-- ============================================
-- BANCOS Y PREGUNTAS DE PRUEBA
-- Proyecto: Ascenso Pro Poli
-- Requiere: esquema creado con 00_SETUP_COMPLETO.sql
-- ============================================

BEGIN;

SET search_path TO public;

-- --------------------------------------------
-- 1) Materias de prueba (5)
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
  ('DHUM', 'Derechos Humanos', 'DDHH', 'Principios y proteccion de derechos en la funcion policial.', 60, '#2563EB', 'shield', 1, 'Juridica', 'media', TRUE),
  ('DCON', 'Constitucion Politica', 'Constitucion', 'Marco constitucional aplicado al servicio policial.', 60, '#0EA5E9', 'account_balance', 2, 'Juridica', 'media', TRUE),
  ('DPEN', 'Derecho Penal', 'Penal', 'Conceptos penales para intervenciones y procedimientos.', 60, '#F97316', 'gavel', 3, 'Juridica', 'alta', TRUE),
  ('DPRO', 'Derecho Procesal Penal', 'Procesal', 'Actuaciones y garantias en proceso penal.', 60, '#8B5CF6', 'description', 4, 'Procedimental', 'alta', TRUE),
  ('FPEP', 'Funcion Policial y Etica', 'Etica PNP', 'Practica policial, deontologia y uso de la fuerza.', 60, '#10B981', 'local_police', 5, 'Operativa', 'media', TRUE)
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
-- 2) Bancos de prueba (2)
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
  x.nombre,
  x.version,
  x.descripcion,
  150,
  CURRENT_DATE,
  TRUE,
  TRUE
FROM (
  VALUES
    ('Banco Oficiales - Prueba', 'v1.0', 'Banco de prueba para perfil de oficiales'),
    ('Banco Suboficiales - Prueba', 'v1.0', 'Banco de prueba para perfil de suboficiales')
) AS x(nombre, version, descripcion)
WHERE NOT EXISTS (
  SELECT 1
  FROM banco_de_pregunta b
  WHERE b.nombre = x.nombre
    AND b.version = x.version
);

