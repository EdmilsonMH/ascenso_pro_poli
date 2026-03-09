// @ts-nocheck
/// <reference lib="deno.ns" />
/// <reference lib="dom" />
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const PROVIDER_NAME = "gemini";
const CACHE_TABLE = "ia_tutor_cache";
const TUTOR_STATE_TABLE = "ia_tutor_estado_usuario";
const CACHE_TEMPLATE_VERSION = "v2";
const TTL_SECONDS_CHAT = 90;
const TTL_SECONDS_PANEL = 600;
const MAX_OUTPUT_TOKENS = 420;

type Mode = "chat" | "panel";

type GeminiCallResult = {
  text: string;
  finishReason: string | null;
  modelUsed: string;
  raw: unknown;
};

type GeminiHttpError = {
  kind: "gemini_http";
  status: number;
  statusText: string;
  model: string;
  details: unknown;
};

function nowIso() {
  return new Date().toISOString();
}

function normalizarModo(value: unknown): Mode {
  const raw = String(value ?? "").trim().toLowerCase();
  return raw === "panel" ? "panel" : "chat";
}

function ttlSegundosPorModo(mode: Mode): number {
  return mode === "panel" ? TTL_SECONDS_PANEL : TTL_SECONDS_CHAT;
}

function normalizarPromptCache(prompt: string): string {
  return prompt.trim().replace(/\s+/g, " ");
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function supabaseHeaders(serviceRoleKey: string) {
  return {
    "Content-Type": "application/json",
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
  };
}

async function fetchSupabaseRows(
  table: string,
  params: Record<string, string>,
  supabaseUrl: string,
  serviceRoleKey: string,
) {
  const search = new URLSearchParams(params);
  const url = `${supabaseUrl}/rest/v1/${table}?${search.toString()}`;
  const response = await fetch(url, {
    method: "GET",
    headers: supabaseHeaders(serviceRoleKey),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`${table} ${response.status}: ${details}`);
  }

  const data = await response.json();
  return Array.isArray(data) ? data : [];
}

async function upsertSupabaseRow(
  table: string,
  row: Record<string, unknown>,
  supabaseUrl: string,
  serviceRoleKey: string,
  onConflict = "cache_key",
) {
  const url =
    `${supabaseUrl}/rest/v1/${table}?on_conflict=${encodeURIComponent(onConflict)}`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      ...supabaseHeaders(serviceRoleKey),
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(row),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`upsert ${table} ${response.status}: ${details}`);
  }
}

async function patchSupabaseRows(
  table: string,
  params: Record<string, string>,
  payload: Record<string, unknown>,
  supabaseUrl: string,
  serviceRoleKey: string,
) {
  const search = new URLSearchParams(params);
  const url = `${supabaseUrl}/rest/v1/${table}?${search.toString()}`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      ...supabaseHeaders(serviceRoleKey),
      Prefer: "return=minimal",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`patch ${table} ${response.status}: ${details}`);
  }
}

function toNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toSafeText(value: unknown): string {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function toShortText(value: unknown, maxChars = 220): string {
  const txt = toSafeText(value);
  if (txt.length <= maxChars) return txt;
  return `${txt.slice(0, maxChars).trim()}...`;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function itemToText(value: unknown): string {
  if (typeof value === "string" || typeof value === "number") {
    return toSafeText(value);
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const row = value as Record<string, unknown>;
    return toSafeText(row["materia"] ?? row["nombre"] ?? row["id"] ?? "");
  }
  return "";
}

function toStringArray(value: unknown, max = 5): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((v) => itemToText(v))
    .filter((v) => v.length > 0)
    .slice(0, max);
}

function normalizarEstadoTutorCompacto(estadoRaw: unknown) {
  const estado = asRecord(estadoRaw);
  const plan = asRecord(estado["plan_dia"] ?? estado["plan"]);
  const progreso = asRecord(estado["progreso"] ?? estado["avance"]);
  const diagnostico = asRecord(estado["diagnostico"]);
  const ranking = asRecord(estado["ranking"]);

  return {
    plan_hoy: {
      fecha: toSafeText(plan["fecha"] ?? plan["fecha_objetivo"]),
      total_preguntas: toNumber(
        plan["total_preguntas"] ?? plan["total_preguntas_dia"],
      ),
      nuevas: toNumber(plan["nuevas"] ?? plan["cantidad_nuevas"]),
      repaso: toNumber(plan["repaso"] ?? plan["cantidad_repaso"]),
      tiempo_minutos: toNumber(
        plan["tiempo_minutos"] ?? plan["tiempo_practica"] ??
          plan["tiempo_total_minutos"],
      ),
      materias_prioritarias: toStringArray(
        plan["materias_prioritarias"] ?? plan["foco_materias"],
        4,
      ),
    },
    progreso: {
      avance_pct: toNumber(progreso["avance_pct"] ?? progreso["progreso_pct"]),
      racha_dias: toNumber(progreso["racha_dias"] ?? progreso["dias_consecutivos"]),
      respondidas_hoy: toNumber(
        progreso["respondidas_hoy"] ?? progreso["preguntas_hoy"],
      ),
      correctas_hoy: toNumber(progreso["correctas_hoy"]),
    },
    diagnostico: {
      nivel: toSafeText(diagnostico["nivel"] ?? diagnostico["estado"]),
      resumen: toShortText(
        diagnostico["resumen"] ?? diagnostico["texto"] ??
          diagnostico["diagnostico"],
      ),
      materias_riesgo: toStringArray(
        diagnostico["materias_riesgo"] ?? diagnostico["debilidades"],
        4,
      ),
    },
    ranking: {
      puesto_actual: toNumber(ranking["puesto_actual"] ?? ranking["posicion"]),
      total_participantes: toNumber(
        ranking["total_participantes"] ?? ranking["total"],
      ),
      percentil: toNumber(ranking["percentil"]),
    },
  };
}

async function obtenerEstadoTutorDesdeBD(
  userId: string,
  supabaseUrl: string,
  serviceRoleKey: string,
) {
  try {
    const rows = await fetchSupabaseRows(
      TUTOR_STATE_TABLE,
      {
        select: "usuario_id,estado,fuente,version,actualizado_at",
        usuario_id: `eq.${userId}`,
        limit: "1",
      },
      supabaseUrl,
      serviceRoleKey,
    );

    const row = rows?.[0];
    if (!row) return null;

    return {
      fuente: toSafeText(row?.fuente) || "app",
      version: toNumber(row?.version, 1),
      actualizado_at: toSafeText(row?.actualizado_at),
      estado_compacto: normalizarEstadoTutorCompacto(row?.estado),
    };
  } catch (_) {
    return null;
  }
}

function contextoCacheEstable(contextoBD: any) {
  const perfil = contextoBD?.perfil ?? {};
  const resumen = contextoBD?.resumen_historial ?? {};
  const fortalezas = Array.isArray(contextoBD?.fortalezas_materia)
    ? contextoBD.fortalezas_materia
    : [];
  const debilidades = Array.isArray(contextoBD?.debilidades_materia)
    ? contextoBD.debilidades_materia
    : [];
  const criticas = Array.isArray(contextoBD?.preguntas_criticas)
    ? contextoBD.preguntas_criticas
    : [];
  const tutorMemoria = asRecord(contextoBD?.tutor_memoria_usuario);
  const estadoCompacto = asRecord(tutorMemoria["estado_compacto"]);

  return {
    perfil: {
      tasa_acierto_global: toNumber(perfil?.tasa_acierto_global),
      velocidad_promedio_segundos: toNumber(perfil?.velocidad_promedio_segundos),
      dias_consecutivos_estudio: toNumber(perfil?.dias_consecutivos_estudio),
      tiempo_total_estudio_minutos: toNumber(perfil?.tiempo_total_estudio_minutos),
    },
    resumen_historial: {
      total_sesiones: toNumber(resumen?.total_sesiones),
      sesiones_completadas: toNumber(resumen?.sesiones_completadas),
      promedio_correctas_ultimas_12: toNumber(resumen?.promedio_correctas_ultimas_12),
      mejor_puntaje_ultimas_12: toNumber(resumen?.mejor_puntaje_ultimas_12),
      efectividad_reciente_pct: toNumber(resumen?.efectividad_reciente_pct),
    },
    fortalezas_materia: fortalezas
      .slice(0, 5)
      .map((f: any) => ({
        materia: toSafeText(f?.materia),
        tasa_dominio: toNumber(f?.tasa_dominio),
      })),
    debilidades_materia: debilidades
      .slice(0, 5)
      .map((d: any) => ({
        materia: toSafeText(d?.materia),
        tasa_dominio: toNumber(d?.tasa_dominio),
      })),
    preguntas_criticas: criticas
      .slice(0, 5)
      .map((q: any) => ({
        pregunta_id: toSafeText(q?.pregunta_id),
        fallos: toNumber(q?.fallos),
      })),
    tutor_memoria_usuario: {
      plan_hoy: asRecord(estadoCompacto["plan_hoy"]),
      progreso: asRecord(estadoCompacto["progreso"]),
      diagnostico: asRecord(estadoCompacto["diagnostico"]),
      ranking: asRecord(estadoCompacto["ranking"]),
    },
  };
}

async function firmaCache({
  userId,
  mode,
  prompt,
  contextoEstable,
  model,
}: {
  userId: string;
  mode: Mode;
  prompt: string;
  contextoEstable: unknown;
  model: string;
}) {
  const promptNormalizado = normalizarPromptCache(prompt);
  const promptHash = await sha256Hex(promptNormalizado);
  const contextHash = await sha256Hex(JSON.stringify(contextoEstable));
  const rawKey =
    `${userId}|${mode}|${promptNormalizado}|${contextHash}|${model}|${CACHE_TEMPLATE_VERSION}`;
  const cacheKey = await sha256Hex(rawKey);

  return { cacheKey, promptHash, contextHash, promptNormalizado };
}

async function obtenerCacheValida({
  cacheKey,
  supabaseUrl,
  serviceRoleKey,
}: {
  cacheKey: string;
  supabaseUrl: string;
  serviceRoleKey: string;
}) {
  const rows = await fetchSupabaseRows(
    CACHE_TABLE,
    {
      select:
        "cache_key,user_id,mode,provider,model,response_text,response_json,created_at,expires_at,last_hit_at,hit_count",
      cache_key: `eq.${cacheKey}`,
      limit: "1",
    },
    supabaseUrl,
    serviceRoleKey,
  );

  const row = rows?.[0];
  if (!row) return null;

  const now = Date.now();
  const expiresAt = new Date(String(row?.expires_at ?? "")).getTime();
  if (!Number.isFinite(expiresAt) || expiresAt <= now) return null;

  return row;
}

async function registrarHitCache({
  cacheKey,
  currentHitCount,
  supabaseUrl,
  serviceRoleKey,
}: {
  cacheKey: string;
  currentHitCount: number;
  supabaseUrl: string;
  serviceRoleKey: string;
}) {
  await patchSupabaseRows(
    CACHE_TABLE,
    { cache_key: `eq.${cacheKey}` },
    {
      last_hit_at: nowIso(),
      hit_count: Math.max(0, currentHitCount) + 1,
    },
    supabaseUrl,
    serviceRoleKey,
  );
}

async function guardarCache({
  cacheKey,
  userId,
  mode,
  model,
  promptHash,
  contextHash,
  text,
  responseJson,
  ttlSeconds,
  supabaseUrl,
  serviceRoleKey,
}: {
  cacheKey: string;
  userId: string;
  mode: Mode;
  model: string;
  promptHash: string;
  contextHash: string;
  text: string;
  responseJson: Record<string, unknown>;
  ttlSeconds: number;
  supabaseUrl: string;
  serviceRoleKey: string;
}) {
  const createdAt = new Date();
  const expiresAt = new Date(createdAt.getTime() + ttlSeconds * 1000);

  await upsertSupabaseRow(
    CACHE_TABLE,
    {
      cache_key: cacheKey,
      user_id: userId,
      mode,
      provider: PROVIDER_NAME,
      model,
      prompt_hash: promptHash,
      context_hash: contextHash,
      response_text: text,
      response_json: responseJson,
      created_at: createdAt.toISOString(),
      expires_at: expiresAt.toISOString(),
      last_hit_at: createdAt.toISOString(),
      hit_count: 0,
    },
    supabaseUrl,
    serviceRoleKey,
  );
}

function resumenDetails(details: unknown) {
  const raw = typeof details === "string" ? details : JSON.stringify(details);
  return raw.length <= 300 ? raw : `${raw.slice(0, 300)}...`;
}

function esError429(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const anyErr = err as Record<string, unknown>;
  if (anyErr["status"] === 429) return true;
  const details = String(anyErr["details"] ?? "");
  const lower = details.toLowerCase();
  return details.includes("429") ||
    lower.includes("quota") ||
    lower.includes("rate limit") ||
    lower.includes("too many requests") ||
    lower.includes("resource_exhausted");
}

function respuestaPareceIncompleta(texto: string) {
  const t = (texto ?? "").trim();
  if (!t) return true;
  if (t.length < 16) return false;
  if (/[.!?]["')\]]?$/.test(t)) return false;
  if (/[:,;-]$/.test(t)) return true;
  return true;
}

function debeRegenerar(text: string, finishReason: string | null) {
  const t = (text ?? "").trim();
  if (!t) return true;
  const fr = (finishReason ?? "").toLowerCase().trim();
  if (fr && fr !== "stop") return true;
  return respuestaPareceIncompleta(t);
}

async function llamarGemini({
  apiKey,
  baseUrl,
  model,
  prompt,
}: {
  apiKey: string;
  baseUrl: string;
  model: string;
  prompt: string;
}): Promise<GeminiCallResult> {
  const normalizedBase = baseUrl.replace(/\/+$/, "");
  const url =
    `${normalizedBase}/models/${encodeURIComponent(model)}:generateContent?key=${
      encodeURIComponent(apiKey)
    }`;

  const payload = {
    contents: [
      {
        role: "user",
        parts: [{ text: prompt }],
      },
    ],
    generationConfig: {
      temperature: 0.25,
      topP: 0.9,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
    },
  };

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const detailsText = await response.text();
    let details: unknown = detailsText;
    try {
      details = JSON.parse(detailsText);
    } catch (_) {
      // keep raw text
    }
    throw {
      kind: "gemini_http",
      status: response.status,
      statusText: response.statusText,
      model,
      details,
    } as GeminiHttpError;
  }

  const data = await response.json();
  const candidate = data?.candidates?.[0] ?? {};
  const finishReason = candidate?.finishReason ?? null;
  const parts = Array.isArray(candidate?.content?.parts)
    ? candidate.content.parts
    : [];
  const text = parts
      .map((p) => {
        if (typeof p?.text === "string") return p.text;
        return "";
      })
      .join("")
      .trim();

  if (!text) {
    throw new Response(
      JSON.stringify({
        error: "Gemini devolvio respuesta vacia",
        finishReason,
        promptFeedback: data?.promptFeedback ?? null,
      }),
      {
        status: 502,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const modelUsed = toSafeText(data?.modelVersion) || model;
  return { text, finishReason, modelUsed, raw: data };
}

function construirMensajeRateLimit(contextoBD: any) {
  const primeraDebilidad = Array.isArray(contextoBD?.debilidades_materia) &&
      contextoBD.debilidades_materia.length > 0
    ? String(contextoBD.debilidades_materia[0]?.materia ?? "").trim()
    : "";

  if (primeraDebilidad) {
    return `Tengo alta demanda de IA en este momento (limite temporal de Gemini). Mientras se libera, refuerza ${primeraDebilidad} durante 15 minutos y vuelve a escribirme.`;
  }
  return "Tengo alta demanda de IA en este momento (limite temporal de Gemini). Intenta nuevamente en 1 a 2 minutos.";
}

function logEjecucion(data: Record<string, unknown>) {
  console.log(
    JSON.stringify({
      event: "ia_diagnostico",
      ts: nowIso(),
      ...data,
    }),
  );
}

function extraerBearerToken(authHeader: string | null) {
  const raw = String(authHeader ?? "").trim();
  if (!raw) return "";
  const match = /^Bearer\s+(.+)$/i.exec(raw);
  if (!match || !match[1]) return "";
  return match[1].trim();
}

async function resolverUsuarioAutenticado({
  supabaseUrl,
  serviceRoleKey,
  bearerToken,
}: {
  supabaseUrl: string | undefined;
  serviceRoleKey: string | undefined;
  bearerToken: string;
}) {
  if (!supabaseUrl || !serviceRoleKey || !bearerToken) return "";

  const authUrl = `${supabaseUrl}/auth/v1/user`;
  try {
    const response = await fetch(authUrl, {
      method: "GET",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${bearerToken}`,
      },
    });
    if (!response.ok) return "";

    const data = await response.json();
    const id = typeof data?.id === "string" ? data.id.trim() : "";
    return id;
  } catch (_) {
    return "";
  }
}

async function obtenerContextoUsuarioDesdeBD(
  userId: string,
  supabaseUrl: string,
  serviceRoleKey: string,
) {
  const estadoTutorPromise = obtenerEstadoTutorDesdeBD(
    userId,
    supabaseUrl,
    serviceRoleKey,
  );
  const [
    estadoTutor,
    perfilRows,
    estadisticaRows,
    dominiosRows,
    sesionesRows,
    respuestasRows,
  ] = await Promise.all([
    estadoTutorPromise,
    fetchSupabaseRows(
      "perfil_usuario",
      {
        select:
          "tasa_acierto_global,velocidad_promedio_segundos,dias_consecutivos_estudio",
        usuario_id: `eq.${userId}`,
        limit: "1",
      },
      supabaseUrl,
      serviceRoleKey,
    ),
    fetchSupabaseRows(
      "estadistica_usuario",
      {
        select: "tiempo_total_estudio_minutos",
        usuario_id: `eq.${userId}`,
        limit: "1",
      },
      supabaseUrl,
      serviceRoleKey,
    ),
    fetchSupabaseRows(
      "dominio_materia",
      {
        select: "tasa_dominio,materia:materia_id(nombre)",
        usuario_id: `eq.${userId}`,
        limit: "40",
      },
      supabaseUrl,
      serviceRoleKey,
    ),
    fetchSupabaseRows(
      "sesion_practica",
      {
        select:
          "id,creado_at,fecha_inicio,fecha_fin,completada,total_preguntas_planeadas,preguntas_respondidas,preguntas_correctas,preguntas_incorrectas,preguntas_omitidas",
        usuario_id: `eq.${userId}`,
        order: "creado_at.desc",
        limit: "24",
      },
      supabaseUrl,
      serviceRoleKey,
    ),
    fetchSupabaseRows(
      "respuesta_usuario",
      {
        select: "es_correcta,fue_omitida,respondida_at,pregunta_id",
        usuario_id: `eq.${userId}`,
        order: "respondida_at.desc",
        limit: "120",
      },
      supabaseUrl,
      serviceRoleKey,
    ),
  ]);

  const perfil = perfilRows?.[0] ?? {};
  const estadistica = estadisticaRows?.[0] ?? {};

  const dominios = dominiosRows
    .map((d) => {
      const nombre = d?.materia?.nombre ?? "Materia";
      const tasa = Number(d?.tasa_dominio ?? 0);
      return {
        materia: String(nombre),
        tasa_dominio: Number.isFinite(tasa) ? tasa : 0,
      };
    })
    .sort((a, b) => b.tasa_dominio - a.tasa_dominio);

  const fortalezas = dominios.filter((d) => d.tasa_dominio >= 75).slice(0, 5);
  const debilidades = [...dominios]
    .sort((a, b) => a.tasa_dominio - b.tasa_dominio)
    .filter((d) => d.tasa_dominio < 65)
    .slice(0, 5);

  const sesiones = sesionesRows.map((s) => {
    const fechaRef = s?.fecha_fin ?? s?.creado_at ?? s?.fecha_inicio ?? null;
    const correctas = Number(s?.preguntas_correctas ?? 0);
    const incorrectas = Number(s?.preguntas_incorrectas ?? 0);
    const omitidas = Number(s?.preguntas_omitidas ?? 0);
    const respondidas = Number(s?.preguntas_respondidas ?? 0);
    return {
      fecha: fechaRef,
      completada: s?.completada === true,
      correctas: Number.isFinite(correctas) ? correctas : 0,
      incorrectas: Number.isFinite(incorrectas) ? incorrectas : 0,
      omitidas: Number.isFinite(omitidas) ? omitidas : 0,
      respondidas: Number.isFinite(respondidas) ? respondidas : 0,
    };
  });

  const sesionesRecientes = sesiones.slice(0, 8);
  const completadas = sesiones.filter((s) => s.completada).length;
  const promedioCorrectas = sesionesRecientes.length > 0
    ? Number(
      (
        sesionesRecientes.reduce((acc, s) => acc + s.correctas, 0) /
        sesionesRecientes.length
      ).toFixed(2),
    )
    : 0;
  const mejorPuntaje = sesionesRecientes.length > 0
    ? Math.max(...sesionesRecientes.map((s) => s.correctas))
    : 0;

  const respuestasValidas = respuestasRows.filter((r) =>
    r?.fue_omitida !== true && typeof r?.es_correcta === "boolean"
  );
  const correctasRecientes = respuestasValidas.filter((r) =>
    r.es_correcta === true
  ).length;
  const totalRecientes = respuestasValidas.length;
  const efectividadReciente = totalRecientes > 0
    ? Number(((correctasRecientes * 100) / totalRecientes).toFixed(2))
    : 0;

  const fallosPorPregunta = new Map<string, number>();
  for (const r of respuestasRows) {
    if (r?.fue_omitida === true || r?.es_correcta !== false) continue;
    const preguntaId = String(r?.pregunta_id ?? "");
    if (!preguntaId) continue;
    fallosPorPregunta.set(
      preguntaId,
      (fallosPorPregunta.get(preguntaId) ?? 0) + 1,
    );
  }
  const preguntasCriticas = Array.from(fallosPorPregunta.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([pregunta_id, fallos]) => ({ pregunta_id, fallos }));

  return {
    usuario_id: userId,
    perfil: {
      tasa_acierto_global: Number(perfil?.tasa_acierto_global ?? 0),
      velocidad_promedio_segundos: Number(perfil?.velocidad_promedio_segundos ?? 0),
      dias_consecutivos_estudio: Number(perfil?.dias_consecutivos_estudio ?? 0),
      tiempo_total_estudio_minutos: Number(
        estadistica?.tiempo_total_estudio_minutos ?? 0,
      ),
    },
    resumen_historial: {
      total_sesiones: sesiones.length,
      sesiones_completadas: completadas,
      promedio_correctas_ultimas_12: promedioCorrectas,
      mejor_puntaje_ultimas_12: mejorPuntaje,
      efectividad_reciente_pct: efectividadReciente,
    },
    fortalezas_materia: fortalezas,
    debilidades_materia: debilidades,
    sesiones_recientes: sesionesRecientes,
    preguntas_criticas: preguntasCriticas,
    tutor_memoria_usuario: estadoTutor ?? null,
  };
}

function recortarTexto(value: string, maxChars = 900) {
  const txt = String(value ?? "").trim();
  if (txt.length <= maxChars) return txt;
  return `${txt.slice(0, maxChars).trim()}...`;
}

function extraerMensajeUsuario(promptRaw: string) {
  const raw = String(promptRaw ?? "").trim();
  if (!raw) return "";

  const matchConComillas = /MENSAJE DEL ESTUDIANTE:\s*"([\s\S]*?)"\s*(?:REGLAS:|$)/i
    .exec(raw);
  if (matchConComillas?.[1]) {
    return recortarTexto(matchConComillas[1], 700);
  }

  const matchSinComillas = /MENSAJE DEL ESTUDIANTE:\s*([\s\S]*?)\s*(?:REGLAS:|$)/i
    .exec(raw);
  if (matchSinComillas?.[1]) {
    return recortarTexto(matchSinComillas[1], 700);
  }

  const matchResponder = /MENSAJE A RESPONDER:\s*([\s\S]*)$/i.exec(raw);
  if (matchResponder?.[1]) {
    return recortarTexto(matchResponder[1], 700);
  }

  return recortarTexto(raw, 700);
}

function construirPromptTutorFinal({
  mensajeUsuario,
  mode,
  contextoBD,
}: {
  mensajeUsuario: string;
  mode: Mode;
  contextoBD: any;
}) {
  const contextoCompacto = contextoCacheEstable(contextoBD ?? {});
  const formato =
    mode === "panel"
      ? "80 a 130 palabras"
      : "90 a 150 palabras";

  return `
Eres el Tutor IA Personal para preparacion de ascenso PNP.
Tu trabajo es entrenar al estudiante con acciones concretas, medibles y enfocadas en examen.
No respondas como chatbot general ni menciones politicas internas del modelo.

CONTEXTO_USUARIO_JSON:
${JSON.stringify(contextoCompacto)}

CONSULTA_DEL_USUARIO:
${mensajeUsuario}

INSTRUCCIONES:
- Personaliza usando el contexto. Prioriza debilidades_materia y preguntas_criticas si existen.
- Si existe tutor_memoria_usuario, usa su plan_hoy/progreso/diagnostico/ranking para responder mas preciso.
- Si faltan datos para decidir, dilo brevemente y pide 1 dato puntual en "Control".
- Evita relleno, frases vacias y explicaciones largas.
- No uses markdown ni bloques de codigo.
- Longitud total: ${formato}.

FORMATO OBLIGATORIO DE SALIDA (texto plano):
Diagnostico: ...
Accion_hoy: ...
Pasos: 1) ... 2) ... 3) ...
Control: ...
Seguimiento_24h: ...
`.trim();
}

serve(async (req) => {
  const startedAt = Date.now();

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization");
  const apiKeyHeader = req.headers.get("apikey");
  if (!authHeader && !apiKeyHeader) {
    return new Response(JSON.stringify({ error: "No autorizado" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let prompt = "";
  let requestedUserId = "";
  let mode: Mode = "chat";
  let usarContextoBd = true;
  try {
    const body = await req.json();
    if (body && typeof body.prompt === "string") {
      prompt = body.prompt;
    }
    if (body && typeof body.user_id === "string") {
      requestedUserId = body.user_id.trim();
    }
    if (body && typeof body.usar_contexto_bd === "boolean") {
      usarContextoBd = body.usar_contexto_bd;
    }
    mode = normalizarModo(body?.mode);
  } catch (_) {
    // ignore parse errors
  }

  if (!prompt.trim()) {
    return new Response(JSON.stringify({ error: "Prompt requerido" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const bearerToken = extraerBearerToken(authHeader);
  const callerUserId = await resolverUsuarioAutenticado({
    supabaseUrl,
    serviceRoleKey,
    bearerToken,
  });

  if (requestedUserId && !callerUserId) {
    return new Response(
      JSON.stringify({
        error: "Sesion invalida para usar contexto personal",
      }),
      {
        status: 401,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  if (
    requestedUserId &&
    callerUserId &&
    requestedUserId !== callerUserId
  ) {
    return new Response(
      JSON.stringify({
        error: "No autorizado para usar user_id distinto al de tu sesion",
      }),
      {
        status: 403,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const userId = callerUserId;
  if (!userId) {
    usarContextoBd = false;
  }

  let contextoBD = null;
  if (usarContextoBd && userId && supabaseUrl && serviceRoleKey) {
    try {
      contextoBD = await obtenerContextoUsuarioDesdeBD(
        userId,
        supabaseUrl,
        serviceRoleKey,
      );
    } catch (e) {
      contextoBD = { error_contexto_bd: String(e) };
    }
  }

  const promptOriginal = prompt.trim();
  const promptLower = promptOriginal.toLowerCase();
  const promptEsEstructurado = promptLower.includes("devuelve solo json") ||
    promptLower.includes("no agregues texto fuera del json") ||
    promptLower.includes("solo una frase corta");

  const mensajeUsuario = extraerMensajeUsuario(promptOriginal) || promptOriginal;
  const promptFinal = promptEsEstructurado
    ? promptOriginal
    : construirPromptTutorFinal({
      mensajeUsuario,
      mode,
      contextoBD,
    });
  const promptParaCache = promptEsEstructurado ? promptOriginal : mensajeUsuario;

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return new Response(
      JSON.stringify({ error: "GEMINI_API_KEY no configurada" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const baseUrl = Deno.env.get("GEMINI_BASE_URL") ??
    "https://generativelanguage.googleapis.com/v1beta";
  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-1.5-flash";

  const cacheHabilitada = Boolean(supabaseUrl && serviceRoleKey && userId);
  const ttlSeconds = ttlSegundosPorModo(mode);
  let cacheKey = "";
  let promptHash = "";
  let contextHash = "";

  try {
    if (cacheHabilitada) {
      const contextoEstable = contextoCacheEstable(contextoBD);
      const firma = await firmaCache({
        userId,
        mode,
        prompt: promptParaCache,
        contextoEstable,
        model,
      });
      cacheKey = firma.cacheKey;
      promptHash = firma.promptHash;
      contextHash = firma.contextHash;

      const cacheRow = await obtenerCacheValida({
        cacheKey,
        supabaseUrl: supabaseUrl!,
        serviceRoleKey: serviceRoleKey!,
      });

      if (cacheRow) {
        const createdAtTs = new Date(String(cacheRow?.created_at ?? "")).getTime();
        const ageSec = Number.isFinite(createdAtTs)
          ? Math.max(0, Math.floor((Date.now() - createdAtTs) / 1000))
          : 0;
        const responseJson = (cacheRow?.response_json &&
            typeof cacheRow.response_json === "object")
          ? cacheRow.response_json
          : {};
        const textFromCache = toSafeText(cacheRow?.response_text) ||
          toSafeText((responseJson as Record<string, unknown>)?.["text"]);

        await registrarHitCache({
          cacheKey,
          currentHitCount: toNumber(cacheRow?.hit_count, 0),
          supabaseUrl: supabaseUrl!,
          serviceRoleKey: serviceRoleKey!,
        }).catch(() => {
          // no-op: cache hit should not fail request
        });

        const payload = {
          text: textFromCache,
          finishReason: toSafeText(
            (responseJson as Record<string, unknown>)?.["finishReason"],
          ) || null,
          regenerated: Boolean(
            (responseJson as Record<string, unknown>)?.["regenerated"],
          ),
          modelUsed: toSafeText(cacheRow?.model) || model,
          provider: PROVIDER_NAME,
          model: toSafeText(cacheRow?.model) || model,
          cached: true,
          cache_age_sec: ageSec,
        };

        logEjecucion({
          mode,
          cache_hit: true,
          latency_ms: Date.now() - startedAt,
          provider: PROVIDER_NAME,
          model: payload.model,
          status: "ok_cached",
        });

        return new Response(JSON.stringify(payload), {
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    const first = await llamarGemini({
      apiKey,
      baseUrl,
      model,
      prompt: promptFinal,
    });

    let finalText = first.text;
    let finalReason = first.finishReason;
    let regenerado = false;

    if (debeRegenerar(finalText, finalReason)) {
      regenerado = true;
      const promptRegenerado = promptEsEstructurado
        ? `
La respuesta anterior se corto o quedo incompleta.
Reescribe una version FINAL COMPLETA respetando exactamente el formato solicitado en el prompt original.
No agregues explicaciones fuera del formato pedido.

PROMPT ORIGINAL:
${promptOriginal}

RESPUESTA PARCIAL:
${finalText}
`
        : `
La respuesta anterior se corto o quedo incompleta.
Reescribe una version final COMPLETA con formato de tutor.

PREGUNTA DEL USUARIO:
${mensajeUsuario}

RESPUESTA PARCIAL:
${finalText}

REGLAS:
- Mantener exactamente este formato:
  Diagnostico: ...
  Accion_hoy: ...
  Pasos: 1) ... 2) ... 3) ...
  Control: ...
  Seguimiento_24h: ...
- Tono humano, claro y directo, sin markdown.
- No uses markdown.
`;
      const second = await llamarGemini({
        apiKey,
        baseUrl,
        model,
        prompt: promptRegenerado,
      });
      finalText = second.text;
      finalReason = second.finishReason;
    }

    const responsePayload = {
      text: finalText,
      finishReason: finalReason,
      regenerated: regenerado,
      modelUsed: first.modelUsed ?? model,
      provider: PROVIDER_NAME,
      model,
      cached: false,
      cache_age_sec: 0,
    };

    if (cacheHabilitada && cacheKey && promptHash && contextHash) {
      await guardarCache({
        cacheKey,
        userId,
        mode,
        model,
        promptHash,
        contextHash,
        text: finalText,
        responseJson: responsePayload,
        ttlSeconds,
        supabaseUrl: supabaseUrl!,
        serviceRoleKey: serviceRoleKey!,
      }).catch(() => {
        // no-op: cache write should not fail request
      });
    }

    logEjecucion({
      mode,
      cache_hit: false,
      latency_ms: Date.now() - startedAt,
      provider: PROVIDER_NAME,
      model,
      status: "ok",
    });

    return new Response(JSON.stringify(responsePayload), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    if (esError429(e)) {
      const payload = {
        text: construirMensajeRateLimit(contextoBD),
        finishReason: "RATE_LIMIT",
        degraded: true,
        reason: "gemini_quota",
        provider: PROVIDER_NAME,
        model,
        cached: false,
        cache_age_sec: 0,
      };

      logEjecucion({
        mode,
        cache_hit: false,
        latency_ms: Date.now() - startedAt,
        provider: PROVIDER_NAME,
        model,
        status: "rate_limit",
      });

      return new Response(
        JSON.stringify(payload),
        {
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (e instanceof Response) {
      const status = e.status || 502;
      let details = "";
      try {
        details = await e.text();
      } catch (_) {
        details = "";
      }
      logEjecucion({
        mode,
        cache_hit: false,
        latency_ms: Date.now() - startedAt,
        provider: PROVIDER_NAME,
        model,
        status: "response_error",
        http_status: status,
      });
      return new Response(
        details || JSON.stringify({ error: "Respuesta invalida del proveedor IA" }),
        {
          status,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (e && typeof e === "object" && (e as any).kind === "gemini_http") {
      const err = e as GeminiHttpError;
      logEjecucion({
        mode,
        cache_hit: false,
        latency_ms: Date.now() - startedAt,
        provider: PROVIDER_NAME,
        model: err.model,
        status: "gemini_http_error",
        http_status: err.status,
      });

      return new Response(
        JSON.stringify({
          error: "Error al llamar a Gemini",
          status: err.status,
          statusText: err.statusText,
          provider: PROVIDER_NAME,
          model: err.model,
          details: resumenDetails(err.details),
        }),
        {
          status: 502,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    logEjecucion({
      mode,
      cache_hit: false,
      latency_ms: Date.now() - startedAt,
      provider: PROVIDER_NAME,
      model,
      status: "unexpected_error",
      error: String(e),
    });

    return new Response(
      JSON.stringify({
        error: "Fallo inesperado llamando a Gemini",
        details: String(e),
        provider: PROVIDER_NAME,
        model,
      }),
      {
        status: 502,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
