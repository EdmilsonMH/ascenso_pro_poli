-- ============================================
-- 14_RANKING_MEJOR_PUNTAJE_FAST.sql
-- Fast path para filtro "Mejor puntaje"
-- Usa datos persistidos en ranking + estadistica_usuario
-- ============================================

BEGIN;
SET search_path TO public;

DROP FUNCTION IF EXISTS public.obtener_ranking_mejor_puntaje(
  text,
  integer
);

CREATE OR REPLACE FUNCTION public.obtener_ranking_mejor_puntaje(
  p_categoria text,
  p_limite integer DEFAULT 5000
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
  v_limite integer := GREATEST(COALESCE(p_limite, 50), 1);
BEGIN
  RETURN QUERY
  WITH params AS (
    SELECT CASE
      WHEN lower(coalesce(p_categoria, '')) LIKE '%suboficial%' THEN 'suboficial'
      WHEN lower(coalesce(p_categoria, '')) LIKE '%oficial%' THEN 'oficial'
      ELSE NULL
    END AS categoria_norm
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
  base AS (
    SELECT
      r.usuario_id,
      COALESCE(r.promedio_simulacros, 0)::numeric AS puntos_promedio,
      GREATEST(
        COALESCE(r.mejor_puntaje_simulacro, 0),
        COALESCE(eu.mejor_puntaje_simulacro, 0)
      )::int AS puntaje_maximo,
      COALESCE(r.puntos_totales, 0)::int AS puntos_totales,
      COALESCE(r.promedio_simulacros, 0)::numeric AS efectividad,
      COALESCE(r.simulacros_100_completados, 0)::int AS practicas_para_ranking,
      COALESCE(r.calculo_ranking_at, r.actualizado_at)::timestamp AS ultima_practica
    FROM ranking r
    JOIN usuarios_categoria uc ON uc.usuario_id = r.usuario_id
    LEFT JOIN estadistica_usuario eu ON eu.usuario_id = r.usuario_id
    WHERE COALESCE(r.simulacros_100_completados, 0) > 0
  ),
  ordenado AS (
    SELECT
      b.*,
      row_number() OVER (
        ORDER BY
          b.puntaje_maximo DESC,
          b.puntos_promedio DESC,
          b.efectividad DESC,
          b.ultima_practica DESC,
          b.usuario_id
      ) AS posicion
    FROM base b
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

REVOKE ALL ON FUNCTION public.obtener_ranking_mejor_puntaje(
  text,
  integer
) FROM public;
GRANT EXECUTE ON FUNCTION public.obtener_ranking_mejor_puntaje(
  text,
  integer
) TO authenticated;

COMMIT;

