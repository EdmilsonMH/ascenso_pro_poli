-- ============================================
-- BANCO OFICIALES INVENTADO (150 PREGUNTAS)
-- 5 materias x 30 preguntas
-- Requiere 00_SETUP_COMPLETO.sql ejecutado
-- ============================================

BEGIN;

SET search_path TO public;

-- --------------------------------------------
-- 1) Materias base (5)
-- --------------------------------------------
INSERT INTO materia (
  codigo,
  nombre,
  nombre_corto,
  descripcion,
  total_preguntas_banco,
  color_hex,
  icono,
  orden_visualizacion,
  categoria,
  nivel_dificultad_promedio,
  activo
)
VALUES
  ('DHUM', 'Derechos Humanos', 'DDHH', 'Derechos fundamentales en funcion policial.', 30, '#2563EB', 'shield', 1, 'Juridica', 'media', TRUE),
  ('DCON', 'Constitucion Politica', 'Constitucion', 'Marco constitucional aplicado al servicio policial.', 30, '#0EA5E9', 'account_balance', 2, 'Juridica', 'media', TRUE),
  ('DPEN', 'Derecho Penal', 'Penal', 'Tipos penales y criterios de actuacion.', 30, '#F97316', 'gavel', 3, 'Juridica', 'alta', TRUE),
  ('DPRO', 'Derecho Procesal Penal', 'Procesal', 'Procedimiento y garantias procesales.', 30, '#8B5CF6', 'description', 4, 'Procedimental', 'alta', TRUE),
  ('FPEP', 'Funcion Policial y Etica', 'Etica PNP', 'Uso de la fuerza, disciplina y deontologia.', 30, '#10B981', 'local_police', 5, 'Operativa', 'media', TRUE)
ON CONFLICT (codigo) DO UPDATE
SET
  nombre = EXCLUDED.nombre,
  nombre_corto = EXCLUDED.nombre_corto,
  descripcion = EXCLUDED.descripcion,
  categoria = EXCLUDED.categoria,
  nivel_dificultad_promedio = EXCLUDED.nivel_dificultad_promedio,
  activo = TRUE,
  actualizado_at = NOW();

-- --------------------------------------------
-- 2) Banco Oficiales
-- --------------------------------------------
INSERT INTO banco_de_pregunta (
  nombre,
  version,
  descripcion,
  total_preguntas,
  fecha_publicacion,
  activo,
  es_oficial
)
SELECT
  'Banco Oficiales - Inventado',
  'v1.0',
  'Banco inventado para pruebas funcionales del flujo de Oficiales',
  150,
  CURRENT_DATE,
  TRUE,
  TRUE
WHERE NOT EXISTS (
  SELECT 1
  FROM banco_de_pregunta
  WHERE nombre = 'Banco Oficiales - Inventado'
    AND version = 'v1.0'
);

-- --------------------------------------------
-- 3) Crear 150 preguntas (5 x 30)
-- --------------------------------------------
WITH banco AS (
  SELECT id
  FROM banco_de_pregunta
  WHERE nombre = 'Banco Oficiales - Inventado'
    AND version = 'v1.0'
  LIMIT 1
),
materias AS (
  SELECT id, codigo, nombre
  FROM materia
  WHERE codigo IN ('DHUM', 'DCON', 'DPEN', 'DPRO', 'FPEP')
),
nums AS (
  SELECT generate_series(1, 30) AS n
),
lote AS (
  SELECT
    b.id AS banco_id,
    m.id AS materia_id,
    m.codigo AS materia_codigo,
    m.nombre AS materia_nombre,
    n.n
  FROM banco b
  CROSS JOIN materias m
  CROSS JOIN nums n
)
INSERT INTO pregunta (
  banco_id,
  materia_id,
  codigo_pregunta,
  numero_oficial,
  enunciado,
  tipo_pregunta,
  dificultad_estimada,
  frecuencia_examen,
  tema_especifico,
  subtema,
  score_importancia,
  activo,
  revisada,
  creado_at,
  actualizado_at
)
SELECT
  l.banco_id,
  l.materia_id,
  format('OFI-%s-%03s', l.materia_codigo, l.n),
  l.n,
  format(
    '[OFICIAL] %s - Pregunta %s: segun el marco normativo, cual es la actuacion correcta en este supuesto?',
    l.materia_nombre,
    l.n
  ),
  'multiple_choice',
  CASE
    WHEN l.n <= 10 THEN 'facil'
    WHEN l.n <= 20 THEN 'medio'
    ELSE 'dificil'
  END,
  CASE
    WHEN l.n <= 10 THEN 'alta'
    WHEN l.n <= 20 THEN 'media'
    ELSE 'baja'
  END,
  CASE l.materia_codigo
    WHEN 'DHUM' THEN CASE
      WHEN l.n % 3 = 0 THEN 'Uso proporcional de la fuerza'
      WHEN l.n % 3 = 1 THEN 'Garantias en intervencion'
      ELSE 'Debido trato al ciudadano'
    END
    WHEN 'DCON' THEN CASE
      WHEN l.n % 3 = 0 THEN 'Derechos fundamentales'
      WHEN l.n % 3 = 1 THEN 'Principio de legalidad'
      ELSE 'Control constitucional'
    END
    WHEN 'DPEN' THEN CASE
      WHEN l.n % 3 = 0 THEN 'Tipicidad y antijuridicidad'
      WHEN l.n % 3 = 1 THEN 'Imputacion y culpabilidad'
      ELSE 'Formas de participacion'
    END
    WHEN 'DPRO' THEN CASE
      WHEN l.n % 3 = 0 THEN 'Cadena de custodia'
      WHEN l.n % 3 = 1 THEN 'Actos urgentes de investigacion'
      ELSE 'Garantias del procedimiento'
    END
    ELSE CASE
      WHEN l.n % 3 = 0 THEN 'Deontologia policial'
      WHEN l.n % 3 = 1 THEN 'Uso progresivo de la fuerza'
      ELSE 'Disciplina y liderazgo'
    END
  END,
  CASE
    WHEN l.n % 2 = 0 THEN 'Aplicacion normativa'
    ELSE 'Criterio operativo'
  END,
  55 + (l.n % 35),
  TRUE,
  TRUE,
  NOW(),
  NOW()
