-- ============================================
-- 17_RANKING_PUBLICO_INVITADO.sql
-- Permite que usuarios anonimos (modo invitado)
-- consulten el ranking publico mediante RPC seguras
-- y lean banco de preguntas publico (solo lectura).
-- ============================================

BEGIN;
SET search_path TO public;

GRANT EXECUTE ON FUNCTION public.obtener_ranking_periodo(
  text,
  text,
  integer,
  integer,
  text
) TO anon;

GRANT EXECUTE ON FUNCTION public.obtener_ranking_mejor_puntaje(
  text,
  integer
) TO anon;

-- Acceso de solo lectura para modo invitado (preguntas reales).
GRANT SELECT ON public.materia TO anon;
GRANT SELECT ON public.pregunta TO anon;
GRANT SELECT ON public.alternativa TO anon;

COMMIT;
