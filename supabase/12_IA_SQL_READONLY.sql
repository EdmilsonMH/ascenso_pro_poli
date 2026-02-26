-- ============================================
-- 12_IA_SQL_READONLY.sql
-- Gateway SQL de solo lectura para IA Tutor
-- Uso: SELECT ... WHERE usuario_id = :user_id ...
-- ============================================

BEGIN;
SET search_path TO public;

CREATE OR REPLACE FUNCTION public.fn_ia_ejecutar_sql_lectura(
  p_usuario_id uuid,
  p_sql text,
  p_max_rows integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := current_setting('request.jwt.claim.role', true);
  v_actor uuid := auth.uid();
  v_sql text;
  v_result jsonb;
  v_max_rows integer := GREATEST(1, LEAST(COALESCE(p_max_rows, 50), 200));
BEGIN
  IF p_usuario_id IS NULL THEN
    RAISE EXCEPTION 'p_usuario_id requerido';
  END IF;

  IF v_role IS DISTINCT FROM 'service_role' AND v_actor IS DISTINCT FROM p_usuario_id THEN
    RAISE EXCEPTION 'No autorizado para consultar datos de otro usuario';
  END IF;

  v_sql := trim(COALESCE(p_sql, ''));
  IF v_sql = '' THEN
    RAISE EXCEPTION 'p_sql requerido';
  END IF;

  IF v_sql ~ ';' THEN
    RAISE EXCEPTION 'No se permite ;';
  END IF;

  IF v_sql !~* '^\s*select\b' THEN
    RAISE EXCEPTION 'Solo se permite SELECT';
  END IF;

  IF v_sql ~* '\b(insert|update|delete|drop|alter|truncate|grant|revoke|create|execute|call|do|copy)\b' THEN
    RAISE EXCEPTION 'Solo lectura';
  END IF;

  IF v_sql ~* '\b(pg_|information_schema|pg_catalog|auth\.)' THEN
    RAISE EXCEPTION 'Esquema no permitido';
  END IF;

  IF v_sql !~* '\:user_id\b' THEN
    RAISE EXCEPTION 'Debes usar :user_id para filtrar por usuario';
  END IF;

  v_sql := replace(v_sql, ':user_id', quote_literal(p_usuario_id::text));

  IF v_sql !~* '\blimit\s+\d+\b' THEN
    v_sql := v_sql || ' LIMIT ' || v_max_rows::text;
  END IF;

  EXECUTE format(
    'SELECT COALESCE(jsonb_agg(t), ''[]''::jsonb) FROM (%s) t',
    v_sql
  )
  INTO v_result;

  RETURN jsonb_build_object(
    'rows', COALESCE(v_result, '[]'::jsonb),
    'count', COALESCE(jsonb_array_length(COALESCE(v_result, '[]'::jsonb)), 0),
    'limited_to', v_max_rows
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ia_ejecutar_sql_lectura(uuid, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ia_ejecutar_sql_lectura(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ia_ejecutar_sql_lectura(uuid, text, integer) TO service_role;

COMMIT;

