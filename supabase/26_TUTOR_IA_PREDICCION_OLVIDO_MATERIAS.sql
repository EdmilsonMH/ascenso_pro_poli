-- ============================================
-- 26_TUTOR_IA_PREDICCION_OLVIDO_MATERIAS.sql
-- Plan de predicciones (version mejorada)
--
-- Objetivo operativo:
-- 1) Riesgo de olvido consistente (0..100): 100 = alto riesgo.
-- 2) Trigger robusto: crea/actualiza fila aunque la primera respuesta sea incorrecta.
-- 3) Recaculo masivo por usuario/todos para normalizar datos historicos.
-- 4) RPC estable para UI: listado por materias + pregunta_ids priorizados.
-- ============================================

BEGIN;
SET search_path TO public;

-- Validacion minima de esquema.
DO $$
BEGIN
  IF to_regclass('public.prediccion_olvido') IS NULL THEN
    RAISE EXCEPTION 'Falta tabla public.prediccion_olvido';
  END IF;
  IF to_regclass('public.respuesta_usuario') IS NULL THEN
    RAISE EXCEPTION 'Falta tabla public.respuesta_usuario';
  END IF;
  IF to_regclass('public.pregunta') IS NULL THEN
    RAISE EXCEPTION 'Falta tabla public.pregunta';
  END IF;
  IF to_regclass('public.materia') IS NULL THEN
    RAISE EXCEPTION 'Falta tabla public.materia';
  END IF;
END
$$;

-- Indices de rendimiento (escala concurrente).
CREATE INDEX IF NOT EXISTS idx_pred_olvido_usuario_prob_desc
  ON public.prediccion_olvido (usuario_id, probabilidad_olvido DESC);

CREATE INDEX IF NOT EXISTS idx_pred_olvido_usuario_urgente_prob
  ON public.prediccion_olvido (
    usuario_id,
    requiere_revision_inmediata,
    probabilidad_olvido DESC
  );

CREATE INDEX IF NOT EXISTS idx_pred_olvido_usuario_actualizado
  ON public.prediccion_olvido (usuario_id, actualizado_at DESC);

