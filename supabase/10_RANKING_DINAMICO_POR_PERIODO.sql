-- ============================================
-- 10_RANKING_DINAMICO_POR_PERIODO.sql
-- Ranking por periodo con reglas estrictas:
-- - Solo sesiones completadas
-- - Exactamente 100 preguntas
-- - Todas las materias de la categoria (Oficiales/Suboficiales)
-- - +1 punto por respuesta correcta
-- - Orden configurable:
--   * promedio (default): puntos_totales / practicas_validas
--   * puntaje_maximo: mejor puntaje individual dentro del periodo
-- ============================================

BEGIN;
SET search_path TO public;

DROP FUNCTION IF EXISTS public.obtener_ranking_periodo(
  text,
  text,
  integer,
  integer,
  text
);
DROP FUNCTION IF EXISTS public.obtener_ranking_periodo(
  text,
  text,
  integer,
  integer
);

CREATE OR REPLACE FUNCTION public.obtener_ranking_periodo(
  p_categoria text,
  p_modo text DEFAULT 'semana',
  p_dias integer DEFAULT NULL,
  p_limite integer DEFAULT 5000,
  p_criterio text DEFAULT 'promedio'
)
RETURNS TABLE (
  usuario_id uuid,
  nombre_completo text,
  categoria text,
  puntos_promedio numeric,
  puntaje_maximo integer,
  puntos_totales integer,
  efectividad numeric,
  practicas_para_ranking integer,
  ultima_practica timestamp,
  posicion bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_modo text;
  v_dias integer;
  v_limite integer;
  v_criterio text;
BEGIN
  v_modo := lower(coalesce(trim(p_modo), 'semana'));
  IF v_modo NOT IN ('ultima_practica', 'semana', 'mes', 'dias', 'todas') THEN
    v_modo := 'semana';
  END IF;

  v_dias := greatest(coalesce(p_dias, 1), 1);
  v_limite := greatest(coalesce(p_limite, 50), 1);

  v_criterio := lower(coalesce(trim(p_criterio), 'promedio'));
  IF v_criterio NOT IN ('promedio', 'puntaje_maximo') THEN
    v_criterio := 'promedio';
  END IF;

  RETURN QUERY
  WITH params AS (
    SELECT
      CASE
        WHEN lower(coalesce(p_categoria, '')) LIKE '%suboficial%' THEN 'suboficial'
        WHEN lower(coalesce(p_categoria, '')) LIKE '%oficial%' THEN 'oficial'
        ELSE NULL
      END AS categoria_norm,
      v_modo AS modo,
      v_dias AS dias,
      v_criterio AS criterio
  ),
  materias_requeridas AS (
    SELECT
      COALESCE(
        array_agg(DISTINCT p.materia_id) FILTER (
          WHERE p.activo = true
            AND p.materia_id IS NOT NULL
            AND (
              (pr.categoria_norm = 'oficial' AND p.codigo_pregunta LIKE 'OFI-%') OR
              (pr.categoria_norm = 'suboficial' AND p.codigo_pregunta LIKE 'SUB-%')
            )
        ),
        '{}'::uuid[]
      ) AS required_ids,
      COUNT(DISTINCT p.materia_id) FILTER (
        WHERE p.activo = true
          AND p.materia_id IS NOT NULL
          AND (
            (pr.categoria_norm = 'oficial' AND p.codigo_pregunta LIKE 'OFI-%') OR
            (pr.categoria_norm = 'suboficial' AND p.codigo_pregunta LIKE 'SUB-%')
          )
      )::int AS required_count
    FROM pregunta p
    CROSS JOIN params pr
  ),
  usuarios_categoria AS (
    SELECT
      u.id AS usuario_id,
      COALESCE(NULLIF(trim(u.nombre_completo), ''), 'Usuario') AS nombre_completo,
      COALESCE(NULLIF(trim(u.metadata ->> 'categoria'), ''), 'General') AS categoria
    FROM usuario u
    CROSS JOIN params pr
    WHERE
      pr.categoria_norm IS NULL
      OR (
        pr.categoria_norm = 'suboficial'
        AND lower(coalesce(u.metadata ->> 'categoria', '')) LIKE '%suboficial%'
      )
      OR (
        pr.categoria_norm = 'oficial'
        AND lower(coalesce(u.metadata ->> 'categoria', '')) LIKE '%oficial%'
        AND lower(coalesce(u.metadata ->> 'categoria', '')) NOT LIKE '%suboficial%'
      )
      OR (
        pr.categoria_norm IS NOT NULL
        AND coalesce(trim(u.metadata ->> 'categoria'), '') = ''
      )
  ),
  sesiones_candidatas AS (
    SELECT
      sp.usuario_id,
      coalesce(sp.fecha_fin, sp.creado_at, sp.fecha_inicio) AS fecha_ref,
      coalesce(sp.total_preguntas_planeadas, sp.preguntas_respondidas, 0)::int AS planeadas,
      coalesce(
        sp.preguntas_respondidas,
        coalesce(sp.preguntas_correctas, 0) +
          coalesce(sp.preguntas_incorrectas, 0) +
          coalesce(sp.preguntas_omitidas, 0),
        0
      )::int AS respondidas,
      coalesce(sp.preguntas_correctas, 0)::int AS correctas
    FROM sesion_practica sp
    JOIN usuarios_categoria uc ON uc.usuario_id = sp.usuario_id
    CROSS JOIN materias_requeridas mr
    WHERE
      sp.completada = true
      AND mr.required_count > 0
      AND coalesce(array_length(sp.materias_incluidas, 1), 0) = mr.required_count
      AND sp.materias_incluidas @> mr.required_ids
      AND sp.materias_incluidas <@ mr.required_ids
  ),
  sesiones_validas AS (
    SELECT sc.*
    FROM sesiones_candidatas sc
    WHERE sc.planeadas = 100
      AND sc.respondidas = 100
  ),
  sesiones_periodizadas AS (
    SELECT
      sv.*,
      row_number() OVER (
        PARTITION BY sv.usuario_id
        ORDER BY sv.fecha_ref DESC, sv.usuario_id
      ) AS rn
    FROM sesiones_validas sv
    CROSS JOIN params pr
    WHERE
      pr.modo = 'ultima_practica'
      OR pr.modo = 'todas'
      OR (
        pr.modo = 'semana'
        AND sv.fecha_ref >= now() - interval '7 days'
      )
      OR (
        pr.modo = 'mes'
        AND sv.fecha_ref >= now() - interval '30 days'
      )
      OR (
        pr.modo = 'dias'
        AND sv.fecha_ref >= now() - make_interval(days => pr.dias)
      )
  ),
  sesiones_filtradas AS (
    SELECT sp.*
    FROM sesiones_periodizadas sp
    CROSS JOIN params pr
    WHERE pr.modo <> 'ultima_practica' OR sp.rn = 1
  ),
  agregados AS (
    SELECT
      sf.usuario_id,
      round((sum(sf.correctas)::numeric / nullif(count(*), 0)), 2) AS puntos_promedio,
      max(sf.correctas)::int AS puntaje_maximo,
      sum(sf.correctas)::int AS puntos_totales,
      round((sum(sf.correctas)::numeric * 100.0) / nullif(sum(sf.respondidas), 0), 2) AS efectividad,
      count(*)::int AS practicas_para_ranking,
      max(sf.fecha_ref)::timestamp AS ultima_practica
    FROM sesiones_filtradas sf
    GROUP BY sf.usuario_id
  ),
  ordenado AS (
    SELECT
      a.*,
      row_number() OVER (
        ORDER BY
          CASE
            WHEN pr.criterio = 'puntaje_maximo' THEN a.puntaje_maximo::numeric
            ELSE a.puntos_promedio
          END DESC,
          CASE
            WHEN pr.criterio = 'puntaje_maximo' THEN a.puntos_promedio
            ELSE a.efectividad
          END DESC,
          CASE
            WHEN pr.criterio = 'puntaje_maximo' THEN a.efectividad
            ELSE a.puntos_totales::numeric
          END DESC,
          a.ultima_practica DESC,
          a.usuario_id
      ) AS posicion
    FROM agregados a
    CROSS JOIN params pr
  )
  SELECT
    o.usuario_id,
    uc.nombre_completo,
    uc.categoria,
    o.puntos_promedio,
    o.puntaje_maximo,
    o.puntos_totales,
    o.efectividad,
    o.practicas_para_ranking,
    o.ultima_practica,
    o.posicion
  FROM ordenado o
  JOIN usuarios_categoria uc ON uc.usuario_id = o.usuario_id
  ORDER BY o.posicion
  LIMIT v_limite;
END;
$$;

REVOKE ALL ON FUNCTION public.obtener_ranking_periodo(
  text,
  text,
  integer,
  integer,
  text
) FROM public;
GRANT EXECUTE ON FUNCTION public.obtener_ranking_periodo(
  text,
  text,
  integer,
  integer,
  text
) TO authenticated;

COMMIT;

-- Ejemplos:
-- SELECT * FROM public.obtener_ranking_periodo('Oficiales PNP', 'ultima_practica', NULL, 100, 'promedio');
-- SELECT * FROM public.obtener_ranking_periodo('Oficiales PNP', 'semana', NULL, 100, 'puntaje_maximo');
-- SELECT * FROM public.obtener_ranking_periodo('Oficiales PNP', 'todas', NULL, 100, 'puntaje_maximo');
-- SELECT * FROM public.obtener_ranking_periodo('Suboficiales PNP', 'dias', 2, 100, 'promedio');
