-- ============================================
-- 08_OFICIALES_DESDE_SUBOFICIALES.sql
-- Duplica el banco SUB -> OFI usando las mismas preguntas
-- Ejecutar despues de 07_SUBOFICIALES_DESDE_PDF.sql
-- ============================================

BEGIN;
SET search_path TO public;

-- 1) Crear banco oficiales
INSERT INTO banco_de_pregunta (nombre, version, descripcion, total_preguntas, fecha_publicacion, activo, es_oficial)
SELECT 'Banco Oficiales 2025 Promo 2026 (Clon PDF)', 'v1.0-pdf', 'Clon del banco suboficiales para pruebas de oficiales', 3000, CURRENT_DATE, TRUE, TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM banco_de_pregunta WHERE nombre = 'Banco Oficiales 2025 Promo 2026 (Clon PDF)' AND version = 'v1.0-pdf'
);

-- 2) Copiar preguntas SUB -> OFI
WITH b_sub AS (
  SELECT id FROM banco_de_pregunta WHERE nombre = 'Banco Suboficiales 2025 Promo 2026 (PDF)' AND version = 'v1.0-pdf' LIMIT 1
), b_ofi AS (
  SELECT id FROM banco_de_pregunta WHERE nombre = 'Banco Oficiales 2025 Promo 2026 (Clon PDF)' AND version = 'v1.0-pdf' LIMIT 1
)
INSERT INTO pregunta (
  banco_id, materia_id, codigo_pregunta, numero_oficial, enunciado, contexto, ubicacion_fuente, codigo_fuente, tipo_pregunta, dificultad_estimada, frecuencia_examen, tema_especifico, subtema, score_importancia, activo, revisada, creado_at, actualizado_at
)
SELECT bo.id, p.materia_id, REPLACE(p.codigo_pregunta, 'SUB-', 'OFI-'), p.numero_oficial, p.enunciado, p.contexto, p.ubicacion_fuente, p.codigo_fuente, p.tipo_pregunta, p.dificultad_estimada, p.frecuencia_examen, p.tema_especifico, p.subtema, p.score_importancia, p.activo, p.revisada, NOW(), NOW()
FROM pregunta p
JOIN b_sub bs ON p.banco_id = bs.id
JOIN b_ofi bo ON TRUE
WHERE p.codigo_pregunta LIKE 'SUB-%'
  AND NOT EXISTS (SELECT 1 FROM pregunta x WHERE x.codigo_pregunta = REPLACE(p.codigo_pregunta, 'SUB-', 'OFI-'));

-- 3) Copiar alternativas
WITH b_sub AS (
  SELECT id FROM banco_de_pregunta WHERE nombre = 'Banco Suboficiales 2025 Promo 2026 (PDF)' AND version = 'v1.0-pdf' LIMIT 1
)
INSERT INTO alternativa (pregunta_id, letra, texto, es_correcta, orden)
SELECT p_new.id, a.letra, a.texto, a.es_correcta, a.orden
FROM pregunta p_old
JOIN b_sub bs ON p_old.banco_id = bs.id
JOIN alternativa a ON a.pregunta_id = p_old.id
JOIN pregunta p_new ON p_new.codigo_pregunta = REPLACE(p_old.codigo_pregunta, 'SUB-', 'OFI-')
WHERE p_old.codigo_pregunta LIKE 'SUB-%'
ON CONFLICT (pregunta_id, letra) DO UPDATE SET
  texto = EXCLUDED.texto,
  es_correcta = EXCLUDED.es_correcta,
  orden = EXCLUDED.orden;

-- 4) Sincronizar total
UPDATE banco_de_pregunta b
SET total_preguntas = t.cantidad
FROM (SELECT banco_id, COUNT(*)::int AS cantidad FROM pregunta GROUP BY banco_id) t
WHERE b.id = t.banco_id
  AND b.nombre IN ('Banco Suboficiales 2025 Promo 2026 (PDF)', 'Banco Oficiales 2025 Promo 2026 (Clon PDF)')
  AND b.version = 'v1.0-pdf';

COMMIT;

-- Verificacion
SELECT b.nombre, b.version, COUNT(p.id) AS total_preguntas FROM banco_de_pregunta b LEFT JOIN pregunta p ON p.banco_id = b.id WHERE b.version = 'v1.0-pdf' AND b.nombre IN ('Banco Suboficiales 2025 Promo 2026 (PDF)', 'Banco Oficiales 2025 Promo 2026 (Clon PDF)') GROUP BY b.nombre, b.version ORDER BY b.nombre;
