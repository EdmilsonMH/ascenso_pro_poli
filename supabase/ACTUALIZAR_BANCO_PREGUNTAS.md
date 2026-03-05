# ACTUALIZAR BANCO DE PREGUNTAS (OFICIALES Y SUBOFICIALES)

Esta guia aplica a tu esquema real de Supabase:
- `materia`
- `banco_de_pregunta`
- `pregunta`
- `alternativa`

No uses la tabla `preguntas` de la guia antigua (`docs/GUIA_SUPABASE.md`), porque no coincide con tu modelo actual.

## 1) Que necesitas tener listo

Para cada pregunta:
- `categoria_objetivo`: `oficial` o `suboficial`
- `codigo_pregunta`: debe empezar con `OFI-` (oficial) o `SUB-` (suboficial)
- `numero_oficial`: entero
- `materia_codigo`: debe existir en `materia.codigo`
- `enunciado`
- `contexto` (opcional, pero recomendado)
- `ubicacion_fuente` (opcional)
- `codigo_fuente` (opcional)
- alternativas (minimo 4):
  - `letra` (`A`, `B`, `C`, `D`, ...)
  - `texto`
  - `es_correcta` (exactamente 1 por pregunta)

## 2) Reglas criticas para que la app funcione

1. La categoria se filtra por prefijo de `codigo_pregunta`.
   - Oficial: `OFI-`
   - Suboficial: `SUB-`

2. `codigo_pregunta` debe ser unico en toda la base.

3. Cada pregunta debe tener `materia_id` valido (si queda `NULL`, se rompe el filtrado por materia en la app).

4. Cada pregunta debe tener alternativas cargadas.

5. En `alternativa`, debe haber 1 sola correcta por pregunta.

## 3) Flujo recomendado de actualizacion

1. Ejecutar migraciones base y parches recientes.
   - Especialmente `17_RANKING_PUBLICO_INVITADO.sql` si usas modo invitado (permite `anon` leer preguntas).

2. Cargar datos a tablas temporales (`staging`) desde CSV/Excel.

3. Validar calidad de datos (duplicados, prefijos, alternativas correctas).

4. Upsert de preguntas con `ON CONFLICT (codigo_pregunta)`.

5. Upsert de alternativas con `ON CONFLICT (pregunta_id, letra)`.

6. Recalcular totales:
   - `banco_de_pregunta.total_preguntas`
   - `materia.total_preguntas_banco`

7. Ejecutar queries de verificacion final.

## 3.1) Estructura minima de staging

```sql
-- Puedes crear estas tablas temporales en una sesion de carga
CREATE TEMP TABLE stg_preguntas (
  codigo_pregunta text,
  numero_oficial int,
  materia_codigo text,
  enunciado text,
  contexto text,
  ubicacion_fuente text,
  codigo_fuente text,
  tipo_pregunta text,
  dificultad_estimada text,
  frecuencia_examen text,
  tema_especifico text,
  subtema text,
  score_importancia int
);

CREATE TEMP TABLE stg_alternativas (
  codigo_pregunta text,
  letra char(1),
  texto text,
  es_correcta boolean,
  orden int
);
```

## 4) SQL de validacion previa (obligatorio)

```sql
-- 1) Duplicados de codigo_pregunta en staging
SELECT codigo_pregunta, COUNT(*)
FROM stg_preguntas
GROUP BY codigo_pregunta
HAVING COUNT(*) > 1;

-- 2) Prefijos invalidos (deben ser OFI- o SUB-)
SELECT codigo_pregunta
FROM stg_preguntas
WHERE codigo_pregunta !~ '^(OFI|SUB)-';

-- 3) Materias inexistentes
SELECT s.materia_codigo, COUNT(*) AS total
FROM stg_preguntas s
LEFT JOIN materia m ON m.codigo = s.materia_codigo
WHERE m.id IS NULL
GROUP BY s.materia_codigo;

-- 4) Preguntas sin alternativas
SELECT s.codigo_pregunta
FROM stg_preguntas s
LEFT JOIN stg_alternativas a ON a.codigo_pregunta = s.codigo_pregunta
GROUP BY s.codigo_pregunta
HAVING COUNT(a.codigo_pregunta) = 0;

-- 5) Preguntas con 0 o mas de 1 correcta
SELECT a.codigo_pregunta,
       SUM(CASE WHEN a.es_correcta THEN 1 ELSE 0 END) AS total_correctas
FROM stg_alternativas a
GROUP BY a.codigo_pregunta
HAVING SUM(CASE WHEN a.es_correcta THEN 1 ELSE 0 END) <> 1;
```

## 5) SQL base de carga (plantilla)