-- ------------------------------------------------------------
-- A) Formula de probabilidad de olvido
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_calcular_probabilidad_olvido(
  p_ultima_correcta timestamp,
  p_veces_correcta integer,
  p_veces_incorrecta integer
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_dias numeric := 0;
  v_correctas numeric := GREATEST(COALESCE(p_veces_correcta, 0), 0);
  v_correctas_efectivas numeric := 0;
  v_incorrectas numeric := GREATEST(COALESCE(p_veces_incorrecta, 0), 0);
  v_base numeric := 0;
  v_penalizacion numeric := 0;
  v_reduccion numeric := 0;
  v_riesgo numeric := 0;
BEGIN
  -- Sin aciertos previos: riesgo alto por defecto.
  IF p_ultima_correcta IS NULL THEN
    RETURN 95;
  END IF;

  v_dias := GREATEST(EXTRACT(EPOCH FROM (NOW() - p_ultima_correcta)) / 86400.0, 0);

  -- Saturacion: muchos aciertos en bloque no deben "inflar" consolidacion indefinidamente.
  v_correctas_efectivas := LN(1 + LEAST(v_correctas, 20));

  -- Curva creciente de riesgo (arranca baja y sube con el tiempo).
  -- Mas consolidacion => sube mas lento el riesgo.
  v_base := 100 * (1 - EXP(-v_dias / (2.4 + (v_correctas_efectivas * 2.2))));

  -- Penaliza historial de errores.
  v_penalizacion := LEAST(v_incorrectas * 3.5, 20);

  -- Reduce riesgo por consolidacion.
  v_reduccion := LEAST(v_correctas_efectivas * 8, 16);

  v_riesgo := v_base + v_penalizacion - v_reduccion;
  v_riesgo := GREATEST(0, LEAST(v_riesgo, 100));

  RETURN v_riesgo;
END;
$$;

COMMENT ON FUNCTION public.fn_calcular_probabilidad_olvido(timestamp, integer, integer)
IS 'Riesgo de olvido 0..100 (100 = alto riesgo), ponderado por tiempo, aciertos e incorrectas, con saturacion de consolidacion.';

-- ------------------------------------------------------------
-- B) Helper central de estado (evita duplicacion de reglas)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_estado_prediccion_olvido(
  p_ultima_correcta timestamp,
  p_veces_correcta integer,
  p_veces_incorrecta integer,
  p_now timestamp
)
RETURNS TABLE (
  probabilidad_olvido numeric,
  dias_desde_ultima_correcta numeric,
  factor_consolidacion numeric,
  nivel_consolidacion text,
  urgencia_revision text,
  requiere_revision_inmediata boolean,
  fecha_revision_optima timestamp
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_correctas integer := GREATEST(COALESCE(p_veces_correcta, 0), 0);
  v_correctas_efectivas numeric := LN(1 + LEAST(v_correctas::numeric, 20));
  v_now timestamp := COALESCE(p_now, NOW());
  v_riesgo numeric := COALESCE(
    public.fn_calcular_probabilidad_olvido(
      p_ultima_correcta,
      p_veces_correcta,
      p_veces_incorrecta
    ),
    0
  );
BEGIN
  probabilidad_olvido := v_riesgo;

  dias_desde_ultima_correcta := CASE
    WHEN p_ultima_correcta IS NULL THEN NULL
    ELSE GREATEST(EXTRACT(EPOCH FROM (v_now - p_ultima_correcta)) / 86400.0, 0)
  END;

  -- Alineado al mismo modelo de saturacion usado en la probabilidad.
  factor_consolidacion := LEAST((v_correctas_efectivas / LN(21)) * 0.9, 0.9);

  nivel_consolidacion := CASE
    WHEN v_correctas >= 5 THEN 'permanente'
    WHEN v_correctas >= 3 THEN 'consolidado'
    WHEN v_correctas >= 1 THEN 'en_consolidacion'
    ELSE 'fragil'
  END;

  urgencia_revision := CASE
    WHEN v_riesgo >= 85 THEN 'critica'
    WHEN v_riesgo >= 70 THEN 'alta'
    WHEN v_riesgo >= 55 THEN 'media'
    WHEN v_riesgo >= 40 THEN 'baja'
    ELSE 'no_necesaria'
  END;

  requiere_revision_inmediata := v_riesgo >= 70;

  fecha_revision_optima := CASE
    WHEN v_riesgo >= 85 THEN v_now
    WHEN v_riesgo >= 70 THEN v_now + INTERVAL '1 day'
    WHEN v_riesgo >= 55 THEN v_now + INTERVAL '2 day'
    WHEN v_riesgo >= 40 THEN v_now + INTERVAL '4 day'
    ELSE v_now + INTERVAL '7 day'
  END;

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.fn_estado_prediccion_olvido(timestamp, integer, integer, timestamp)
IS 'Deriva estado completo de prediccion (riesgo, urgencia, consolidacion, revision) en un solo punto de verdad.';

-- ------------------------------------------------------------
-- C) Trigger de actualizacion de prediccion
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_actualizar_prediccion_olvido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamp := NOW();
  v_prev public.prediccion_olvido%ROWTYPE;
  v_correctas integer := 0;
  v_incorrectas integer := 0;
  v_ultima_correcta timestamp;
  v_ultima_incorrecta timestamp;
  v_probabilidad numeric := 0;
  v_dias numeric;
  v_factor numeric;
  v_nivel text;
  v_urgencia text;
  v_inmediata boolean;
  v_fecha_optima timestamp;
