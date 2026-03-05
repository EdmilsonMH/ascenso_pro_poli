-- ============================================
-- 21_FIX_RLS_USUARIO_EMAIL_DUPLICADO.sql
-- Corrige casos de "duplicate key ... usuario_email_key"
-- al completar perfil/registro.
-- ============================================
--
-- Problema típico:
-- - Existe fila previa en public.usuario con el mismo email.
-- - RLS solo validaba auth.uid() = id, y no auth.uid() = user_id.
-- - La app no ve esa fila y vuelve a intentar INSERT, chocando por email único.
--
-- Este script:
-- 1) Ajusta políticas RLS de public.usuario para soportar id o user_id.
-- 2) Re-vincula user_id por email usando auth.users (solo cuando es seguro).

BEGIN;
SET search_path TO public;

-- --------------------------------------------
-- 1) Políticas RLS compatibles con esquemas legacy
-- --------------------------------------------
DROP POLICY IF EXISTS "Usuarios pueden ver su propio perfil" ON public.usuario;
DROP POLICY IF EXISTS "Usuarios pueden actualizar su propio perfil" ON public.usuario;
DROP POLICY IF EXISTS "Permitir registro de nuevos usuarios" ON public.usuario;

CREATE POLICY "Usuarios pueden ver su propio perfil"
ON public.usuario
FOR SELECT
USING (
  auth.uid()::text = id::text
  OR auth.uid()::text = user_id
);

CREATE POLICY "Usuarios pueden actualizar su propio perfil"
ON public.usuario
FOR UPDATE
USING (
  auth.uid()::text = id::text
  OR auth.uid()::text = user_id
)
WITH CHECK (
  auth.uid()::text = id::text
  OR auth.uid()::text = user_id
);

CREATE POLICY "Permitir registro de nuevos usuarios"
ON public.usuario
FOR INSERT
WITH CHECK (
  auth.uid()::text = id::text
  OR auth.uid()::text = user_id
);

-- --------------------------------------------
-- 2) Re-vincular user_id por email (si aplica)
-- --------------------------------------------
DO $$
DECLARE
  v_rows int := 0;
BEGIN
  UPDATE public.usuario u
  SET user_id = au.id::text
  FROM auth.users au
  WHERE u.email IS NOT NULL
    AND btrim(u.email) <> ''
    AND lower(u.email) = lower(au.email)
    AND coalesce(u.user_id, '') <> au.id::text
    AND NOT EXISTS (
      SELECT 1
      FROM public.usuario ux
      WHERE ux.user_id = au.id::text
        AND ux.id <> u.id
    );

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RAISE NOTICE 'Filas relink por email->user_id: %', v_rows;
END $$;

COMMIT;

-- Verificación rápida (opcional):
-- SELECT id, user_id, email
-- FROM public.usuario
-- WHERE lower(email) = lower('TU_CORREO@EJEMPLO.COM');
