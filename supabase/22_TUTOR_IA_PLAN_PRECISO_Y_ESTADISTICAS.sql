-- ============================================
-- 22_TUTOR_IA_PLAN_PRECISO_Y_ESTADISTICAS.sql
-- Objetivo:
-- 1) Plan adaptativo preciso (sin selecciones ambiguas)
-- 2) Estadisticas de sesion para alimentar Tutor IA
-- ============================================

BEGIN;
SET search_path TO public;

-- ------------------------------------------------------------
-- 1) Plan adaptativo preciso
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_generar_plan_adaptativo(
  p_usuario_id uuid,
  p_fecha_objetivo date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_plan jsonb;
  v_fecha_examen date;
  v_fecha_objetivo date;
  v_dias_restantes integer := 60;
  v_dia_numero integer := 1;
  v_preguntas_faltantes integer := 3000;
  v_cantidad_nuevas integer := 12;
  v_cantidad_repaso integer := 8;
  v_total_dia integer := 20;
  v_preguntas_nuevas uuid[] := '{}'::uuid[];
  v_preguntas_repaso uuid[] := '{}'::uuid[];
  v_preguntas_prioritarias uuid[] := '{}'::uuid[];
  v_materias_debiles uuid[] := '{}'::uuid[];
  v_mensaje text;
BEGIN
  IF p_usuario_id IS NULL THEN
    RAISE EXCEPTION 'p_usuario_id requerido';
  END IF;

  SELECT
    u.fecha_examen_objetivo,
    GREATEST(COALESCE((CURRENT_DATE - u.fecha_registro::date)::int + 1, 1), 1)
  INTO v_fecha_examen, v_dia_numero
  FROM public.usuario u
  WHERE u.id = p_usuario_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuario no encontrado para p_usuario_id=%', p_usuario_id;
  END IF;

  v_fecha_objetivo := COALESCE(p_fecha_objetivo, v_fecha_examen, CURRENT_DATE + 60);
  v_dias_restantes := GREATEST(COALESCE((v_fecha_objetivo - CURRENT_DATE)::int, 60), 1);

  SELECT GREATEST(3000 - COUNT(*), 0)
  INTO v_preguntas_faltantes
  FROM public.exposicion_pregunta ep
  WHERE ep.usuario_id = p_usuario_id
    AND ep.estado_dominio IN ('dominada', 'consolidando');

  v_total_dia := CEIL(v_preguntas_faltantes::numeric / v_dias_restantes);
  v_total_dia := GREATEST(20, LEAST(v_total_dia, 100));

  v_cantidad_nuevas := CEIL(v_total_dia * 0.60);
  v_cantidad_repaso := GREATEST(v_total_dia - v_cantidad_nuevas, 0);

  WITH nuevas AS (
    SELECT p.id
    FROM public.pregunta p
    WHERE p.activo = true
      AND NOT EXISTS (
        SELECT 1
        FROM public.exposicion_pregunta ep
        WHERE ep.usuario_id = p_usuario_id
          AND ep.pregunta_id = p.id
      )
    ORDER BY
      COALESCE(p.score_importancia, 0) DESC,
      COALESCE(p.frecuencia_examen_real, 0) DESC,
      COALESCE(p.numero_oficial, 999999) ASC,
      p.id
    LIMIT v_cantidad_nuevas
  )
  SELECT COALESCE(array_agg(n.id), '{}'::uuid[])
  INTO v_preguntas_nuevas
  FROM nuevas n;

  WITH repaso AS (
    SELECT cr.pregunta_id
    FROM public.cola_repaso_inteligente cr
    JOIN public.pregunta p ON p.id = cr.pregunta_id
    WHERE cr.usuario_id = p_usuario_id
      AND cr.en_cola = true
      AND p.activo = true
      AND cr.proxima_revision_optima <= NOW() + INTERVAL '1 day'
    ORDER BY
      COALESCE(cr.prioridad_urgencia, 0) DESC,
      cr.proxima_revision_optima ASC,
      cr.pregunta_id
    LIMIT v_cantidad_repaso
  )
  SELECT COALESCE(array_agg(r.pregunta_id), '{}'::uuid[])
  INTO v_preguntas_repaso
  FROM repaso r;

  WITH materias AS (
    SELECT dm.materia_id
    FROM public.dominio_materia dm
    WHERE dm.usuario_id = p_usuario_id
      AND dm.materia_id IS NOT NULL
      AND COALESCE(dm.tasa_dominio, 100) < 60
    ORDER BY
      COALESCE(dm.tasa_dominio, 100) ASC,
      COALESCE(dm.total_incorrectas, 0) DESC,
      dm.materia_id
    LIMIT 10
  )
  SELECT COALESCE(array_agg(m.materia_id), '{}'::uuid[])
  INTO v_materias_debiles
  FROM materias m;

  SELECT COALESCE(
    array_agg(d.id ORDER BY d.fuente, d.orden_idx),
    '{}'::uuid[]
  )
  INTO v_preguntas_prioritarias
  FROM (
    SELECT DISTINCT ON (z.id)
      z.id,
      z.fuente,
      z.orden_idx
    FROM (
      SELECT
        u1.id,
        1 AS fuente,
        u1.ord AS orden_idx
      FROM unnest(COALESCE(v_preguntas_repaso, '{}'::uuid[])) WITH ORDINALITY AS u1(id, ord)
      UNION ALL
      SELECT
        u2.id,
        2 AS fuente,
        u2.ord AS orden_idx
      FROM unnest(COALESCE(v_preguntas_nuevas, '{}'::uuid[])) WITH ORDINALITY AS u2(id, ord)
    ) z
    WHERE z.id IS NOT NULL
    ORDER BY z.id, z.fuente, z.orden_idx
  ) d;

  v_mensaje := CASE
    WHEN v_dias_restantes <= 30 THEN
      'URGENTE: quedan ' || v_dias_restantes || ' dias. Prioriza repaso critico y ejecucion diaria.'
    WHEN v_dias_restantes <= 60 THEN
      'Tiempo moderado: ' || v_dias_restantes || ' dias. Mantiene ritmo diario y control de errores.'
    ELSE
      'Buen margen: ' || v_dias_restantes || ' dias. Enfoque en constancia y consolidacion.'
  END;

  INSERT INTO public.plan_estudio_diario (
    usuario_id,
    dia_numero,
    fecha_objetivo,
    preguntas_nuevas,
    cantidad_nuevas,
    preguntas_repaso,
    cantidad_repaso,
    materias_prioritarias,
    razon_priorizacion,
    mensaje_motivacional,
    actualizado_at
  )
  VALUES (
    p_usuario_id,
    v_dia_numero,
    CURRENT_DATE,
    v_preguntas_nuevas,
    COALESCE(array_length(v_preguntas_nuevas, 1), 0),
    v_preguntas_repaso,
    COALESCE(array_length(v_preguntas_repaso, 1), 0),
    v_materias_debiles,
    'Plan calculado por ritmo restante + dominio por materia + cola de repaso.',
    v_mensaje,
    NOW()
  )
  ON CONFLICT (usuario_id, dia_numero) DO UPDATE SET
    fecha_objetivo = EXCLUDED.fecha_objetivo,
    preguntas_nuevas = EXCLUDED.preguntas_nuevas,
    cantidad_nuevas = EXCLUDED.cantidad_nuevas,
    preguntas_repaso = EXCLUDED.preguntas_repaso,
    cantidad_repaso = EXCLUDED.cantidad_repaso,
    materias_prioritarias = EXCLUDED.materias_prioritarias,
    razon_priorizacion = EXCLUDED.razon_priorizacion,
    mensaje_motivacional = EXCLUDED.mensaje_motivacional,
    actualizado_at = NOW();

  v_plan := jsonb_build_object(
    'fecha_generacion', CURRENT_DATE,
    'fecha_objetivo', CURRENT_DATE,
    'dias_restantes', v_dias_restantes,
    'preguntas_faltantes', v_preguntas_faltantes,
    'preguntas_nuevas', v_preguntas_nuevas,
    'cantidad_nuevas', COALESCE(array_length(v_preguntas_nuevas, 1), 0),
    'preguntas_repaso', v_preguntas_repaso,
    'cantidad_repaso', COALESCE(array_length(v_preguntas_repaso, 1), 0),
    'pregunta_ids_prioritarias', v_preguntas_prioritarias,
    'materias_prioritarias', v_materias_debiles,
    'total_preguntas_dia',
      COALESCE(array_length(v_preguntas_nuevas, 1), 0) +
      COALESCE(array_length(v_preguntas_repaso, 1), 0),
    'mensaje_ia', v_mensaje
  );

  RETURN v_plan;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_generar_plan_adaptativo(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_generar_plan_adaptativo(uuid, date) TO service_role;

-- ------------------------------------------------------------
-- 2) Estadisticas por sesion para Tutor IA
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_actualizar_estadistica_usuario_sesion()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_aplicar boolean := false;
  v_duracion_min integer := 0;
  v_momento timestamp;
  v_hora text;
  v_dia text;
BEGIN
  IF NEW.usuario_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_aplicar := COALESCE(NEW.completada, false);
  ELSIF TG_OP = 'UPDATE' THEN
    v_aplicar :=
      COALESCE(NEW.completada, false)
      AND COALESCE(OLD.completada, false) IS DISTINCT FROM true;
  END IF;

  IF NOT v_aplicar THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.duracion_real_segundos, 0) > 0 THEN
    v_duracion_min := CEIL(NEW.duracion_real_segundos::numeric / 60.0)::int;
  ELSIF NEW.fecha_inicio IS NOT NULL AND NEW.fecha_fin IS NOT NULL THEN
    v_duracion_min := CEIL(EXTRACT(EPOCH FROM (NEW.fecha_fin - NEW.fecha_inicio)) / 60.0)::int;
  ELSE
    v_duracion_min := 0;
  END IF;
  v_duracion_min := GREATEST(v_duracion_min, 0);

  v_momento := COALESCE(NEW.fecha_fin, NEW.fecha_inicio, NOW());
  v_hora := to_char(v_momento, 'HH24');
  v_dia := to_char(v_momento, 'ID');

  INSERT INTO public.estadistica_usuario (
    usuario_id,
    total_sesiones,
    total_sesiones_completadas,
    tiempo_total_estudio_minutos,
    hora_pico_rendimiento,
    dia_semana_mas_activo,
    actualizado_at
  )
  VALUES (
    NEW.usuario_id,
    1,
    1,
    v_duracion_min,
    v_hora,
    v_dia,
    NOW()
  )
  ON CONFLICT (usuario_id) DO UPDATE SET
    total_sesiones = COALESCE(public.estadistica_usuario.total_sesiones, 0) + 1,
    total_sesiones_completadas =
      COALESCE(public.estadistica_usuario.total_sesiones_completadas, 0) + 1,
    tiempo_total_estudio_minutos =
      COALESCE(public.estadistica_usuario.tiempo_total_estudio_minutos, 0) + v_duracion_min,
    hora_pico_rendimiento = v_hora,
    dia_semana_mas_activo = v_dia,
    actualizado_at = NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_actualizar_estadistica_usuario_sesion ON public.sesion_practica;
CREATE TRIGGER trigger_actualizar_estadistica_usuario_sesion
AFTER INSERT OR UPDATE OF completada, duracion_real_segundos, fecha_inicio, fecha_fin
ON public.sesion_practica
FOR EACH ROW
EXECUTE FUNCTION public.trg_actualizar_estadistica_usuario_sesion();

COMMIT;

