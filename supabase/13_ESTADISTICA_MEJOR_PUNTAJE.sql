-- ============================================
-- 13_ESTADISTICA_MEJOR_PUNTAJE.sql
-- Persistir mejor puntaje de simulacro por usuario
-- ============================================

BEGIN;
SET search_path TO public;

CREATE OR REPLACE FUNCTION public.trg_actualizar_mejor_puntaje_simulacro()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nuevo_puntaje integer;
BEGIN
  IF NEW.usuario_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Solo considerar sesiones completadas.
  IF COALESCE(NEW.completada, false) <> true THEN
    RETURN NEW;
  END IF;

  -- Priorizamos preguntas_correctas (0-100) para mantener consistencia con ranking.
  v_nuevo_puntaje := COALESCE(
    NULLIF(NEW.preguntas_correctas, 0),
    NULLIF(ROUND(COALESCE(NEW.puntaje_obtenido, 0))::int, 0),
    0
  );

  IF v_nuevo_puntaje <= 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.estadistica_usuario (
    usuario_id,
    mejor_puntaje_simulacro,
    actualizado_at
  )
  VALUES (
    NEW.usuario_id,
    v_nuevo_puntaje,
    NOW()
  )
  ON CONFLICT (usuario_id) DO UPDATE SET
    mejor_puntaje_simulacro = GREATEST(
      COALESCE(public.estadistica_usuario.mejor_puntaje_simulacro, 0),
      EXCLUDED.mejor_puntaje_simulacro
    ),
    actualizado_at = NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_actualizar_mejor_puntaje_simulacro ON public.sesion_practica;
CREATE TRIGGER trigger_actualizar_mejor_puntaje_simulacro
AFTER INSERT OR UPDATE OF completada, preguntas_correctas, puntaje_obtenido
ON public.sesion_practica
FOR EACH ROW
EXECUTE FUNCTION public.trg_actualizar_mejor_puntaje_simulacro();

COMMIT;