BEGIN
  IF NEW.usuario_id IS NULL OR NEW.pregunta_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Leemos estado previo para calcular estado final y escribir una sola vez.
  SELECT *
  INTO v_prev
  FROM public.prediccion_olvido po
  WHERE po.usuario_id = NEW.usuario_id
    AND po.pregunta_id = NEW.pregunta_id
  FOR UPDATE;

  IF FOUND THEN
    v_correctas := COALESCE(v_prev.veces_respondida_correcta, 0) +
      CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END;
    v_incorrectas := COALESCE(v_prev.veces_respondida_incorrecta, 0) +
      CASE WHEN COALESCE(NEW.es_correcta, false) THEN 0 ELSE 1 END;
    v_ultima_correcta := CASE
      WHEN NEW.es_correcta THEN v_now
      ELSE v_prev.ultima_respuesta_correcta
    END;
    v_ultima_incorrecta := CASE
      WHEN COALESCE(NEW.es_correcta, false) THEN v_prev.ultima_respuesta_incorrecta
      ELSE v_now
    END;
  ELSE
    v_correctas := CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END;
    v_incorrectas := CASE WHEN COALESCE(NEW.es_correcta, false) THEN 0 ELSE 1 END;
    v_ultima_correcta := CASE WHEN NEW.es_correcta THEN v_now ELSE NULL END;
    v_ultima_incorrecta := CASE WHEN COALESCE(NEW.es_correcta, false) THEN NULL ELSE v_now END;
  END IF;

  SELECT
    e.probabilidad_olvido,
    e.dias_desde_ultima_correcta,
    e.factor_consolidacion,
    e.nivel_consolidacion,
    e.urgencia_revision,
    e.requiere_revision_inmediata,
    e.fecha_revision_optima
  INTO
    v_probabilidad,
    v_dias,
    v_factor,
    v_nivel,
    v_urgencia,
    v_inmediata,
    v_fecha_optima
  FROM public.fn_estado_prediccion_olvido(
    v_ultima_correcta,
    v_correctas,
    v_incorrectas,
    v_now
  ) e;

  -- Una sola escritura (insert o update).
  INSERT INTO public.prediccion_olvido (
    usuario_id,
    pregunta_id,
    ultima_respuesta_correcta,
    ultima_respuesta_incorrecta,
    veces_respondida_correcta,
    veces_respondida_incorrecta,
    probabilidad_olvido,
    dias_desde_ultima_correcta,
    factor_consolidacion,
    nivel_consolidacion,
    urgencia_revision,
    requiere_revision_inmediata,
    fecha_revision_optima,
    calculado_at,
    actualizado_at
  )
  VALUES (
    NEW.usuario_id,
    NEW.pregunta_id,
    v_ultima_correcta,
    v_ultima_incorrecta,
    v_correctas,
    v_incorrectas,
    COALESCE(v_probabilidad, 0),
    v_dias,
    v_factor,
    v_nivel,
    v_urgencia,
    v_inmediata,
    v_fecha_optima,
    v_now,
    v_now
  )
  ON CONFLICT (usuario_id, pregunta_id) DO UPDATE
  SET
    ultima_respuesta_correcta = EXCLUDED.ultima_respuesta_correcta,
    ultima_respuesta_incorrecta = EXCLUDED.ultima_respuesta_incorrecta,
    veces_respondida_correcta = EXCLUDED.veces_respondida_correcta,
    veces_respondida_incorrecta = EXCLUDED.veces_respondida_incorrecta,
    probabilidad_olvido = EXCLUDED.probabilidad_olvido,
    dias_desde_ultima_correcta = EXCLUDED.dias_desde_ultima_correcta,
    factor_consolidacion = EXCLUDED.factor_consolidacion,
    nivel_consolidacion = EXCLUDED.nivel_consolidacion,
    urgencia_revision = EXCLUDED.urgencia_revision,
    requiere_revision_inmediata = EXCLUDED.requiere_revision_inmediata,
    fecha_revision_optima = EXCLUDED.fecha_revision_optima,
    calculado_at = EXCLUDED.calculado_at,
    actualizado_at = EXCLUDED.actualizado_at;

  RETURN NEW;
END;
$$;

-- Forzamos trigger actualizado (idempotente).
DROP TRIGGER IF EXISTS trigger_actualizar_prediccion ON public.respuesta_usuario;
CREATE TRIGGER trigger_actualizar_prediccion
AFTER INSERT ON public.respuesta_usuario
FOR EACH ROW
EXECUTE FUNCTION public.trg_actualizar_prediccion_olvido();

