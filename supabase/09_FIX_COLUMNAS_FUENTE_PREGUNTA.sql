-- ============================================
-- 09_FIX_COLUMNAS_FUENTE_PREGUNTA.sql
-- Agrega columnas separadas para UBICACION y CODIGO
-- y rellena datos desde pregunta.contexto (si existen)
-- ============================================

BEGIN;
SET search_path TO public;

ALTER TABLE pregunta ADD COLUMN IF NOT EXISTS ubicacion_fuente TEXT;
ALTER TABLE pregunta ADD COLUMN IF NOT EXISTS codigo_fuente TEXT;

UPDATE pregunta
SET
  ubicacion_fuente = COALESCE(
    ubicacion_fuente,
    NULLIF(TRIM(SUBSTRING(contexto FROM 'UBICACION:\s*([^|]+)')), '')
  ),
  codigo_fuente = COALESCE(
    codigo_fuente,
    NULLIF(TRIM(SUBSTRING(contexto FROM 'CODIGO_FUENTE:\s*([^|]+)')), '')
  )
WHERE contexto IS NOT NULL
  AND (ubicacion_fuente IS NULL OR codigo_fuente IS NULL);

COMMIT;

-- Verificacion
SELECT
  COUNT(*) AS total_preguntas,
  COUNT(ubicacion_fuente) AS con_ubicacion_fuente,
  COUNT(codigo_fuente) AS con_codigo_fuente
FROM pregunta;
