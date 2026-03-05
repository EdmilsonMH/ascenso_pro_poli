-- ============================================
-- 19_BORRAR_BANCO_PREGUNTAS.sql
-- Borra (o desactiva) bancos de preguntas por nombre+version
-- ============================================
--
-- IMPORTANTE:
-- - Cambia v_modo a 'soft' o 'hard'
-- - Cambia la lista de bancos objetivo
-- - Haz backup antes de ejecutar
--
-- MODO soft: desactiva preguntas y banco (reversible)
-- MODO hard: borra banco, preguntas y datos dependientes (irreversible)

BEGIN;
SET search_path TO public;

DO $$
DECLARE
  -- Cambia aqui: 'soft' (seguro) o 'hard' (borrado total)
  v_modo text := 'soft';

  -- Cambia aqui los bancos a borrar: nombre|version
  v_bancos_objetivo text[] := ARRAY[
    'Banco Suboficiales 2025 Promo 2026 (PDF)|v1.0-pdf',
    'Banco Oficiales 2025 Promo 2026 (Clon PDF)|v1.0-pdf'
  ];

  v_total_bancos int;
  v_total_preguntas int;
BEGIN
  CREATE TEMP TABLE tmp_bancos_objetivo ON COMMIT DROP AS
  SELECT b.id, b.nombre, b.version
  FROM banco_de_pregunta b
  WHERE (b.nombre || '|' || b.version) = ANY (v_bancos_objetivo);

  SELECT COUNT(*) INTO v_total_bancos FROM tmp_bancos_objetivo;
  IF v_total_bancos = 0 THEN
    RAISE EXCEPTION
      'No se encontraron bancos objetivo. Revisa nombre/version en v_bancos_objetivo.';
  END IF;

  CREATE TEMP TABLE tmp_preguntas_objetivo ON COMMIT DROP AS
  SELECT p.id, p.materia_id, p.banco_id, p.codigo_pregunta
  FROM pregunta p
  JOIN tmp_bancos_objetivo b ON b.id = p.banco_id;

  SELECT COUNT(*) INTO v_total_preguntas FROM tmp_preguntas_objetivo;

  RAISE NOTICE 'Modo: %', v_modo;
  RAISE NOTICE 'Bancos objetivo: %', v_total_bancos;
  RAISE NOTICE 'Preguntas objetivo: %', v_total_preguntas;

  IF lower(v_modo) = 'soft' THEN
    -- Desactivar preguntas del banco (la app solo consume activo=true)
    UPDATE pregunta
    SET activo = FALSE,
        actualizado_at = NOW()
    WHERE id IN (SELECT id FROM tmp_preguntas_objetivo);

    -- Desactivar banco
    UPDATE banco_de_pregunta
    SET activo = FALSE
    WHERE id IN (SELECT id FROM tmp_bancos_objetivo);

  ELSIF lower(v_modo) = 'hard' THEN
    -- Tablas con FK a pregunta SIN cascada
    DELETE FROM correlacion_preguntas
    WHERE pregunta_a_id IN (SELECT id FROM tmp_preguntas_objetivo)
       OR pregunta_b_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM cola_repaso_inteligente
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM exposicion_pregunta
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM respuesta_batalla
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM prediccion_olvido
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM error_analizado
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM respuesta_usuario
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    -- Tablas con cascada (igual se borran explicitamente para trazabilidad)
    DELETE FROM referencia_legal
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM alternativa
    WHERE pregunta_id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM pregunta
    WHERE id IN (SELECT id FROM tmp_preguntas_objetivo);

    DELETE FROM banco_de_pregunta
    WHERE id IN (SELECT id FROM tmp_bancos_objetivo);

  ELSE
    RAISE EXCEPTION 'Modo invalido: %. Usa soft o hard.', v_modo;
  END IF;

  -- Recalcular totales por banco (preguntas activas)
  UPDATE banco_de_pregunta b
  SET total_preguntas = t.cantidad
  FROM (
    SELECT banco_id, COUNT(*)::int AS cantidad
    FROM pregunta
    WHERE activo = TRUE
    GROUP BY banco_id
  ) t
  WHERE b.id = t.banco_id;

  UPDATE banco_de_pregunta b
  SET total_preguntas = 0
  WHERE NOT EXISTS (
    SELECT 1
    FROM pregunta p
    WHERE p.banco_id = b.id
      AND p.activo = TRUE
  );

  -- Recalcular totales por materia (preguntas activas)
  UPDATE materia m
  SET total_preguntas_banco = t.cantidad,
      actualizado_at = NOW()
  FROM (
    SELECT m2.id AS materia_id, COUNT(p.id)::int AS cantidad
    FROM materia m2
    LEFT JOIN pregunta p
      ON p.materia_id = m2.id
     AND p.activo = TRUE
    GROUP BY m2.id
  ) t
  WHERE m.id = t.materia_id;
END $$;

COMMIT;

-- Verificacion
SELECT b.nombre, b.version, b.activo, b.total_preguntas
FROM banco_de_pregunta b
ORDER BY b.nombre, b.version;

SELECT
  CASE
    WHEN p.codigo_pregunta LIKE 'OFI-%' THEN 'OFI'
    WHEN p.codigo_pregunta LIKE 'SUB-%' THEN 'SUB'
    ELSE 'OTRO'
  END AS prefijo,
  COUNT(*) AS total
FROM pregunta p
WHERE p.activo = TRUE
GROUP BY 1
ORDER BY 1;

