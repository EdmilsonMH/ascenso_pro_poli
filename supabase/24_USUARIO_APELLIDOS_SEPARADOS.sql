-- ============================================
-- 24_USUARIO_APELLIDOS_SEPARADOS.sql
-- Objetivo:
-- 1) Agregar columnas separadas de identidad y telefono en public.usuario
-- 2) Backfill desde nombre_completo existente (orden: AP + AM + NOMBRES)
-- 3) Mantener sincronia con trigger BEFORE INSERT/UPDATE
-- 4) Validar telefono solo celular Peru (+519XXXXXXXX)
-- ============================================

BEGIN;
SET search_path TO public;

ALTER TABLE public.usuario
  ADD COLUMN IF NOT EXISTS nombres text,
  ADD COLUMN IF NOT EXISTS apellido_paterno text,
  ADD COLUMN IF NOT EXISTS apellido_materno text,
  ADD COLUMN IF NOT EXISTS telefono text;

-- Normaliza telefonos existentes a +519XXXXXXXX cuando sea posible.
UPDATE public.usuario u
SET telefono = CASE
  WHEN u.telefono IS NULL OR trim(u.telefono) = '' THEN NULL
  WHEN regexp_replace(u.telefono, '[^0-9]', '', 'g') ~ '^9[0-9]{8}$'
    THEN '+51' || regexp_replace(u.telefono, '[^0-9]', '', 'g')
  WHEN regexp_replace(u.telefono, '[^0-9]', '', 'g') ~ '^519[0-9]{8}$'
    THEN '+' || regexp_replace(u.telefono, '[^0-9]', '', 'g')
  ELSE NULL
END;

-- Backfill de nombres separados asumiendo orden AP + AM + NOMBRES.
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
        THEN array_to_string(p.arr[3:cardinality(p.arr)], ' ')
      WHEN cardinality(p.arr) = 2
        THEN p.arr[2]
      WHEN cardinality(p.arr) = 1
        THEN p.arr[1]
      ELSE ''
    END AS nombres,
    CASE
      WHEN cardinality(p.arr) >= 1 THEN p.arr[1]
      ELSE ''
    END AS apellido_paterno,
    CASE
      WHEN cardinality(p.arr) >= 2 THEN p.arr[2]
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
        COALESCE(NULLIF(trim(COALESCE(u.apellido_paterno, n.apellido_paterno)), ''), ''),
        COALESCE(NULLIF(trim(COALESCE(u.apellido_materno, n.apellido_materno)), ''), ''),
        COALESCE(NULLIF(trim(COALESCE(u.nombres, n.nombres)), ''), '')
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
  v_digitos text;
BEGIN
  NEW.nombres := NULLIF(trim(COALESCE(NEW.nombres, '')), '');
  NEW.apellido_paterno := NULLIF(trim(COALESCE(NEW.apellido_paterno, '')), '');
  NEW.apellido_materno := NULLIF(trim(COALESCE(NEW.apellido_materno, '')), '');
  v_nombre := trim(COALESCE(NEW.nombre_completo, ''));

  -- Normaliza telefono a +519XXXXXXXX
  IF NEW.telefono IS NOT NULL THEN
    v_digitos := regexp_replace(NEW.telefono, '[^0-9]', '', 'g');
    IF v_digitos = '' THEN
      NEW.telefono := NULL;
    ELSIF v_digitos ~ '^9[0-9]{8}$' THEN
      NEW.telefono := '+51' || v_digitos;
    ELSIF v_digitos ~ '^519[0-9]{8}$' THEN
      NEW.telefono := '+' || v_digitos;
    ELSE
      RAISE EXCEPTION 'Telefono invalido. Use celular Peru: 9XXXXXXXX o +519XXXXXXXX';
    END IF;
  END IF;

  IF (NEW.nombres IS NULL OR NEW.apellido_paterno IS NULL OR NEW.apellido_materno IS NULL)
     AND v_nombre <> '' THEN
    v_arr := regexp_split_to_array(regexp_replace(v_nombre, '\s+', ' ', 'g'), ' ');

    IF NEW.apellido_paterno IS NULL AND cardinality(v_arr) >= 1 THEN
      NEW.apellido_paterno := v_arr[1];
    END IF;

    IF NEW.apellido_materno IS NULL AND cardinality(v_arr) >= 2 THEN
      NEW.apellido_materno := v_arr[2];
    END IF;

    IF NEW.nombres IS NULL THEN
      IF cardinality(v_arr) >= 3 THEN
        NEW.nombres := array_to_string(v_arr[3:cardinality(v_arr)], ' ');
      ELSIF cardinality(v_arr) = 2 THEN
        NEW.nombres := v_arr[2];
      ELSIF cardinality(v_arr) = 1 THEN
        NEW.nombres := v_arr[1];
      END IF;
    END IF;
  END IF;

  NEW.nombre_completo := NULLIF(
    trim(
      concat_ws(
        ' ',
        COALESCE(NEW.apellido_paterno, ''),
        COALESCE(NEW.apellido_materno, ''),
        COALESCE(NEW.nombres, '')
      )
    ),
    ''
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_usuario_normalizar_nombre ON public.usuario;
CREATE TRIGGER trigger_usuario_normalizar_nombre
BEFORE INSERT OR UPDATE OF nombre_completo, nombres, apellido_paterno, apellido_materno, telefono
ON public.usuario
FOR EACH ROW
EXECUTE FUNCTION public.trg_usuario_normalizar_nombre();

-- Constraint final de telefono peruano.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'usuario_telefono_peru_chk'
      AND conrelid = 'public.usuario'::regclass
  ) THEN
    ALTER TABLE public.usuario
      ADD CONSTRAINT usuario_telefono_peru_chk
      CHECK (telefono IS NULL OR telefono ~ '^\+519[0-9]{8}$');
  END IF;
END;
$$;

COMMIT;
