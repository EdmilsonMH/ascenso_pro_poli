-- ============================================
-- 20_RESET_TOTAL_DATOS.sql
-- Deja la base de datos en cero (solo datos, no estructura)
-- ============================================
--
-- Que hace:
-- 1) Vacia TODAS las tablas del schema public
-- 2) Mantiene tablas, funciones, triggers, vistas y politicas
-- 3) Reinicia identidades (si existieran)
--
-- Si tambien quieres borrar usuarios de Auth (login),
-- descomenta el bloque opcional al final.

BEGIN;
SET search_path TO public;

DO $$
DECLARE
  v_sql text;
  v_total_tablas int;
BEGIN
  SELECT COUNT(*)
  INTO v_total_tablas
  FROM pg_tables
  WHERE schemaname = 'public'
    AND tablename <> 'spatial_ref_sys';

  IF v_total_tablas = 0 THEN
    RAISE NOTICE 'No hay tablas en schema public para truncar.';
    RETURN;
  END IF;

  SELECT
    'TRUNCATE TABLE ' ||
    string_agg(format('%I.%I', schemaname, tablename), ', ') ||
    ' RESTART IDENTITY CASCADE;'
  INTO v_sql
  FROM pg_tables
  WHERE schemaname = 'public'
    AND tablename <> 'spatial_ref_sys';

  EXECUTE v_sql;
  RAISE NOTICE 'Tablas truncadas en public: %', v_total_tablas;
END $$;

COMMIT;

-- ============================================
-- OPCIONAL: reset total de autenticacion
-- (solo si quieres borrar tambien TODOS los logins)
-- ============================================
-- BEGIN;
-- DELETE FROM auth.users;
-- COMMIT;

-- Verificacion rapida
DO $$
DECLARE
  r record;
  v_count bigint;
BEGIN
  FOR r IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename <> 'spatial_ref_sys'
    ORDER BY tablename
  LOOP
    EXECUTE format('SELECT COUNT(*) FROM public.%I', r.tablename) INTO v_count;
    RAISE NOTICE 'Tabla % => % filas', r.tablename, v_count;
  END LOOP;
END $$;
