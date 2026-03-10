-- ============================================
-- 27_TUTOR_IA_VELOCIDAD_RPC.sql
-- Objetivo:
-- Mover el calculo del Coach de Velocidad a SQL para reducir
-- latencia de red y CPU en cliente.
-- ============================================

BEGIN;
SET search_path TO public;

-- Lectura reciente por usuario para panel de velocidad.
CREATE INDEX IF NOT EXISTS idx_respuesta_usuario_usuario_respondida_desc
ON public.respuesta_usuario (usuario_id, respondida_at DESC);

-- Este indice parcial de velocidad era potencialmente poco usado con la
-- forma actual de la query; lo retiramos para evitar costo de escritura.
DROP INDEX IF EXISTS public.idx_respuesta_usuario_velocidad_valida;

-- Ventana valida para acierto (no exige tiempo de respuesta).
CREATE INDEX IF NOT EXISTS idx_respuesta_usuario_accuracy_valida
ON public.respuesta_usuario (usuario_id, respondida_at DESC, pregunta_id)
WHERE fue_omitida IS DISTINCT FROM true
  AND es_correcta IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fn_tutor_velocidad_dashboard(
  p_usuario_id uuid,
  p_ventana integer DEFAULT 1200,
  p_muestra_minima integer DEFAULT 10,
  p_half_life_dias numeric DEFAULT 14
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_ventana integer := greatest(least(coalesce(p_ventana, 1200), 5000), 100);
  v_muestra_min integer := greatest(least(coalesce(p_muestra_minima, 10), 500), 1);
  v_half_life numeric := greatest(least(coalesce(p_half_life_dias, 14), 365), 1);
  v_payload jsonb;
BEGIN
  IF p_usuario_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  IF v_role <> 'service_role' THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'No autenticado para consultar este dashboard';
    END IF;
    IF v_uid IS DISTINCT FROM p_usuario_id THEN
      RAISE EXCEPTION 'No autorizado para consultar este dashboard';
    END IF;
  END IF;

  WITH base AS (
    SELECT
      ru.pregunta_id::text AS pregunta_id,
      ru.tiempo_total_respuesta::numeric AS tiempo_segundos,
      ru.es_correcta,
      ru.fue_omitida,
      ru.respondida_at,
      coalesce(m.nombre, 'Materia sin nombre') AS materia,
      p.numero_oficial,
      coalesce(trim(p.codigo_pregunta), '') AS codigo_pregunta,
      coalesce(trim(p.enunciado), '') AS enunciado
    FROM public.respuesta_usuario ru
    JOIN public.pregunta p ON p.id = ru.pregunta_id
    LEFT JOIN public.materia m ON m.id = p.materia_id
    WHERE ru.usuario_id = p_usuario_id
      AND ru.fue_omitida IS DISTINCT FROM true
      AND ru.es_correcta IS NOT NULL
    ORDER BY ru.respondida_at DESC NULLS LAST
    LIMIT v_ventana
  ),
  valid_accuracy AS (
    SELECT *
    FROM base
    WHERE coalesce(trim(materia), '') <> ''
  ),
  valid_speed AS (
    SELECT
      *,
      power(
        0.5::numeric,
        greatest(
          0::numeric,
          extract(epoch from (v_now - coalesce(respondida_at, v_now))) / 86400.0
        ) / v_half_life::numeric
      ) AS peso_recencia
    FROM valid_accuracy
    WHERE coalesce(tiempo_segundos, 0) > 0
  ),
  global_accuracy AS (
    SELECT
      count(*)::int AS respuestas_validas,
      count(*) FILTER (WHERE es_correcta = true)::int AS correctas
    FROM valid_accuracy
  ),
  global_speed AS (
    SELECT
      count(*)::int AS muestra,
      count(*) FILTER (WHERE tiempo_segundos < 8)::int AS imp_count,
      count(*) FILTER (WHERE tiempo_segundos >= 8 AND tiempo_segundos <= 20)::int AS opt_count,
      count(*) FILTER (WHERE tiempo_segundos > 20)::int AS lenta_count,
      coalesce(sum(tiempo_segundos * peso_recencia), 0)::numeric AS suma_pond,
      coalesce(sum(peso_recencia), 0)::numeric AS peso_total,
      coalesce(sum(peso_recencia) FILTER (WHERE tiempo_segundos < 8), 0)::numeric AS imp_peso,
      coalesce(sum(peso_recencia) FILTER (WHERE tiempo_segundos >= 8 AND tiempo_segundos <= 20), 0)::numeric AS opt_peso,
      coalesce(sum(peso_recencia) FILTER (WHERE tiempo_segundos > 20), 0)::numeric AS lenta_peso
    FROM valid_speed
  ),
  materia_accuracy AS (
    SELECT
      materia,
      count(*)::int AS respuestas_validas,
      count(*) FILTER (WHERE es_correcta = true)::int AS correctas_validas
    FROM valid_accuracy
    GROUP BY materia
  ),
  materia_speed AS (
    SELECT
      materia,
      count(*)::int AS muestra_valida,
      coalesce(sum(tiempo_segundos * peso_recencia), 0)::numeric AS suma_pond,
      coalesce(sum(peso_recencia), 0)::numeric AS peso_total,
      coalesce(sum(peso_recencia) FILTER (WHERE tiempo_segundos < 8), 0)::numeric AS imp_peso,
      coalesce(sum(peso_recencia) FILTER (WHERE tiempo_segundos >= 8 AND tiempo_segundos <= 20), 0)::numeric AS opt_peso,
      coalesce(sum(peso_recencia) FILTER (WHERE tiempo_segundos > 20), 0)::numeric AS lenta_peso
    FROM valid_speed
    GROUP BY materia
  ),
  materia_base AS (
    SELECT
      ma.materia,
      ma.respuestas_validas,
      ma.correctas_validas,
      coalesce(ms.muestra_valida, 0)::int AS muestra_valida,
      coalesce(ms.suma_pond, 0)::numeric AS suma_pond,
      coalesce(ms.peso_total, 0)::numeric AS peso_total,
      coalesce(ms.imp_peso, 0)::numeric AS imp_peso,
      coalesce(ms.opt_peso, 0)::numeric AS opt_peso,
      coalesce(ms.lenta_peso, 0)::numeric AS lenta_peso
    FROM materia_accuracy ma
    LEFT JOIN materia_speed ms ON ms.materia = ma.materia
  ),
  promedio_global AS (
    SELECT
      CASE
        WHEN gs.peso_total > 0 THEN gs.suma_pond / gs.peso_total
        ELSE 0::numeric
      END AS promedio_global
    FROM global_speed gs
  ),
  materia_rank AS (
    SELECT
      mb.materia,
      CASE WHEN mb.peso_total > 0 THEN mb.suma_pond / mb.peso_total ELSE 0::numeric END AS promedio_segundos,
      mb.muestra_valida,
      mb.respuestas_validas,
      mb.correctas_validas,
      CASE WHEN mb.peso_total > 0 THEN (mb.imp_peso * 100.0) / mb.peso_total ELSE 0::numeric END AS pct_impulsiva,
      CASE WHEN mb.peso_total > 0 THEN (mb.opt_peso * 100.0) / mb.peso_total ELSE 0::numeric END AS pct_optima,
      CASE WHEN mb.peso_total > 0 THEN (mb.lenta_peso * 100.0) / mb.peso_total ELSE 0::numeric END AS pct_lenta,
      CASE WHEN mb.respuestas_validas > 0 THEN (mb.correctas_validas * 100.0) / mb.respuestas_validas ELSE 0::numeric END AS tasa_acierto,
      (
        (CASE WHEN mb.peso_total > 0 THEN mb.suma_pond / mb.peso_total ELSE 0::numeric END) * mb.muestra_valida
        + (pg.promedio_global * 20.0)
      ) / nullif(mb.muestra_valida + 20.0, 0) AS promedio_ajustado,
      least(
        mb.muestra_valida::numeric /
        v_muestra_min::numeric,
        1.0
      ) AS confiabilidad
    FROM materia_base mb
    CROSS JOIN promedio_global pg
    WHERE mb.muestra_valida >= v_muestra_min
      AND mb.peso_total > 0
  ),
  materias_json AS (
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'materia', mr.materia,
            'promedio_segundos', round(mr.promedio_segundos, 3),
            'promedio_ajustado', round(mr.promedio_ajustado, 3),
            'score_ranking', round((mr.promedio_ajustado * mr.confiabilidad), 3),
            'preguntas', mr.muestra_valida,
            'muestra_valida', mr.muestra_valida,
            'respuestas_validas', mr.respuestas_validas,
            'pct_impulsiva', round(mr.pct_impulsiva, 2),
            'pct_optima', round(mr.pct_optima, 2),
            'pct_lenta', round(mr.pct_lenta, 2),
            'tasa_acierto', round(mr.tasa_acierto, 2),
            'clasificacion', CASE
              WHEN mr.promedio_segundos < 8 THEN 'Impulsivo'
              WHEN mr.promedio_segundos <= 20 THEN 'Optimo'
              ELSE 'Lento'
            END,
            'confianza_muestra', CASE
              WHEN mr.muestra_valida >= (v_muestra_min * 3) THEN 'Alta'
              WHEN mr.muestra_valida >= v_muestra_min THEN 'Media'
              ELSE 'Baja'
            END
          )
          ORDER BY (mr.promedio_ajustado * mr.confiabilidad) DESC, mr.muestra_valida DESC
        ),
        '[]'::jsonb
      ) AS data
    FROM materia_rank mr
  ),
  pregunta_base AS (
    SELECT
      vs.pregunta_id,
      vs.materia,
      max(vs.numero_oficial) AS numero_oficial,
      max(vs.codigo_pregunta) AS codigo_pregunta,
      max(vs.enunciado) AS enunciado,
      count(*)::int AS intentos,
      sum(vs.tiempo_segundos)::numeric AS total_segundos,
      sum(vs.tiempo_segundos * vs.peso_recencia)::numeric AS total_ponderado_segundos,
      sum(vs.peso_recencia)::numeric AS peso_total,
      CASE
        WHEN sum(vs.peso_recencia) > 0 THEN sum(vs.tiempo_segundos * vs.peso_recencia) / sum(vs.peso_recencia)
        ELSE 0::numeric
      END AS promedio_segundos,
      count(*) FILTER (WHERE vs.es_correcta = false)::int AS incorrectas,
      count(*) FILTER (WHERE vs.es_correcta = true)::int AS correctas
    FROM valid_speed vs
    GROUP BY vs.pregunta_id, vs.materia
  ),
  preguntas_json AS (
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'pregunta_id', pb.pregunta_id,
            'numero', coalesce(pb.numero_oficial, 0),
            'codigo_pregunta', coalesce(pb.codigo_pregunta, ''),
            'texto', CASE
              WHEN coalesce(pb.enunciado, '') <> '' THEN left(regexp_replace(pb.enunciado, '\\s+', ' ', 'g'), 130)
              WHEN coalesce(pb.codigo_pregunta, '') <> '' THEN pb.codigo_pregunta
              ELSE 'Pregunta'
            END,
            'materia', pb.materia,
            'intentos', pb.intentos,
            'promedio_segundos', round(pb.promedio_segundos, 3),
            'total_segundos', round(pb.total_segundos, 3),
            'tasa_error', round((CASE WHEN pb.intentos > 0 THEN (pb.incorrectas * 100.0) / pb.intentos ELSE 0 END)::numeric, 2),
            'tasa_acierto', round((CASE WHEN pb.intentos > 0 THEN (pb.correctas * 100.0) / pb.intentos ELSE 0 END)::numeric, 2)
          )
        ),
        '[]'::jsonb
      ) AS data
    FROM (
      SELECT *
      FROM pregunta_base
      ORDER BY promedio_segundos DESC, intentos DESC, total_segundos DESC
      LIMIT 10
    ) pb
  )
  SELECT
    jsonb_build_object(
      'metricas_velocidad',
      jsonb_build_object(
        'promedio_segundos', round((CASE WHEN gs.peso_total > 0 THEN gs.suma_pond / gs.peso_total ELSE 0 END)::numeric, 3),
        'clasificacion', CASE
          WHEN (CASE WHEN gs.peso_total > 0 THEN gs.suma_pond / gs.peso_total ELSE 0 END) < 8 THEN 'Impulsivo'
          WHEN (CASE WHEN gs.peso_total > 0 THEN gs.suma_pond / gs.peso_total ELSE 0 END) <= 20 THEN 'Optimo'
          ELSE 'Lento'
        END,
        'total_respuestas', gs.muestra,
        'respuestas_validas_acierto', ga.respuestas_validas,
        'tasa_acierto_global', round((CASE WHEN ga.respuestas_validas > 0 THEN (ga.correctas * 100.0) / ga.respuestas_validas ELSE 0 END)::numeric, 2),
        'impulsivas', gs.imp_count,
        'optimas', gs.opt_count,
        'lentas', gs.lenta_count,
        'pct_impulsiva', round((CASE WHEN gs.peso_total > 0 THEN (gs.imp_peso * 100.0) / gs.peso_total ELSE 0 END)::numeric, 2),
        'pct_optima', round((CASE WHEN gs.peso_total > 0 THEN (gs.opt_peso * 100.0) / gs.peso_total ELSE 0 END)::numeric, 2),
        'pct_lenta', round((CASE WHEN gs.peso_total > 0 THEN (gs.lenta_peso * 100.0) / gs.peso_total ELSE 0 END)::numeric, 2),
        'rango_optimo_min', 8,
        'rango_optimo_max', 20,
        'recomendacion', CASE
          WHEN gs.muestra < v_muestra_min
            THEN 'Aun hay poca muestra para decisiones finas. Continua practicando para mejorar precision del coach.'
          WHEN (CASE WHEN gs.peso_total > 0 THEN gs.suma_pond / gs.peso_total ELSE 0 END) < 8
            THEN 'Baja un poco la velocidad y relee palabras clave (NO/EXCEPTO).'
          WHEN (CASE WHEN gs.peso_total > 0 THEN gs.suma_pond / gs.peso_total ELSE 0 END) <= 20
            THEN 'Tu ritmo es saludable. Mantiene precision con lectura activa.'
          ELSE 'Acelera descarte de opciones para ganar tiempo por pregunta.'
        END,
        'confianza_muestra', CASE
          WHEN gs.muestra >= (v_muestra_min * 3) THEN 'Alta'
          WHEN gs.muestra >= v_muestra_min THEN 'Media'
          WHEN gs.muestra > 0 THEN 'Baja'
          ELSE 'Sin datos'
        END,
        'muestra_minima_recomendada', v_muestra_min,
        'ventana_respuestas', v_ventana
      ),
      'materias_tiempo', mj.data,
      'preguntas_lentas', pj.data,
      'preguntas_lentas_ids', coalesce(
        (
          SELECT jsonb_agg(elem ->> 'pregunta_id')
          FROM jsonb_array_elements(pj.data) elem
          WHERE coalesce(elem ->> 'pregunta_id', '') <> ''
        ),
        '[]'::jsonb
      )
    )
  INTO v_payload
  FROM global_speed gs
  CROSS JOIN global_accuracy ga
  CROSS JOIN materias_json mj
  CROSS JOIN preguntas_json pj;

  RETURN coalesce(v_payload, '{}'::jsonb);
END;
$$;

COMMENT ON FUNCTION public.fn_tutor_velocidad_dashboard(uuid, integer, integer, numeric)
IS 'Dashboard de velocidad para Tutor IA: metricas globales, ranking por materia y top preguntas lentas.';

REVOKE ALL ON FUNCTION public.fn_tutor_velocidad_dashboard(uuid, integer, integer, numeric) FROM public;
REVOKE ALL ON FUNCTION public.fn_tutor_velocidad_dashboard(uuid, integer, integer, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_tutor_velocidad_dashboard(uuid, integer, integer, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_tutor_velocidad_dashboard(uuid, integer, integer, numeric) TO service_role;

COMMIT;
