# Load Test Tutor IA (k6)

Este escenario mide el flujo Tutor con 1000 VUs en `ramp + hold` y valida:

- `p95 < 800ms`
- `error < 1%`
- sin timeout en DB/Edge

## 1) Prerrequisitos

- k6 instalado (`k6 version`)
- URL de Supabase
- API key (`service_role` recomendado para pruebas de carga)
- lista de `user_id` reales para simular usuarios

## 2) Variables (PowerShell)

```powershell
$env:SUPABASE_URL="https://TU-PROYECTO.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="TU_SERVICE_ROLE_KEY"
$env:K6_USER_IDS="uuid1,uuid2,uuid3,uuid4"
```

Opcionales:

```powershell
$env:K6_TARGET_P95_MS="800"
$env:K6_TARGET_ERROR_RATE="0.01"
$env:K6_WITH_EDGE="0"   # 1 para incluir ia_diagnostico
$env:K6_REQUEST_TIMEOUT="5s"
```

## 3) Ejecutar prueba 1000 VUs (ramp + hold)

```powershell
k6 run .\loadtest\tutor_1000vus.js
```

Stages por defecto:

- 2m -> 200 VUs
- 3m -> 500 VUs
- 5m -> 1000 VUs
- 15m hold en 1000
- 2m ramp down

Puedes ajustar por env:

```powershell
$env:K6_STAGE_1="2m"
$env:K6_STAGE_2="3m"
$env:K6_STAGE_3="5m"
$env:K6_STAGE_HOLD="15m"
$env:K6_STAGE_DOWN="2m"
```

## 4) Metricas clave que debes mirar

- `http_req_duration` (global y por endpoint)
- `http_req_failed`
- `timeout_rate`
- `server_error_rate`
- `tutor_flow_duration`
- `tutor_flow_failed`

Si falla umbral en:

- `fn_tutor_velocidad_dashboard`: cuello en `respuesta_usuario`/joins.
- `fn_tutor_prediccion_olvido_materias`: cuello en agregaciones de riesgo.
- `ia_diagnostico`: cuello de Edge/LLM (si `K6_WITH_EDGE=1`).

## 5) Plan de mejora para cumplir objetivos

1. Reducir trabajo duplicado de carga en app (evitar doble `analizarPerfilCompleto`).
2. Mover IA generativa fuera del hot path de pantalla.
3. Consolidar dashboard en una sola RPC/cache por usuario.
4. Asegurar indices compuestos para consultas por `usuario_id + respondida_at`.
5. Repetir k6 tras cada cambio y comparar `p95` + tasa de error.

## 6) Recomendacion de ejecucion

1. Corre una prueba corta (100-200 VUs) para validar credenciales.
2. Luego ejecuta 1000 VUs con hold completo.
3. Si hay errores >1%, revisar logs de Postgres, Edge Functions y limites del plan Supabase.