-- --------------------------------------------
-- 3) Generar 30 preguntas por materia en cada banco
--    Total esperado: 300 preguntas
-- --------------------------------------------
WITH bancos AS (
  SELECT id, 'OFI'::text AS prefijo
  FROM banco_de_pregunta
  WHERE nombre = 'Banco Oficiales - Prueba'
    AND version = 'v1.0'

  UNION ALL

  SELECT id, 'SUB'::text AS prefijo
  FROM banco_de_pregunta
  WHERE nombre = 'Banco Suboficiales - Prueba'
    AND version = 'v1.0'
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
    b.prefijo,
    m.id AS materia_id,
    m.codigo AS materia_codigo,
    m.nombre AS materia_nombre,
    n.n
  FROM bancos b
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
  format('%s-%s-%03s', l.prefijo, l.materia_codigo, l.n),
  l.n,
  format(
    '[%s] %s - Pregunta %s: En una situacion operativa, cual es la actuacion mas adecuada segun la normativa vigente?',
    CASE WHEN l.prefijo = 'OFI' THEN 'OFICIAL' ELSE 'SUBOFICIAL' END,
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
      WHEN l.n % 3 = 1 THEN 'Garantias de intervencion'
      ELSE 'Trato digno y no discriminacion'
    END
    WHEN 'DCON' THEN CASE
      WHEN l.n % 3 = 0 THEN 'Derechos fundamentales'
      WHEN l.n % 3 = 1 THEN 'Control constitucional'
      ELSE 'Principios de legalidad'
    END
    WHEN 'DPEN' THEN CASE
      WHEN l.n % 3 = 0 THEN 'Tipicidad y antijuridicidad'
      WHEN l.n % 3 = 1 THEN 'Culpabilidad'
      ELSE 'Participacion y autoria'
    END
    WHEN 'DPRO' THEN CASE
      WHEN l.n % 3 = 0 THEN 'Cadena de custodia'
      WHEN l.n % 3 = 1 THEN 'Actos urgentes'
      ELSE 'Garantias procesales'
    END
    ELSE CASE
      WHEN l.n % 3 = 0 THEN 'Etica y deontologia'
      WHEN l.n % 3 = 1 THEN 'Atencion al ciudadano'
      ELSE 'Disciplina y liderazgo'
    END
  END,
  CASE
    WHEN l.n % 2 = 0 THEN 'Marco legal aplicable'
    ELSE 'Criterio operativo'
  END,
  50 + (l.n % 40),
  TRUE,
  TRUE,
  NOW(),
  NOW()
FROM lote l
WHERE NOT EXISTS (
  SELECT 1
  FROM pregunta p
  WHERE p.codigo_pregunta = format('%s-%s-%03s', l.prefijo, l.materia_codigo, l.n)
);

-- --------------------------------------------
-- 4) Alternativas para preguntas generadas
-- --------------------------------------------
WITH preguntas_objetivo AS (
  SELECT
    p.id,
    p.codigo_pregunta,
    split_part(p.codigo_pregunta, '-', 2) AS materia_codigo,
    right(p.codigo_pregunta, 3)::int AS numero
  FROM pregunta p
  WHERE p.codigo_pregunta ~ '^(OFI|SUB)-(DHUM|DCON|DPEN|DPRO|FPEP)-[0-9]{3}$'
),
materias_objetivo AS (
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
  po.id AS pregunta_id,
  alt.letra,
  CASE alt.letra
    WHEN 'A' THEN format('Aplicar una medida inmediata sin dejar constancia formal en %s.', mo.nombre)
    WHEN 'B' THEN format('Aplicar el procedimiento establecido para %s respetando legalidad y derechos.', mo.nombre)
    WHEN 'C' THEN format('Delegar la decision sin verificar competencia en %s.', mo.nombre)
    ELSE format('Postergar la intervencion de %s sin evaluar riesgo inmediato.', mo.nombre)
  END AS texto,
  CASE
    WHEN po.numero % 4 = 1 AND alt.letra = 'A' THEN TRUE
    WHEN po.numero % 4 = 2 AND alt.letra = 'B' THEN TRUE
    WHEN po.numero % 4 = 3 AND alt.letra = 'C' THEN TRUE
    WHEN po.numero % 4 = 0 AND alt.letra = 'D' THEN TRUE
    ELSE FALSE
  END AS es_correcta,
  alt.orden
FROM preguntas_objetivo po
JOIN materias_objetivo mo
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
-- 5) Sincronizar totales en banco y materia
-- --------------------------------------------
UPDATE banco_de_pregunta b
SET total_preguntas = t.cantidad
FROM (
  SELECT banco_id, COUNT(*)::int AS cantidad
  FROM pregunta
  GROUP BY banco_id
) t
WHERE b.id = t.banco_id
  AND b.nombre IN ('Banco Oficiales - Prueba', 'Banco Suboficiales - Prueba');

UPDATE materia m
SET total_preguntas_banco = t.cantidad,
    actualizado_at = NOW()
FROM (
  SELECT materia_id, COUNT(*)::int AS cantidad
  FROM pregunta
  WHERE materia_id IN (
    SELECT id FROM materia WHERE codigo IN ('DHUM', 'DCON', 'DPEN', 'DPRO', 'FPEP')
  )
  GROUP BY materia_id
) t
WHERE m.id = t.materia_id;

COMMIT;

-- --------------------------------------------
-- 6) Verificacion rapida
-- --------------------------------------------
SELECT
  b.nombre AS banco,
  b.version,
  COUNT(p.id) AS total_preguntas
FROM banco_de_pregunta b
LEFT JOIN pregunta p ON p.banco_id = b.id
WHERE b.nombre IN ('Banco Oficiales - Prueba', 'Banco Suboficiales - Prueba')
GROUP BY b.nombre, b.version
ORDER BY b.nombre;

SELECT
  m.codigo,
  m.nombre AS materia,
  COUNT(p.id) AS total_preguntas
FROM materia m
LEFT JOIN pregunta p ON p.materia_id = m.id
WHERE m.codigo IN ('DHUM', 'DCON', 'DPEN', 'DPRO', 'FPEP')
GROUP BY m.codigo, m.nombre
ORDER BY m.codigo;