-- ------------------------------------------------------------
-- D) Funciones de recaculo historico
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_recalcular_prediccion_olvido_usuario(
  p_usuario_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actualizadas integer := 0;
BEGIN
  IF p_usuario_id IS NULL THEN
    RETURN 0;
  END IF;

  WITH calc AS (
    SELECT
      po.id,
      e.probabilidad_olvido,
      e.dias_desde_ultima_correcta,
      e.factor_consolidacion,
      e.nivel_consolidacion,
      e.urgencia_revision,
      e.requiere_revision_inmediata,
      e.fecha_revision_optima
    FROM public.prediccion_olvido po
    CROSS JOIN LATERAL public.fn_estado_prediccion_olvido(
      po.ultima_respuesta_correcta,
      po.veces_respondida_correcta,
      po.veces_respondida_incorrecta,
      NOW()
    ) e
    WHERE po.usuario_id = p_usuario_id
  )
  UPDATE public.prediccion_olvido po
  SET
    probabilidad_olvido = calc.probabilidad_olvido,
    dias_desde_ultima_correcta = calc.dias_desde_ultima_correcta,
    factor_consolidacion = calc.factor_consolidacion,
    nivel_consolidacion = calc.nivel_consolidacion,
    urgencia_revision = calc.urgencia_revision,
    requiere_revision_inmediata = calc.requiere_revision_inmediata,
    fecha_revision_optima = calc.fecha_revision_optima,
    calculado_at = NOW(),
    actualizado_at = NOW()
  FROM calc
  WHERE po.id = calc.id;

  GET DIAGNOSTICS v_actualizadas = ROW_COUNT;
  RETURN v_actualizadas;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_recalcular_prediccion_olvido_todos()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actualizadas integer := 0;
BEGIN
  WITH calc AS (
    SELECT
      po.id,
      e.probabilidad_olvido,
      e.dias_desde_ultima_correcta,
      e.factor_consolidacion,
      e.nivel_consolidacion,
      e.urgencia_revision,
      e.requiere_revision_inmediata,
      e.fecha_revision_optima
    FROM public.prediccion_olvido po
    CROSS JOIN LATERAL public.fn_estado_prediccion_olvido(
      po.ultima_respuesta_correcta,
      po.veces_respondida_correcta,
      po.veces_respondida_incorrecta,
      NOW()
    ) e
  )
  UPDATE public.prediccion_olvido po
  SET
    probabilidad_olvido = calc.probabilidad_olvido,
    dias_desde_ultima_correcta = calc.dias_desde_ultima_correcta,
    factor_consolidacion = calc.factor_consolidacion,
    nivel_consolidacion = calc.nivel_consolidacion,
    urgencia_revision = calc.urgencia_revision,
    requiere_revision_inmediata = calc.requiere_revision_inmediata,
    fecha_revision_optima = calc.fecha_revision_optima,
    calculado_at = NOW(),
    actualizado_at = NOW()
  FROM calc
  WHERE po.id = calc.id;

  GET DIAGNOSTICS v_actualizadas = ROW_COUNT;
  RETURN v_actualizadas;
END;
$$;

-- ------------------------------------------------------------
-- E) RPC para UI: prediccion por materias
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_tutor_prediccion_olvido_materias(
  p_usuario_id uuid DEFAULT NULL,
  p_min_prob numeric DEFAULT 40
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_usuario_id uuid;
  v_role text := COALESCE(current_setting('request.jwt.claim.role', true), '');
  v_min_prob numeric := GREATEST(COALESCE(p_min_prob, 40), 0);
  v_max_ids_por_materia integer := 20;
  v_total_preguntas integer := 0;
  v_total_urgentes integer := 0;
  v_materias jsonb := '[]'::jsonb;
  v_top_materia text := '';
BEGIN
  v_usuario_id := COALESCE(p_usuario_id, v_auth_uid);

  -- Bloquea consultas de terceros en contexto sin sesion JWT.
  IF v_auth_uid IS NULL
     AND p_usuario_id IS NOT NULL
     AND v_role <> 'service_role' THEN
    RAISE EXCEPTION 'Acceso no autenticado'
      USING ERRCODE = '42501';
  END IF;

  IF v_usuario_id IS NULL THEN
    RETURN jsonb_build_object(
      'estado', 'sin_sesion',
      'resumen', 'Inicia sesion para ver el listado de materias con riesgo de olvido.',
      'materias', '[]'::jsonb,
      'total_preguntas', 0,
      'total_urgentes', 0
    );
  END IF;

  -- Seguridad: el usuario autenticado solo puede consultar su propio id.
  IF v_auth_uid IS NOT NULL
     AND v_auth_uid <> v_usuario_id
     AND v_role <> 'service_role' THEN
    RAISE EXCEPTION 'No autorizado para consultar este usuario'
      USING ERRCODE = '42501';
  END IF;

  WITH base AS MATERIALIZED (
    SELECT
      po.pregunta_id,
      COALESCE(po.probabilidad_olvido, 0)::numeric AS probabilidad_olvido,
      COALESCE(po.urgencia_revision, '') AS urgencia_revision,
      COALESCE(po.requiere_revision_inmediata, false) AS requiere_revision_inmediata,
      po.fecha_revision_optima,
      COALESCE(m.nombre, 'Materia sin nombre') AS materia
    FROM public.prediccion_olvido po
    LEFT JOIN public.pregunta p ON p.id = po.pregunta_id
    LEFT JOIN public.materia m ON m.id = p.materia_id
    WHERE po.usuario_id = v_usuario_id
      AND COALESCE(po.probabilidad_olvido, 0) >= v_min_prob
  ),
  agg AS (
    SELECT
      materia,
      COUNT(*)::int AS total,
      COUNT(*) FILTER (
        WHERE requiere_revision_inmediata
           OR lower(urgencia_revision) IN ('critica', 'alta', 'urgente')
      )::int AS urgentes,
      AVG(probabilidad_olvido)::numeric(6,2) AS probabilidad_promedio,
      MAX(probabilidad_olvido)::numeric(6,2) AS probabilidad_maxima,
      MIN(fecha_revision_optima) AS proxima_revision,
      ARRAY_AGG(pregunta_id::text ORDER BY probabilidad_olvido DESC)
        FILTER (WHERE rn <= v_max_ids_por_materia) AS pregunta_ids
    FROM (
      SELECT
        b.*,
        ROW_NUMBER() OVER (
          PARTITION BY b.materia
          ORDER BY b.probabilidad_olvido DESC, b.pregunta_id
        ) AS rn
      FROM base b
    ) ranked
    GROUP BY materia
  )
  SELECT
    COALESCE(SUM(agg.total), 0)::int AS total_preguntas,
    COALESCE(SUM(agg.urgentes), 0)::int AS total_urgentes,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'materia', agg.materia,
          'total', agg.total,
          'urgentes', agg.urgentes,
          'probabilidad_promedio', agg.probabilidad_promedio,
          'probabilidad_maxima', agg.probabilidad_maxima,
          'proxima_revision',
            CASE
              WHEN agg.proxima_revision IS NULL THEN ''
              ELSE to_char(agg.proxima_revision, 'YYYY-MM-DD')
            END,
          'pregunta_ids', COALESCE(to_jsonb(agg.pregunta_ids), '[]'::jsonb)
        )
        ORDER BY agg.urgentes DESC, agg.probabilidad_maxima DESC, agg.total DESC
      ),
      '[]'::jsonb
    ),
    COALESCE(
      (
        SELECT a2.materia
        FROM agg a2
        ORDER BY a2.urgentes DESC, a2.probabilidad_maxima DESC, a2.total DESC
        LIMIT 1
      ),
      ''
    )
  INTO v_total_preguntas, v_total_urgentes, v_materias, v_top_materia
  FROM agg;

  IF v_total_preguntas = 0 THEN
    RETURN jsonb_build_object(
      'estado', 'sin_datos',
      'resumen', 'No hay materias con riesgo de olvido alto por ahora.',
      'materias', '[]'::jsonb,
      'total_preguntas', 0,
      'total_urgentes', 0
    );
  END IF;

  RETURN jsonb_build_object(
    'estado', 'ok',
    'resumen',
      'Se detectaron ' || v_total_preguntas || ' preguntas con riesgo de olvido en '
      || COALESCE(jsonb_array_length(v_materias), 0) || ' materias. Urgentes: '
      || v_total_urgentes || '. Materia mas expuesta: ' || COALESCE(v_top_materia, 'N/A') || '.',
    'materias', COALESCE(v_materias, '[]'::jsonb),
    'total_preguntas', v_total_preguntas,
    'total_urgentes', v_total_urgentes
  );
