-- ============================================
-- 18_SYNC_BORRADO_AUTH_USUARIO.sql
-- Version segura (sin borrado masivo inmediato):
-- Si se elimina un usuario en auth.users, elimina tambien
-- su fila en public.usuario (y por cascada el resto de datos).
-- ============================================

BEGIN;
SET search_path TO public, auth;

CREATE OR REPLACE FUNCTION public.fn_cleanup_public_usuario_on_auth_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Compatibilidad: algunos registros pueden relacionarse por id
  -- y otros por user_id (texto con el UUID de auth.users.id).
  DELETE FROM public.usuario
  WHERE id = OLD.id
     OR user_id = OLD.id::text;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_cleanup_public_usuario_on_auth_delete ON auth.users;

CREATE TRIGGER trg_cleanup_public_usuario_on_auth_delete
AFTER DELETE ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.fn_cleanup_public_usuario_on_auth_delete();

-- Borrado puntual solicitado (correo especifico).
-- Se elimina en auth.users y luego se limpia cualquier remanente en public.usuario.
DELETE FROM auth.users
WHERE lower(email) = lower('cardenas3kmc@gmail.com');

DELETE FROM public.usuario
WHERE lower(email) = lower('cardenas3kmc@gmail.com');

COMMIT;

-- ==========================================================
-- OPCIONAL (manual): revisar primero posibles huerfanos
-- ==========================================================
-- SELECT u.id, u.user_id, u.nombre_completo
-- FROM public.usuario u
-- WHERE NOT EXISTS (
--   SELECT 1
--   FROM auth.users au
--   WHERE au.id = u.id
--      OR au.id::text = u.user_id
-- );

-- ==========================================================
-- OPCIONAL (manual): limpiar huerfanos SOLO si validaste antes
-- ==========================================================
-- DELETE FROM public.usuario u
-- WHERE NOT EXISTS (
--   SELECT 1
--   FROM auth.users au
--   WHERE au.id = u.id
--      OR au.id::text = u.user_id
-- );
