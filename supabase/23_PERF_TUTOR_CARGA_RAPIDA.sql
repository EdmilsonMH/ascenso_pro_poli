-- ============================================
-- 23_PERF_TUTOR_CARGA_RAPIDA.sql
-- Objetivo:
-- Acelerar carga de practicas en Tutor IA
-- (filtros por banco/materia + estadisticas por usuario)
-- ============================================

BEGIN;
SET search_path TO public;

-- Preguntas: filtros mas comunes del cliente.
CREATE INDEX IF NOT EXISTS idx_pregunta_activo_banco_materia_numero
ON public.pregunta (activo, banco_id, materia_id, numero_oficial, id);

CREATE INDEX IF NOT EXISTS idx_pregunta_activo_banco_numero
ON public.pregunta (activo, banco_id, numero_oficial, id);

-- Exposicion: lecturas por usuario/pregunta para priorizacion.
CREATE INDEX IF NOT EXISTS idx_exposicion_usuario_pregunta_comp
ON public.exposicion_pregunta (usuario_id, pregunta_id);

CREATE INDEX IF NOT EXISTS idx_exposicion_usuario_actualizado_comp
ON public.exposicion_pregunta (usuario_id, actualizado_at DESC);

-- Alternativas: carga por lista de preguntas.
CREATE INDEX IF NOT EXISTS idx_alternativa_pregunta_orden
ON public.alternativa (pregunta_id, orden);

-- Historial de respuestas: consultas de ultimo intento por pregunta.
CREATE INDEX IF NOT EXISTS idx_respuesta_usuario_usuario_pregunta_respondida
ON public.respuesta_usuario (usuario_id, pregunta_id, respondida_at DESC);

COMMIT;