FROM lote l
WHERE NOT EXISTS (
  SELECT 1
  FROM pregunta p
  WHERE p.codigo_pregunta = format('OFI-%s-%03s', l.materia_codigo, l.n)
);

-- --------------------------------------------
-- 4) Alternativas para preguntas OFI-*
-- --------------------------------------------
WITH preguntas_ofi AS (
  SELECT
    p.id,
    split_part(p.codigo_pregunta, '-', 2) AS materia_codigo,
    right(p.codigo_pregunta, 3)::int AS numero
  FROM pregunta p
  WHERE p.codigo_pregunta ~ '^OFI-(DHUM|DCON|DPEN|DPRO|FPEP)-[0-9]{3}$'
),
materias_obj AS (
  SELECT codigo, nombre
  FROM materia
  WHERE codigo IN ('DHUM', 'DCON', 'DPEN', 'DPRO', 'FPEP')
)
INSERT INTO alternativa (
  pregunta_id,
  letra,
  texto,
  es_correcta,
  orden
)
SELECT
  po.id,
  alt.letra,
  CASE alt.letra
    WHEN 'A' THEN format('Actuar sin documentar formalmente en %s.', mo.nombre)
    WHEN 'B' THEN format('Aplicar el procedimiento legal de %s respetando derechos y legalidad.', mo.nombre)
    WHEN 'C' THEN format('Delegar la actuacion sin validar competencia en %s.', mo.nombre)
    ELSE format('Postergar la actuacion de %s sin evaluar urgencia.', mo.nombre)
  END,
  CASE
    WHEN po.numero % 4 = 1 AND alt.letra = 'A' THEN TRUE
    WHEN po.numero % 4 = 2 AND alt.letra = 'B' THEN TRUE
    WHEN po.numero % 4 = 3 AND alt.letra = 'C' THEN TRUE
    WHEN po.numero % 4 = 0 AND alt.letra = 'D' THEN TRUE
    ELSE FALSE
  END,
  alt.orden
FROM preguntas_ofi po
JOIN materias_obj mo
  ON mo.codigo = po.materia_codigo
CROSS JOIN (
  VALUES
    ('A'::char(1), 1),
    ('B'::char(1), 2),
    ('C'::char(1), 3),
    ('D'::char(1), 4)
) AS alt(letra, orden)
ON CONFLICT (pregunta_id, letra) DO UPDATE
SET
  texto = EXCLUDED.texto,
  es_correcta = EXCLUDED.es_correcta,
  orden = EXCLUDED.orden;

-- --------------------------------------------
-- 5) Recalcular totales
-- --------------------------------------------
UPDATE banco_de_pregunta b
SET total_preguntas = t.cantidad
FROM (
  SELECT banco_id, COUNT(*)::int AS cantidad
  FROM pregunta
  GROUP BY banco_id
) t
WHERE b.id = t.banco_id
  AND b.nombre = 'Banco Oficiales - Inventado'
  AND b.version = 'v1.0';

UPDATE materia m
SET total_preguntas_banco = t.cantidad,
    actualizado_at = NOW()
FROM (
  SELECT materia_id, COUNT(*)::int AS cantidad
  FROM pregunta
  GROUP BY materia_id
) t
WHERE m.id = t.materia_id
  AND m.codigo IN ('DHUM', 'DCON', 'DPEN', 'DPRO', 'FPEP');

COMMIT;

-- --------------------------------------------
-- 6) Verificacion
-- --------------------------------------------
SELECT
  b.nombre,
  b.version,
  COUNT(p.id) AS total_preguntas
FROM banco_de_pregunta b
LEFT JOIN pregunta p ON p.banco_id = b.id
WHERE b.nombre = 'Banco Oficiales - Inventado'
  AND b.version = 'v1.0'
GROUP BY b.nombre, b.version;

SELECT
  m.codigo,
  m.nombre,
  COUNT(p.id) AS total_preguntas
FROM materia m
LEFT JOIN pregunta p ON p.materia_id = m.id
WHERE m.codigo IN ('DHUM', 'DCON', 'DPEN', 'DPRO', 'FPEP')
  AND p.codigo_pregunta LIKE 'OFI-%'
GROUP BY m.codigo, m.nombre
ORDER BY m.codigo;

