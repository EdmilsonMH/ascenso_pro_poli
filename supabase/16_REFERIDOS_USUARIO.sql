-- ============================================
-- 16_REFERIDOS_USUARIO.sql
-- Sistema de referidos por usuario (opcional)
-- Reglas:
-- - Un usuario solo puede ser referido una vez.
-- - Solo puede tener un único referidor.
-- - El referidor recibe +5 créditos cuando el referido activa/paga (premium=true).
-- ============================================

BEGIN;
SET search_path TO public;

-- Asegurar función gen_random_uuid() para generar códigos
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Validaciones de compatibilidad con esquema base existente
DO $$
BEGIN
  IF to_regclass('public.usuario') IS NULL THEN
    RAISE EXCEPTION
      'No existe public.usuario. Ejecuta primero tu schema base (database_setup.sql).';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'usuario'
      AND column_name = 'premium'
  ) THEN
    RAISE EXCEPTION
      'Falta columna public.usuario.premium. El trigger automático depende de ella.';
  END IF;
END;
$$;

-- --------------------------------------------
-- 1) Columnas de referido y créditos
-- --------------------------------------------
ALTER TABLE public.usuario
  ADD COLUMN IF NOT EXISTS codigo_referido text,
  ADD COLUMN IF NOT EXISTS referido_por_usuario_id uuid REFERENCES public.usuario(id),
  ADD COLUMN IF NOT EXISTS referido_aplicado_at timestamp,
  ADD COLUMN IF NOT EXISTS referido_recompensado_at timestamp,
  ADD COLUMN IF NOT EXISTS creditos integer NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'usuario_creditos_no_negativos'
      AND conrelid = 'public.usuario'::regclass
  ) THEN
    ALTER TABLE public.usuario
      ADD CONSTRAINT usuario_creditos_no_negativos CHECK (creditos >= 0);
  END IF;
END;
$$;

-- --------------------------------------------
-- 2) Generación automática de código referido
-- --------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_generar_codigo_referido_unico()
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_codigo text;
BEGIN
  LOOP
    v_codigo := UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.usuario WHERE codigo_referido = v_codigo
    );
  END LOOP;

  RETURN v_codigo;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_usuario_generar_codigo_referido()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.codigo_referido IS NULL OR BTRIM(NEW.codigo_referido) = '' THEN
    NEW.codigo_referido := public.fn_generar_codigo_referido_unico();
  ELSE
    NEW.codigo_referido := UPPER(BTRIM(NEW.codigo_referido));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_usuario_generar_codigo_referido ON public.usuario;
CREATE TRIGGER trigger_usuario_generar_codigo_referido
BEFORE INSERT ON public.usuario
FOR EACH ROW
EXECUTE FUNCTION public.trg_usuario_generar_codigo_referido();

-- Asegurar código a usuarios ya existentes
UPDATE public.usuario
SET codigo_referido = UPPER(BTRIM(codigo_referido))
WHERE codigo_referido IS NOT NULL;

UPDATE public.usuario
SET codigo_referido = public.fn_generar_codigo_referido_unico()
WHERE codigo_referido IS NULL OR BTRIM(codigo_referido) = '';

-- Resolver posibles códigos duplicados previos (si existieran)
WITH codigos_duplicados AS (
  SELECT
    id,
    ROW_NUMBER() OVER (PARTITION BY codigo_referido ORDER BY id) AS rn
  FROM public.usuario
  WHERE codigo_referido IS NOT NULL
)
UPDATE public.usuario u
SET codigo_referido = public.fn_generar_codigo_referido_unico()
FROM codigos_duplicados d
WHERE u.id = d.id
  AND d.rn > 1;

-- Índice único para códigos
CREATE UNIQUE INDEX IF NOT EXISTS idx_usuario_codigo_referido_unique
ON public.usuario (codigo_referido)
WHERE codigo_referido IS NOT NULL;

-- --------------------------------------------
-- 3) RPC: aplicar código referido (una sola vez)
-- --------------------------------------------
CREATE OR REPLACE FUNCTION public.aplicar_codigo_referido(p_codigo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usuario_actual_id uuid := auth.uid();
  v_codigo text := UPPER(BTRIM(COALESCE(p_codigo, '')));
  v_referidor_id uuid;
  v_referido_actual uuid;
BEGIN
  IF v_usuario_actual_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No autenticado.'
    );
  END IF;

  IF v_codigo = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Código referido vacío.'
    );
  END IF;

  SELECT referido_por_usuario_id
  INTO v_referido_actual
  FROM public.usuario
  WHERE id = v_usuario_actual_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Usuario actual no encontrado.'
    );
  END IF;

  IF v_referido_actual IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Ya tienes un referido aplicado.'
    );
  END IF;

  SELECT id
  INTO v_referidor_id
  FROM public.usuario
  WHERE codigo_referido = v_codigo
  LIMIT 1;

  IF v_referidor_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Código referido no válido.'
    );
  END IF;

  IF v_referidor_id = v_usuario_actual_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No puedes referirte a ti mismo.'
    );
  END IF;

  UPDATE public.usuario
  SET
    referido_por_usuario_id = v_referidor_id,
    referido_aplicado_at = NOW()
  WHERE id = v_usuario_actual_id
    AND referido_por_usuario_id IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No se pudo aplicar el referido.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'referidor_id', v_referidor_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.aplicar_codigo_referido(text) TO authenticated;

-- --------------------------------------------
-- 4) Premio +5 al referidor cuando el referido se activa/paga
-- --------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_otorgar_credito_referido_al_activar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Solo al pasar de no premium -> premium
  IF COALESCE(OLD.premium, false) = true OR COALESCE(NEW.premium, false) <> true THEN
    RETURN NEW;
  END IF;

  -- Debe tener referidor y no haber sido recompensado antes
  IF NEW.referido_por_usuario_id IS NULL OR NEW.referido_recompensado_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Sumar +5 al referidor
  UPDATE public.usuario
  SET creditos = COALESCE(creditos, 0) + 5
  WHERE id = NEW.referido_por_usuario_id;

  -- Marcar que ya se pagó la recompensa para este referido
  UPDATE public.usuario
  SET referido_recompensado_at = NOW()
  WHERE id = NEW.id
    AND referido_recompensado_at IS NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_otorgar_credito_referido_al_activar ON public.usuario;
CREATE TRIGGER trigger_otorgar_credito_referido_al_activar
AFTER UPDATE OF premium ON public.usuario
FOR EACH ROW
EXECUTE FUNCTION public.trg_otorgar_credito_referido_al_activar();

COMMIT;