END;
$$;

-- Permisos.
REVOKE ALL ON FUNCTION public.fn_tutor_prediccion_olvido_materias(uuid, numeric) FROM public;
REVOKE ALL ON FUNCTION public.fn_tutor_prediccion_olvido_materias(uuid, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_tutor_prediccion_olvido_materias(uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_tutor_prediccion_olvido_materias(uuid, numeric) TO service_role;

REVOKE ALL ON FUNCTION public.fn_estado_prediccion_olvido(timestamp, integer, integer, timestamp) FROM public;
REVOKE ALL ON FUNCTION public.fn_estado_prediccion_olvido(timestamp, integer, integer, timestamp) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_estado_prediccion_olvido(timestamp, integer, integer, timestamp) TO service_role;

REVOKE ALL ON FUNCTION public.fn_recalcular_prediccion_olvido_usuario(uuid) FROM public;
REVOKE ALL ON FUNCTION public.fn_recalcular_prediccion_olvido_usuario(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_recalcular_prediccion_olvido_usuario(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_recalcular_prediccion_olvido_usuario(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.fn_recalcular_prediccion_olvido_todos() FROM public;
REVOKE ALL ON FUNCTION public.fn_recalcular_prediccion_olvido_todos() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_recalcular_prediccion_olvido_todos() TO service_role;

COMMIT;

-- Post-deploy recomendado:
-- SELECT public.fn_recalcular_prediccion_olvido_todos();