```sql
BEGIN;
SET search_path TO public;

-- A) Crear/actualizar bancos (ajusta nombres/version)
INSERT INTO banco_de_pregunta (nombre, version, descripcion, total_preguntas, fecha_publicacion, activo, es_oficial)
SELECT x.nombre, x.version, x.descripcion, 0, CURRENT_DATE, TRUE, TRUE
FROM (
  VALUES
    ('Banco Oficiales 2026', 'v2.0', 'Banco actualizado oficiales'),
    ('Banco Suboficiales 2026', 'v2.0', 'Banco actualizado suboficiales')
) AS x(nombre, version, descripcion)
WHERE NOT EXISTS (
  SELECT 1
  FROM banco_de_pregunta b
  WHERE b.nombre = x.nombre
    AND b.version = x.version
);

-- B) CTE para obtener IDs de bancos por nombre/version
WITH b_ofi AS (
  SELECT id FROM banco_de_pregunta WHERE nombre = 'Banco Oficiales 2026' AND version = 'v2.0' LIMIT 1
), b_sub AS (
  SELECT id FROM banco_de_pregunta WHERE nombre = 'Banco Suboficiales 2026' AND version = 'v2.0' LIMIT 1
)
INSERT INTO pregunta (
  banco_id,
  materia_id,
  codigo_pregunta,
  numero_oficial,
  enunciado,
  contexto,
  ubicacion_fuente,
  codigo_fuente,
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
  CASE
    WHEN s.codigo_pregunta LIKE 'OFI-%' THEN (SELECT id FROM b_ofi)
    WHEN s.codigo_pregunta LIKE 'SUB-%' THEN (SELECT id FROM b_sub)
    ELSE NULL
  END AS banco_id,
  m.id AS materia_id,
  s.codigo_pregunta,
  s.numero_oficial,
  s.enunciado,
  s.contexto,
  s.ubicacion_fuente,
  s.codigo_fuente,
  COALESCE(s.tipo_pregunta, 'multiple_choice'),
  COALESCE(s.dificultad_estimada, 'medio'),
  COALESCE(s.frecuencia_examen, 'media'),
  COALESCE(s.tema_especifico, 'Banco actualizado'),
  COALESCE(s.subtema, 'General'),
  COALESCE(s.score_importancia, 70),
  TRUE,
  TRUE,
  NOW(),
  NOW()
FROM stg_preguntas s
JOIN materia m ON m.codigo = s.materia_codigo
ON CONFLICT (codigo_pregunta) DO UPDATE
SET
  banco_id = EXCLUDED.banco_id,
  materia_id = EXCLUDED.materia_id,
  numero_oficial = EXCLUDED.numero_oficial,
  enunciado = EXCLUDED.enunciado,
  contexto = EXCLUDED.contexto,
  ubicacion_fuente = EXCLUDED.ubicacion_fuente,
  codigo_fuente = EXCLUDED.codigo_fuente,
  tipo_pregunta = EXCLUDED.tipo_pregunta,
  dificultad_estimada = EXCLUDED.dificultad_estimada,
  frecuencia_examen = EXCLUDED.frecuencia_examen,
  tema_especifico = EXCLUDED.tema_especifico,
  subtema = EXCLUDED.subtema,
  score_importancia = EXCLUDED.score_importancia,
  activo = TRUE,
  revisada = TRUE,
  actualizado_at = NOW();

-- C) Insert/update alternativas
INSERT INTO alternativa (pregunta_id, letra, texto, es_correcta, orden)
SELECT
  p.id,
  a.letra,
  a.texto,
  a.es_correcta,
  COALESCE(a.orden, 0)
FROM stg_alternativas a
JOIN pregunta p ON p.codigo_pregunta = a.codigo_pregunta
ON CONFLICT (pregunta_id, letra) DO UPDATE
SET
  texto = EXCLUDED.texto,
  es_correcta = EXCLUDED.es_correcta,
  orden = EXCLUDED.orden;

-- D) Sincronizar totales por banco
UPDATE banco_de_pregunta b
SET total_preguntas = t.cantidad
FROM (
  SELECT banco_id, COUNT(*)::int AS cantidad
  FROM pregunta
  WHERE activo = TRUE
  GROUP BY banco_id
) t
WHERE b.id = t.banco_id;

-- E) Sincronizar totales por materia
UPDATE materia m
SET total_preguntas_banco = t.cantidad,
    actualizado_at = NOW()
FROM (
  SELECT materia_id, COUNT(*)::int AS cantidad
  FROM pregunta
  WHERE activo = TRUE
  GROUP BY materia_id
) t
WHERE m.id = t.materia_id;

COMMIT;
```

## 6) Verificacion final

```sql
-- Preguntas por banco
SELECT b.nombre, b.version, COUNT(p.id) AS total_preguntas
FROM banco_de_pregunta b
LEFT JOIN pregunta p ON p.banco_id = b.id AND p.activo = TRUE
GROUP BY b.nombre, b.version
ORDER BY b.nombre, b.version;

-- Preguntas por prefijo/categoria real usada por app
SELECT
  CASE
    WHEN codigo_pregunta LIKE 'OFI-%' THEN 'Oficiales'
    WHEN codigo_pregunta LIKE 'SUB-%' THEN 'Suboficiales'
    ELSE 'Sin prefijo'
  END AS categoria,
  COUNT(*) AS total
FROM pregunta
WHERE activo = TRUE
GROUP BY 1
ORDER BY 1;

-- Preguntas sin alternativas
SELECT p.codigo_pregunta
FROM pregunta p
LEFT JOIN alternativa a ON a.pregunta_id = p.id
WHERE p.activo = TRUE
GROUP BY p.id, p.codigo_pregunta
HAVING COUNT(a.id) = 0;

-- Preguntas con numero de correctas invalido
SELECT p.codigo_pregunta,
       SUM(CASE WHEN a.es_correcta THEN 1 ELSE 0 END) AS total_correctas
FROM pregunta p
JOIN alternativa a ON a.pregunta_id = p.id
WHERE p.activo = TRUE
GROUP BY p.codigo_pregunta
HAVING SUM(CASE WHEN a.es_correcta THEN 1 ELSE 0 END) <> 1;
```

## 7) Riesgos comunes

- Cargar `OFI-` y `SUB-` sin prefijo consistente.
- Materias nuevas sin crear primero en `materia`.
- Preguntas sin alternativas o con multiples correctas.
- No ejecutar `17_RANKING_PUBLICO_INVITADO.sql` y luego fallar en modo invitado.
- Dejar `total_preguntas` desactualizado en `banco_de_pregunta`.
