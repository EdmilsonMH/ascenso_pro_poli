import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = (__ENV.SUPABASE_URL || '').replace(/\/+$/, '');
const API_KEY =
  __ENV.SUPABASE_SERVICE_ROLE_KEY || __ENV.SUPABASE_ANON_KEY || '';
const USER_IDS = (__ENV.K6_USER_IDS || '')
  .split(',')
  .map((v) => v.trim())
  .filter((v) => v.length > 0);

const TARGET_P95_MS = Number(__ENV.K6_TARGET_P95_MS || 800);
const TARGET_ERROR_RATE = Number(__ENV.K6_TARGET_ERROR_RATE || 0.01);
const REQUEST_TIMEOUT = __ENV.K6_REQUEST_TIMEOUT || '5s';

const WITH_EDGE = String(__ENV.K6_WITH_EDGE || '0') === '1';
const EDGE_PROMPT =
  __ENV.K6_IA_PROMPT ||
  'Genera un resumen breve para panel del tutor. Responde en texto plano.';

const THINK_TIME_MIN_MS = Number(__ENV.K6_THINK_MIN_MS || 150);
const THINK_TIME_MAX_MS = Number(__ENV.K6_THINK_MAX_MS || 350);

export const timeout_rate = new Rate('timeout_rate');
export const server_error_rate = new Rate('server_error_rate');
export const tutor_flow_duration = new Trend('tutor_flow_duration', true);
export const tutor_flow_failed = new Rate('tutor_flow_failed');

if (!BASE_URL) {
  throw new Error('Falta SUPABASE_URL');
}
if (!API_KEY) {
  throw new Error(
    'Falta SUPABASE_SERVICE_ROLE_KEY o SUPABASE_ANON_KEY para autenticacion',
  );
}
if (USER_IDS.length === 0) {
  throw new Error(
    'Falta K6_USER_IDS (lista CSV de user_ids reales para prueba)',
  );
}

const commonHeaders = {
  apikey: API_KEY,
  Authorization: `Bearer ${API_KEY}`,
  'Content-Type': 'application/json',
};

function randomThinkSeconds() {
  const ms =
    THINK_TIME_MIN_MS + Math.random() * (THINK_TIME_MAX_MS - THINK_TIME_MIN_MS);
  return Math.max(ms, 0) / 1000;
}

function pickUserId() {
  const idx = (__VU + __ITER) % USER_IDS.length;
  return USER_IDS[idx];
}

function markFailureMetrics(res, endpoint) {
  const isTimeout =
    !res ||
    res.status === 0 ||
    res.error_code === 1050 ||
    res.error_code === 1211 ||
    res.error_code === 1220 ||
    res.error_code === 1221 ||
    res.error_code === 1230 ||
    res.status === 408 ||
    res.status === 504 ||
    res.status === 524;

  const isServerError = !!res && res.status >= 500;

  timeout_rate.add(isTimeout, { endpoint });
  server_error_rate.add(isServerError, { endpoint });
}

function rpc(functionName, payload, userId) {
  const res = http.post(
    `${BASE_URL}/rest/v1/rpc/${functionName}`,
    JSON.stringify(payload),
    {
      headers: commonHeaders,
      timeout: REQUEST_TIMEOUT,
      tags: {
        endpoint: functionName,
        kind: 'rpc',
        user_id: userId,
      },
    },
  );

  markFailureMetrics(res, functionName);

  const ok = check(res, {
    [`${functionName}: status 2xx`]: (r) => r.status >= 200 && r.status < 300,
  });

  return { ok, res };
}

function edgeDiagnostico(userId) {
  const body = {
    prompt: EDGE_PROMPT,
    mode: 'panel',
    user_id: userId,
  };
  const res = http.post(
    `${BASE_URL}/functions/v1/ia_diagnostico`,
    JSON.stringify(body),
    {
      headers: commonHeaders,
      timeout: REQUEST_TIMEOUT,
      tags: {
        endpoint: 'ia_diagnostico',
        kind: 'edge',
        user_id: userId,
      },
    },
  );

  markFailureMetrics(res, 'ia_diagnostico');

  const ok = check(res, {
    'ia_diagnostico: status 2xx': (r) => r.status >= 200 && r.status < 300,
  });

  return { ok, res };
}

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    tutor_1000_vus: {
      executor: 'ramping-vus',
      startVUs: Number(__ENV.K6_START_VUS || 10),
      gracefulRampDown: '30s',
      stages: [
        { duration: __ENV.K6_STAGE_1 || '2m', target: 200 },
        { duration: __ENV.K6_STAGE_2 || '3m', target: 500 },
        { duration: __ENV.K6_STAGE_3 || '5m', target: 1000 },
        { duration: __ENV.K6_STAGE_HOLD || '15m', target: 1000 },
        { duration: __ENV.K6_STAGE_DOWN || '2m', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: [`p(95)<${TARGET_P95_MS}`],
    http_req_failed: [`rate<${TARGET_ERROR_RATE}`],
    timeout_rate: [`rate<${TARGET_ERROR_RATE}`],
    server_error_rate: [`rate<${TARGET_ERROR_RATE}`],
    tutor_flow_duration: [`p(95)<${TARGET_P95_MS}`],
    tutor_flow_failed: [`rate<${TARGET_ERROR_RATE}`],

    'http_req_duration{endpoint:fn_generar_plan_adaptativo}': [
      `p(95)<${TARGET_P95_MS}`,
    ],
    'http_req_duration{endpoint:fn_calcular_progreso_dinamico}': [
      `p(95)<${TARGET_P95_MS}`,
    ],
    'http_req_duration{endpoint:fn_calcular_dias_disponibles}': [
      `p(95)<${TARGET_P95_MS}`,
    ],
    'http_req_duration{endpoint:fn_tutor_velocidad_dashboard}': [
      `p(95)<${TARGET_P95_MS}`,
    ],
    'http_req_duration{endpoint:fn_tutor_prediccion_olvido_materias}': [
      `p(95)<${TARGET_P95_MS}`,
    ],
  },
};

export default function () {
  const userId = pickUserId();
  const start = Date.now();
  let flowOk = true;

  group('tutor_flow', () => {
    const a = rpc('fn_generar_plan_adaptativo', { p_usuario_id: userId }, userId);
    flowOk = flowOk && a.ok;

    const b = rpc(
      'fn_calcular_progreso_dinamico',
      { p_usuario_id: userId },
      userId,
    );
    flowOk = flowOk && b.ok;

    const c = rpc(
      'fn_calcular_dias_disponibles',
      { p_usuario_id: userId },
      userId,
    );
    flowOk = flowOk && c.ok;

    const d = rpc(
      'fn_tutor_velocidad_dashboard',
      {
        p_usuario_id: userId,
        p_ventana: 1200,
        p_muestra_minima: 10,
        p_half_life_dias: 14,
      },
      userId,
    );
    flowOk = flowOk && d.ok;

    const e = rpc(
      'fn_tutor_prediccion_olvido_materias',
      { p_usuario_id: userId, p_min_prob: 40 },
      userId,
    );
    flowOk = flowOk && e.ok;

    if (WITH_EDGE) {
      const f = edgeDiagnostico(userId);
      flowOk = flowOk && f.ok;
    }
  });

  tutor_flow_duration.add(Date.now() - start);
  tutor_flow_failed.add(!flowOk);

  sleep(randomThinkSeconds());
}
