-- ============================================
-- 24_USUARIO_APELLIDOS_SEPARADOS.sql
-- Objetivo:
-- 1) Agregar columnas separadas de identidad en public.usuario
-- 2) Backfill desde nombre_completo existente
-- 3) Mantener sincronia con trigger BEFORE INSERT/UPDATE
-- ============================================

BEGIN;
SET search_path TO public;

ALTER TABLE public.usuario
  ADD COLUMN IF NOT EXISTS nombres text,
  ADD COLUMN IF NOT EXISTS apellido_paterno text,
  ADD COLUMN IF NOT EXISTS apellido_materno text;

WITH partes AS (
  SELECT
    u.id,
    regexp_split_to_array(
      trim(regexp_replace(COALESCE(u.nombre_completo, ''), '\s+', ' ', 'g')),
      ' '
    ) AS arr
  FROM public.usuario u
),
normalizado AS (
  SELECT
    p.id,
    CASE
      WHEN cardinality(p.arr) >= 3
        THEN array_to_string(p.arr[1:cardinality(p.arr)-2], ' ')
      WHEN cardinality(p.arr) = 2
        THEN p.arr[1]
      WHEN cardinality(p.arr) = 1
        THEN p.arr[1]
      ELSE ''
    END AS nombres,
    CASE
      WHEN cardinality(p.arr) >= 2 THEN p.arr[cardinality(p.arr)-1]
      ELSE ''
    END AS apellido_paterno,
    CASE
      WHEN cardinality(p.arr) >= 3 THEN p.arr[cardinality(p.arr)]
      ELSE ''
    END AS apellido_materno
  FROM partes p
)
UPDATE public.usuario u
SET
  nombres = COALESCE(NULLIF(trim(n.nombres), ''), u.nombres),
  apellido_paterno = COALESCE(NULLIF(trim(n.apellido_paterno), ''), u.apellido_paterno),
  apellido_materno = COALESCE(NULLIF(trim(n.apellido_materno), ''), u.apellido_materno),
  nombre_completo = NULLIF(
    trim(
      concat_ws(
        ' ',
        COALESCE(NULLIF(trim(COALESCE(u.nombres, n.nombres)), ''), ''),
        COALESCE(NULLIF(trim(COALESCE(u.apellido_paterno, n.apellido_paterno)), ''), ''),
        COALESCE(NULLIF(trim(COALESCE(u.apellido_materno, n.apellido_materno)), ''), '')
      )
    ),
    ''
  )
FROM normalizado n
WHERE n.id = u.id;

CREATE OR REPLACE FUNCTION public.trg_usuario_normalizar_nombre()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_nombre text;
  v_arr text[];
BEGIN
  NEW.nombres := NULLIF(trim(COALESCE(NEW.nombres, '')), '');
  NEW.apellido_paterno := NULLIF(trim(COALESCE(NEW.apellido_paterno, '')), '');
  NEW.apellido_materno := NULLIF(trim(COALESCE(NEW.apellido_materno, '')), '');
  v_nombre := trim(COALESCE(NEW.nombre_completo, ''));

  IF (NEW.nombres IS NULL OR NEW.apellido_paterno IS NULL OR NEW.apellido_materno IS NULL)
     AND v_nombre <> '' THEN
    v_arr := regexp_split_to_array(regexp_replace(v_nombre, '\s+', ' ', 'g'), ' ');

    IF NEW.nombres IS NULL THEN
      IF cardinality(v_arr) >= 3 THEN
        NEW.nombres := array_to_string(v_arr[1:cardinality(v_arr)-2], ' ');
      ELSIF cardinality(v_arr) >= 1 THEN
        NEW.nombres := v_arr[1];
      END IF;
    END IF;

    IF NEW.apellido_paterno IS NULL AND cardinality(v_arr) >= 2 THEN
      NEW.apellido_paterno := v_arr[cardinality(v_arr)-1];
    END IF;

    IF NEW.apellido_materno IS NULL AND cardinality(v_arr) >= 3 THEN
      NEW.apellido_materno := v_arr[cardinality(v_arr)];
    END IF;
  END IF;

  NEW.nombre_completo := NULLIF(
    trim(
      concat_ws(
        ' ',
        COALESCE(NEW.nombres, ''),
        COALESCE(NEW.apellido_paterno, ''),
        COALESCE(NEW.apellido_materno, '')
      )
    ),
    ''
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_usuario_normalizar_nombre ON public.usuario;
CREATE TRIGGER trigger_usuario_normalizar_nombre
BEFORE INSERT OR UPDATE OF nombre_completo, nombres, apellido_paterno, apellido_materno
ON public.usuario
FOR EACH ROW
EXECUTE FUNCTION public.trg_usuario_normalizar_nombre();

COMMIT;
