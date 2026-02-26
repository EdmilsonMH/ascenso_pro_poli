-- ============================================
-- 11_IA_TUTOR_CACHE.sql
-- Cache per-user para IA Tutor (DeepSeek)
-- TTL controlado por expires_at desde Edge Function
-- ============================================

BEGIN;
SET search_path TO public;

CREATE TABLE IF NOT EXISTS public.ia_tutor_cache (
  cache_key text PRIMARY KEY,
  user_id uuid NOT NULL,
  mode text NOT NULL CHECK (mode IN ('chat', 'panel')),
  provider text NOT NULL,
  model text NOT NULL,
  prompt_hash text NOT NULL,
  context_hash text NOT NULL,
  response_text text NOT NULL,
  response_json jsonb NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  last_hit_at timestamptz NULL,
  hit_count integer NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS ia_tutor_cache_user_mode_idx
  ON public.ia_tutor_cache (user_id, mode);

CREATE INDEX IF NOT EXISTS ia_tutor_cache_expires_at_idx
  ON public.ia_tutor_cache (expires_at);

ALTER TABLE public.ia_tutor_cache ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.ia_tutor_cache FROM public;
REVOKE ALL ON TABLE public.ia_tutor_cache FROM anon;
REVOKE ALL ON TABLE public.ia_tutor_cache FROM authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.ia_tutor_cache
  TO service_role;

COMMIT;

