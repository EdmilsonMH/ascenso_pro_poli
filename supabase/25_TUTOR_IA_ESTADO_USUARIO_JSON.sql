-- ============================================
-- 25_TUTOR_IA_ESTADO_USUARIO_JSON.sql
-- Objetivo:
-- Guardar estado JSON del Tutor IA por usuario
-- (plan diario, progreso, diagnostico, ranking, etc.)
-- para personalizar respuestas con contexto persistente.
-- ============================================

BEGIN;
SET search_path TO public;

CREATE TABLE IF NOT EXISTS public.ia_tutor_estado_usuario (
  usuario_id uuid PRIMARY KEY REFERENCES public.usuario(id) ON DELETE CASCADE,
  estado jsonb NOT NULL DEFAULT '{}'::jsonb,
  fuente text NOT NULL DEFAULT 'app',
  version integer NOT NULL DEFAULT 1,
  creado_at timestamptz NOT NULL DEFAULT now(),
  actualizado_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ia_tutor_estado_usuario_actualizado_idx
  ON public.ia_tutor_estado_usuario (actualizado_at DESC);

ALTER TABLE public.ia_tutor_estado_usuario ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.ia_tutor_estado_usuario FROM public;
REVOKE ALL ON TABLE public.ia_tutor_estado_usuario FROM anon;

GRANT SELECT, INSERT, UPDATE
  ON TABLE public.ia_tutor_estado_usuario
  TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.ia_tutor_estado_usuario
  TO service_role;

DROP POLICY IF EXISTS "Usuarios pueden ver su estado tutor IA" ON public.ia_tutor_estado_usuario;
DROP POLICY IF EXISTS "Usuarios pueden crear su estado tutor IA" ON public.ia_tutor_estado_usuario;
DROP POLICY IF EXISTS "Usuarios pueden actualizar su estado tutor IA" ON public.ia_tutor_estado_usuario;

CREATE POLICY "Usuarios pueden ver su estado tutor IA"
ON public.ia_tutor_estado_usuario
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Usuarios pueden crear su estado tutor IA"
ON public.ia_tutor_estado_usuario
FOR INSERT
WITH CHECK (auth.uid()::text = usuario_id::text);

CREATE POLICY "Usuarios pueden actualizar su estado tutor IA"
ON public.ia_tutor_estado_usuario
FOR UPDATE
USING (auth.uid()::text = usuario_id::text)
WITH CHECK (auth.uid()::text = usuario_id::text);

CREATE OR REPLACE FUNCTION public.fn_upsert_ia_tutor_estado_usuario(
  p_estado_parcial jsonb,
  p_fuente text DEFAULT 'app',
  p_version integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_usuario_id uuid;
  v_fuente text;
  v_version integer;
  v_row public.ia_tutor_estado_usuario%ROWTYPE;
BEGIN
  v_usuario_id := auth.uid();
  IF v_usuario_id IS NULL THEN
    RAISE EXCEPTION 'Sesion requerida para actualizar estado de tutor IA';
  END IF;

  v_fuente := COALESCE(NULLIF(trim(p_fuente), ''), 'app');
  v_version := GREATEST(COALESCE(p_version, 1), 1);

  INSERT INTO public.ia_tutor_estado_usuario (
    usuario_id,
    estado,
    fuente,
    version,
    actualizado_at
  )
  VALUES (
    v_usuario_id,
    COALESCE(p_estado_parcial, '{}'::jsonb),
    v_fuente,
    v_version,
    now()
  )
  ON CONFLICT (usuario_id) DO UPDATE SET
    estado = COALESCE(public.ia_tutor_estado_usuario.estado, '{}'::jsonb)
      || COALESCE(EXCLUDED.estado, '{}'::jsonb),
    fuente = EXCLUDED.fuente,
    version = GREATEST(public.ia_tutor_estado_usuario.version, EXCLUDED.version),
    actualizado_at = now();

  SELECT *
  INTO v_row
  FROM public.ia_tutor_estado_usuario
  WHERE usuario_id = v_usuario_id;

  RETURN jsonb_build_object(
    'usuario_id', v_row.usuario_id,
    'estado', v_row.estado,
    'fuente', v_row.fuente,
    'version', v_row.version,
    'actualizado_at', v_row.actualizado_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_get_ia_tutor_estado_usuario()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_usuario_id uuid;
  v_row public.ia_tutor_estado_usuario%ROWTYPE;
BEGIN
  v_usuario_id := auth.uid();
  IF v_usuario_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT *
  INTO v_row
  FROM public.ia_tutor_estado_usuario
  WHERE usuario_id = v_usuario_id;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'usuario_id', v_row.usuario_id,
    'estado', v_row.estado,
    'fuente', v_row.fuente,
    'version', v_row.version,
    'actualizado_at', v_row.actualizado_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_upsert_ia_tutor_estado_usuario(jsonb, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_upsert_ia_tutor_estado_usuario(jsonb, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_get_ia_tutor_estado_usuario() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_get_ia_tutor_estado_usuario() TO service_role;

COMMIT;
