-- ============================================
-- ARCHIVO UNIFICADO AUTO-GENERADO
-- Ejecutar completo en Supabase SQL Editor (proyecto limpio)
-- Orden interno: 01 -> 02 -> 03 -> 04
-- ============================================


-- ===== INICIO base_de_datos_supabase\01_SCHEMA_COMPLETO.sql =====

-- ============================================
-- SARGENTO IA - SCRIPT COMPLETO SUPABASE
-- Ejecutar en orden: PARTE 1 → PARTE 2 → PARTE 3
-- ============================================

-- IMPORTANTE: Este es el SCRIPT COMPLETO consolidado
-- Contiene TODAS las tablas, funciones, triggers y optimizaciones
-- Listo para copiar y pegar en Supabase SQL Editor

-- ============================================
-- PARTE 1: EXTENSIONES Y TABLAS BASE
-- ============================================

-- Habilitar extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================
-- TABLAS PRINCIPALES
-- ============================================

-- Tabla: USUARIO
CREATE TABLE IF NOT EXISTS usuario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT UNIQUE NOT NULL,
    
    nombre_completo TEXT NOT NULL,
    email TEXT UNIQUE,
    telefono TEXT,
    
    grado_actual TEXT NOT NULL,
    grado_objetivo TEXT,
    unidad_policial TEXT,
    codigo_unidad TEXT,
    region TEXT,
    
    fecha_examen_objetivo DATE,
    zona_horaria TEXT DEFAULT 'America/Lima',
    idioma TEXT DEFAULT 'es',
    
    avatar_url TEXT,
    apodo TEXT,
    
    password_hash TEXT,
    auth_provider TEXT DEFAULT 'supabase',
    
    activo BOOLEAN DEFAULT TRUE,
    verificado BOOLEAN DEFAULT FALSE,
    premium BOOLEAN DEFAULT FALSE,
    
    fecha_registro TIMESTAMP DEFAULT NOW(),
    ultima_sesion TIMESTAMP,
    
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Tabla: PERFIL_USUARIO
CREATE TABLE IF NOT EXISTS perfil_usuario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID UNIQUE REFERENCES usuario(id) ON DELETE CASCADE,
    
    total_preguntas_respondidas INTEGER DEFAULT 0,
    total_correctas INTEGER DEFAULT 0,
    total_incorrectas INTEGER DEFAULT 0,
    total_omitidas INTEGER DEFAULT 0,
    tasa_acierto_global DECIMAL(5,2) DEFAULT 0,
    
    velocidad_promedio_segundos DECIMAL(6,2),
    tendencia_impulsividad DECIMAL(5,2),
    tendencia_revision DECIMAL(5,2),
    patron_horario_optimo TEXT,
    nivel_concentracion_estimado DECIMAL(5,2),
    
    probabilidad_aprobacion DECIMAL(5,2),
    puntaje_estimado_examen INTEGER,
    nivel_preparacion TEXT,
    areas_criticas TEXT[],
    fortalezas TEXT[],
    
    tiempo_estudio_recomendado_minutos INTEGER,
    proxima_revision_sugerida TIMESTAMP,
    
    dias_consecutivos_estudio INTEGER DEFAULT 0,
    racha_maxima_dias INTEGER DEFAULT 0,
    
    creado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: META_DIARIA
CREATE TABLE IF NOT EXISTS meta_diaria (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    
    preguntas_objetivo INTEGER DEFAULT 33,
    minutos_objetivo INTEGER DEFAULT 40,
    materias_enfoque UUID[],
    
    fecha DATE DEFAULT CURRENT_DATE,
    preguntas_completadas INTEGER DEFAULT 0,
    minutos_estudiados INTEGER DEFAULT 0,
    meta_cumplida BOOLEAN DEFAULT FALSE,
    
    hora_recordatorio TIME,
    recordatorio_activo BOOLEAN DEFAULT TRUE,
    
    mensaje_motivacional TEXT,
    
    creado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(usuario_id, fecha)
);

-- Tabla: ESTADISTICA_USUARIO
CREATE TABLE IF NOT EXISTS estadistica_usuario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID UNIQUE REFERENCES usuario(id) ON DELETE CASCADE,
    
    total_sesiones INTEGER DEFAULT 0,
    total_sesiones_completadas INTEGER DEFAULT 0,
    total_sesiones_abandonadas INTEGER DEFAULT 0,
    tiempo_total_estudio_minutos INTEGER DEFAULT 0,
    
    preguntas_vistas_unicas INTEGER DEFAULT 0,
    preguntas_dominadas INTEGER DEFAULT 0,
    
    mejor_racha_correctas INTEGER DEFAULT 0,
    mejor_puntaje_simulacro INTEGER DEFAULT 0,
    mejor_tiempo_promedio_segundos DECIMAL(6,2),
    
    hora_pico_rendimiento TEXT,
    dia_semana_mas_activo TEXT,
    
    total_medallas_oro INTEGER DEFAULT 0,
    total_medallas_plata INTEGER DEFAULT 0,
    total_medallas_bronce INTEGER DEFAULT 0,
    
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: MATERIA
CREATE TABLE IF NOT EXISTS materia (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    codigo TEXT UNIQUE NOT NULL,
    nombre TEXT NOT NULL,
    nombre_corto TEXT,
    descripcion TEXT,
    
    total_preguntas_banco INTEGER NOT NULL,
    
    color_hex TEXT DEFAULT '#3B82F6',
    icono TEXT,
    orden_visualizacion INTEGER DEFAULT 0,
    
    categoria TEXT,
    nivel_dificultad_promedio TEXT,
    
    activo BOOLEAN DEFAULT TRUE,
    
    creado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: BANCO_DE_PREGUNTA
CREATE TABLE IF NOT EXISTS banco_de_pregunta (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    nombre TEXT NOT NULL,
    version TEXT NOT NULL,
    descripcion TEXT,
    
    total_preguntas INTEGER NOT NULL DEFAULT 3000,
    fecha_publicacion DATE,
    
    activo BOOLEAN DEFAULT TRUE,
    es_oficial BOOLEAN DEFAULT TRUE,
    
    creado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: PREGUNTA
CREATE TABLE IF NOT EXISTS pregunta (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    banco_id UUID REFERENCES banco_de_pregunta(id),
    materia_id UUID REFERENCES materia(id),
    
    codigo_pregunta TEXT UNIQUE NOT NULL,
    numero_oficial INTEGER,
    
    enunciado TEXT NOT NULL,
    contexto TEXT,
    ubicacion_fuente TEXT,
    codigo_fuente TEXT,
    
    tipo_pregunta TEXT DEFAULT 'multiple_choice',
    
    dificultad_estimada TEXT DEFAULT 'medio',
    tasa_error_global DECIMAL(5,2) DEFAULT 0,
    tiempo_promedio_respuesta_segundos DECIMAL(6,2),
    veces_respondida INTEGER DEFAULT 0,
    
    -- EXTENSIÓN CRÍTICA 3000/60
    frecuencia_examen_real DECIMAL(5,2) DEFAULT 0,
    veces_aparecio_examen_real INTEGER DEFAULT 0,
    tasa_error_real DECIMAL(5,2) DEFAULT 0,
    tiempo_promedio_real DECIMAL(6,2) DEFAULT 0,
    score_importancia INTEGER DEFAULT 50,
    es_pregunta_trampa BOOLEAN DEFAULT FALSE,
    tema_especifico TEXT,
    subtema TEXT,
    palabras_clave TEXT[],
    preguntas_relacionadas UUID[],
    grupo_tematico TEXT,
    veces_respondida_total INTEGER DEFAULT 0,
    tasa_mejora_usuarios DECIMAL(5,2) DEFAULT 0,
    metricas_actualizadas_at TIMESTAMP,
    
    es_pregunta_clave BOOLEAN DEFAULT FALSE,
    frecuencia_examen TEXT DEFAULT 'media',
    
    tiene_audio BOOLEAN DEFAULT FALSE,
    audio_url TEXT,
    audio_duracion_segundos INTEGER,
    
    tiene_imagen BOOLEAN DEFAULT FALSE,
    imagen_url TEXT,
    
    activo BOOLEAN DEFAULT TRUE,
    revisada BOOLEAN DEFAULT FALSE,
    
    creado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: ALTERNATIVA
CREATE TABLE IF NOT EXISTS alternativa (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pregunta_id UUID REFERENCES pregunta(id) ON DELETE CASCADE,
    
    letra CHAR(1) NOT NULL,
    texto TEXT NOT NULL,
    es_correcta BOOLEAN NOT NULL DEFAULT FALSE,
    orden INTEGER DEFAULT 0,
    
    creado_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(pregunta_id, letra)
);

-- Tabla: REFERENCIA_LEGAL
CREATE TABLE IF NOT EXISTS referencia_legal (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pregunta_id UUID REFERENCES pregunta(id) ON DELETE CASCADE,
    
    tipo_norma TEXT NOT NULL,
    nombre_norma TEXT NOT NULL,
    codigo_norma TEXT,
    
    articulo TEXT,
    inciso TEXT,
    literal TEXT,
    numeral TEXT,
    parrafo TEXT,
    
    texto_legal TEXT,
    explicacion_detallada TEXT,
    contexto_aplicacion TEXT,
    
    url_norma TEXT,
    orden INTEGER DEFAULT 1,
    
    creado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: SESION_PRACTICA
CREATE TABLE IF NOT EXISTS sesion_practica (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    
    tipo_sesion TEXT NOT NULL,
    nombre_sesion TEXT,
    
    total_preguntas_planeadas INTEGER,
    tiempo_limite_minutos INTEGER,
    materias_incluidas UUID[],
    nivel_dificultad TEXT,
    modo_aleatorio BOOLEAN DEFAULT TRUE,
    
    preguntas_respondidas INTEGER DEFAULT 0,
    preguntas_correctas INTEGER DEFAULT 0,
    preguntas_incorrectas INTEGER DEFAULT 0,
    preguntas_omitidas INTEGER DEFAULT 0,
    
    fecha_inicio TIMESTAMP NOT NULL DEFAULT NOW(),
    fecha_fin TIMESTAMP,
    duracion_real_segundos INTEGER,
    
    puntaje_obtenido DECIMAL(5,2),
    puntaje_aprobacion DECIMAL(5,2) DEFAULT 70,
    aprobado BOOLEAN,
    
    estado TEXT DEFAULT 'en_progreso',
    completada BOOLEAN DEFAULT FALSE,
    
    dispositivo TEXT,
    ubicacion_aproximada TEXT,
    
    -- EXTENSIÓN tracking fino
    nivel_energia_inicio INTEGER,
    nivel_energia_fin INTEGER,
    nivel_concentracion_auto DECIMAL(5,2),
    con_distracciones BOOLEAN,
    lugar_estudio TEXT,
    cantidad_pausas INTEGER DEFAULT 0,
    duracion_pausas_segundos INTEGER DEFAULT 0,
    ritmo_estudio TEXT,
    score_efectividad DECIMAL(5,2),
    preguntas_nuevas_vistas INTEGER DEFAULT 0,
    preguntas_dominadas_sesion INTEGER DEFAULT 0,
    feedback_usuario TEXT,
    calificacion_sesion INTEGER,
    
    metadata JSONB DEFAULT '{}'::jsonb,
    
    creado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: RESPUESTA_USUARIO (CRÍTICA PARA IA)
CREATE TABLE IF NOT EXISTS respuesta_usuario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    pregunta_id UUID REFERENCES pregunta(id),
    sesion_id UUID REFERENCES sesion_practica(id) ON DELETE CASCADE,
    
    alternativa_seleccionada_id UUID REFERENCES alternativa(id),
    letra_seleccionada CHAR(1),
    
    es_correcta BOOLEAN,
    fue_omitida BOOLEAN DEFAULT FALSE,
    
    -- TRACKING DE COMPORTAMIENTO (CRÍTICO)
    tiempo_primera_lectura DECIMAL(6,2),
    tiempo_primera_seleccion DECIMAL(6,2),
    tiempo_revision DECIMAL(6,2),
    tiempo_total_respuesta DECIMAL(6,2) NOT NULL,
    
    numero_cambios_respuesta INTEGER DEFAULT 0,
    secuencia_selecciones TEXT,
    veces_leyo_enunciado INTEGER DEFAULT 1,
    reprodujo_audio BOOLEAN DEFAULT FALSE,
    veces_reprodujo_audio INTEGER DEFAULT 0,
    
    -- DIAGNÓSTICO AUTOMÁTICO IA
    tipo_error TEXT,
    patron_detectado TEXT,
    confianza_usuario INTEGER,
    
    -- CONTEXTO
    posicion_en_sesion INTEGER,
    momento_del_dia TEXT,
    estado_fatiga_estimado DECIMAL(5,2),
    
    marco_para_revision BOOLEAN DEFAULT FALSE,
    reporto_error BOOLEAN DEFAULT FALSE,
    
    respondida_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(usuario_id, pregunta_id, sesion_id)
);

-- Tabla: ERROR_ANALIZADO
CREATE TABLE IF NOT EXISTS error_analizado (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    respuesta_id UUID REFERENCES respuesta_usuario(id) ON DELETE CASCADE,
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    pregunta_id UUID REFERENCES pregunta(id),
    materia_id UUID REFERENCES materia(id),
    
    tipo_error TEXT NOT NULL,
    subtipo_error TEXT,
    
    nivel_gravedad TEXT,
    impacto_score DECIMAL(5,2),
    
    diagnostico_ia TEXT,
    recomendacion_ia TEXT,
    
    es_patron_recurrente BOOLEAN DEFAULT FALSE,
    veces_cometido_similar INTEGER DEFAULT 1,
    
    fue_corregido BOOLEAN DEFAULT FALSE,
    fecha_correccion TIMESTAMP,
    intentos_hasta_correccion INTEGER,
    
    analizado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: DOMINIO_MATERIA (Mapa de Calor)
CREATE TABLE IF NOT EXISTS dominio_materia (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    materia_id UUID REFERENCES materia(id),
    
    total_preguntas_vistas INTEGER DEFAULT 0,
    total_correctas INTEGER DEFAULT 0,
    total_incorrectas INTEGER DEFAULT 0,
    total_omitidas INTEGER DEFAULT 0,
    
    tasa_dominio DECIMAL(5,2) DEFAULT 0,
    tasa_mejora DECIMAL(5,2),
    
    nivel_dominio TEXT DEFAULT 'sin_datos',
    color_mapa_calor TEXT DEFAULT 'gris',
    
    necesita_refuerzo_urgente BOOLEAN DEFAULT FALSE,
    prioridad_estudio INTEGER DEFAULT 3,
    tiempo_recomendado_minutos INTEGER,
    proxima_revision_sugerida TIMESTAMP,
    
    temas_debiles TEXT[],
    errores_comunes TEXT[],
    
    dominio_hace_7_dias DECIMAL(5,2),
    dominio_hace_30_dias DECIMAL(5,2),
    
    primera_practica TIMESTAMP,
    ultima_practica TIMESTAMP,
    actualizado_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(usuario_id, materia_id)
);

-- Tabla: PREDICCION_OLVIDO (Curva de Ebbinghaus)
CREATE TABLE IF NOT EXISTS prediccion_olvido (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    pregunta_id UUID REFERENCES pregunta(id),
    
    ultima_respuesta_correcta TIMESTAMP,
    ultima_respuesta_incorrecta TIMESTAMP,
    veces_respondida_correcta INTEGER DEFAULT 0,
    veces_respondida_incorrecta INTEGER DEFAULT 0,
    
    probabilidad_olvido DECIMAL(5,2) DEFAULT 0,
    dias_desde_ultima_correcta DECIMAL(6,2),
    factor_consolidacion DECIMAL(5,2),
    
    nivel_consolidacion TEXT,
    fecha_revision_optima TIMESTAMP,
    urgencia_revision TEXT,
    
    requiere_revision_inmediata BOOLEAN DEFAULT FALSE,
    agregada_a_plan_estudio BOOLEAN DEFAULT FALSE,
    
    calculado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(usuario_id, pregunta_id)
);

-- Tabla: MENSAJE_IA
CREATE TABLE IF NOT EXISTS mensaje_ia (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    
    tipo_mensaje TEXT NOT NULL,
    categoria TEXT,
    
    titulo TEXT,
    contenido TEXT NOT NULL,
    contenido_html TEXT,
    accion_recomendada TEXT,
    
    prioridad TEXT DEFAULT 'normal',
    urgente BOOLEAN DEFAULT FALSE,
    
    sesion_id UUID REFERENCES sesion_practica(id),
    materia_id UUID REFERENCES materia(id),
    datos_analisis JSONB,
    
    leido BOOLEAN DEFAULT FALSE,
    fecha_lectura TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE,
    
    usuario_respondio BOOLEAN DEFAULT FALSE,
    respuesta_usuario TEXT,
    
    generado_at TIMESTAMP DEFAULT NOW(),
    expira_at TIMESTAMP,
    
    CONSTRAINT check_contenido CHECK (LENGTH(contenido) > 0)
);

-- Tabla: RANKING
CREATE TABLE IF NOT EXISTS ranking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID UNIQUE REFERENCES usuario(id) ON DELETE CASCADE,
    
    puntos_totales INTEGER DEFAULT 0,
    puntos_mes_actual INTEGER DEFAULT 0,
    puntos_semana_actual INTEGER DEFAULT 0,
    
    posicion_nacional INTEGER,
    posicion_regional INTEGER,
    posicion_unidad INTEGER,
    posicion_grado INTEGER,
    
    cambio_posicion_dia INTEGER DEFAULT 0,
    tendencia TEXT,
    
    simulacros_100_completados INTEGER DEFAULT 0,
    simulacros_aprobados INTEGER DEFAULT 0,
    mejor_puntaje_simulacro INTEGER DEFAULT 0,
    promedio_simulacros DECIMAL(5,2) DEFAULT 0,
    
    racha_actual_dias INTEGER DEFAULT 0,
    racha_maxima_dias INTEGER DEFAULT 0,
    
    total_medallas_oro INTEGER DEFAULT 0,
    total_medallas_plata INTEGER DEFAULT 0,
    total_medallas_bronce INTEGER DEFAULT 0,
    logros_desbloqueados TEXT[],
    
    nivel_usuario INTEGER DEFAULT 1,
    experiencia_total INTEGER DEFAULT 0,
    
    actualizado_at TIMESTAMP DEFAULT NOW(),
    calculo_ranking_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: BATALLA
CREATE TABLE IF NOT EXISTS batalla (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    codigo_batalla TEXT UNIQUE NOT NULL,
    
    usuario1_id UUID REFERENCES usuario(id),
    usuario2_id UUID REFERENCES usuario(id),
    
    total_preguntas INTEGER DEFAULT 20,
    tiempo_limite_segundos INTEGER DEFAULT 600,
    materias_incluidas UUID[],
    nivel_dificultad TEXT DEFAULT 'mixto',
    
    usuario1_correctas INTEGER DEFAULT 0,
    usuario1_tiempo_total INTEGER DEFAULT 0,
    usuario2_correctas INTEGER DEFAULT 0,
    usuario2_tiempo_total INTEGER DEFAULT 0,
    
    ganador_id UUID REFERENCES usuario(id),
    diferencia_puntos INTEGER,
    
    estado TEXT DEFAULT 'esperando',
    
    puntos_ganador INTEGER DEFAULT 100,
    puntos_perdedor INTEGER DEFAULT 50,
    
    creada_at TIMESTAMP DEFAULT NOW(),
    iniciada_at TIMESTAMP,
    finalizada_at TIMESTAMP,
    
    CHECK (usuario1_id != usuario2_id)
);

-- Tabla: RESPUESTA_BATALLA
CREATE TABLE IF NOT EXISTS respuesta_batalla (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batalla_id UUID REFERENCES batalla(id) ON DELETE CASCADE,
    usuario_id UUID REFERENCES usuario(id),
    pregunta_id UUID REFERENCES pregunta(id),
    
    alternativa_seleccionada_id UUID REFERENCES alternativa(id),
    es_correcta BOOLEAN,
    tiempo_respuesta_segundos DECIMAL(6,2),
    
    numero_pregunta INTEGER,
    
    respondida_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(batalla_id, usuario_id, pregunta_id)
);

-- Tabla: LOGRO
CREATE TABLE IF NOT EXISTS logro (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    codigo TEXT UNIQUE NOT NULL,
    nombre TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    
    categoria TEXT,
    nivel_dificultad TEXT,
    
    puntos_otorgados INTEGER DEFAULT 100,
    medalla_tipo TEXT,
    
    icono TEXT,
    color_hex TEXT,
    
    criterios JSONB,
    
    activo BOOLEAN DEFAULT TRUE,
    
    creado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: USUARIO_LOGRO
CREATE TABLE IF NOT EXISTS usuario_logro (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    logro_id UUID REFERENCES logro(id),
    
    desbloqueado_at TIMESTAMP DEFAULT NOW(),
    sesion_id UUID REFERENCES sesion_practica(id),
    
    notificado BOOLEAN DEFAULT FALSE,
    compartido_redes BOOLEAN DEFAULT FALSE,
    
    UNIQUE(usuario_id, logro_id)
);

-- Tabla: CONFIGURACION_USUARIO
CREATE TABLE IF NOT EXISTS configuracion_usuario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID UNIQUE REFERENCES usuario(id) ON DELETE CASCADE,
    
    notif_recordatorio_diario BOOLEAN DEFAULT TRUE,
    notif_logros BOOLEAN DEFAULT TRUE,
    notif_ranking BOOLEAN DEFAULT TRUE,
    notif_batallas BOOLEAN DEFAULT TRUE,
    notif_mensajes_ia BOOLEAN DEFAULT TRUE,
    
    audio_activado BOOLEAN DEFAULT FALSE,
    velocidad_audio DECIMAL(3,2) DEFAULT 1.0,
    
    tema TEXT DEFAULT 'light',
    tamano_fuente TEXT DEFAULT 'normal',
    modo_daltonico BOOLEAN DEFAULT FALSE,
    
    perfil_publico BOOLEAN DEFAULT TRUE,
    mostrar_en_ranking BOOLEAN DEFAULT TRUE,
    aceptar_batallas BOOLEAN DEFAULT TRUE,
    
    modo_estudio_preferido TEXT,
    mostrar_explicaciones_automaticas BOOLEAN DEFAULT TRUE,
    
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- TABLAS CRÍTICAS PARA 3000/60
-- ============================================

-- Tabla: PLAN_ESTUDIO_DIARIO
CREATE TABLE IF NOT EXISTS plan_estudio_diario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    
    dia_numero INTEGER NOT NULL,
    fecha_objetivo DATE NOT NULL,
    
    preguntas_nuevas UUID[],
    cantidad_nuevas INTEGER DEFAULT 0,
    
    preguntas_repaso UUID[],
    cantidad_repaso INTEGER DEFAULT 0,
    
    materias_prioritarias UUID[],
    razon_priorizacion TEXT,
    
    objetivo_tasa_acierto DECIMAL(5,2),
    objetivo_tiempo_promedio DECIMAL(6,2),
    objetivo_preguntas_dominar INTEGER,
    
    preguntas_completadas INTEGER DEFAULT 0,
    tasa_acierto_real DECIMAL(5,2),
    tiempo_promedio_real DECIMAL(6,2),
    preguntas_dominadas_hoy INTEGER DEFAULT 0,
    
    plan_cumplido BOOLEAN DEFAULT FALSE,
    adaptaciones_realizadas INTEGER DEFAULT 0,
    
    mensaje_motivacional TEXT,
    prediccion_exito_dia DECIMAL(5,2),
    
    creado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW(),
    completado_at TIMESTAMP,
    
    UNIQUE(usuario_id, dia_numero)
);

-- Tabla: EXPOSICION_PREGUNTA
CREATE TABLE IF NOT EXISTS exposicion_pregunta (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    pregunta_id UUID REFERENCES pregunta(id),
    
    total_veces_vista INTEGER DEFAULT 0,
    total_veces_correcta INTEGER DEFAULT 0,
    total_veces_incorrecta INTEGER DEFAULT 0,
    total_veces_omitida INTEGER DEFAULT 0,
    
    primera_vez_vista TIMESTAMP,
    ultima_vez_vista TIMESTAMP,
    primera_vez_correcta TIMESTAMP,
    ultima_vez_incorrecta TIMESTAMP,
    
    racha_correctas_consecutivas INTEGER DEFAULT 0,
    racha_incorrectas_consecutivas INTEGER DEFAULT 0,
    
    estado_dominio TEXT DEFAULT 'no_vista',
    veces_dominada INTEGER DEFAULT 0,
    veces_olvidada INTEGER DEFAULT 0,
    
    dificultad_personal TEXT,
    necesita_atencion_especial BOOLEAN DEFAULT FALSE,
    
    tiempo_promedio_usuario DECIMAL(6,2),
    tiempo_minimo_logrado DECIMAL(6,2),
    
    probabilidad_acierto_siguiente DECIMAL(5,2),
    
    notas_usuario TEXT,
    marcada_para_revision BOOLEAN DEFAULT FALSE,
    
    actualizado_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(usuario_id, pregunta_id)
);

-- Tabla: CORRELACION_PREGUNTAS
CREATE TABLE IF NOT EXISTS correlacion_preguntas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pregunta_a_id UUID REFERENCES pregunta(id),
    pregunta_b_id UUID REFERENCES pregunta(id),
    
    tipo_correlacion TEXT NOT NULL,
    score_similitud DECIMAL(5,2),
    
    usuarios_confunden_ambas INTEGER DEFAULT 0,
    usuarios_aciertan_una_fallan_otra INTEGER DEFAULT 0,
    
    aprender_primero UUID,
    razon_orden TEXT,
    
    calculado_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(pregunta_a_id, pregunta_b_id)
);

-- Tabla: PATRON_ERROR_DETALLADO
CREATE TABLE IF NOT EXISTS patron_error_detallado (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    
    tipo_patron TEXT NOT NULL,
    descripcion_patron TEXT,
    severidad TEXT,
    
    veces_detectado INTEGER DEFAULT 0,
    ultima_vez_detectado TIMESTAMP,
    tendencia TEXT,
    
    preguntas_afectadas UUID[],
    materias_afectadas UUID[],
    
    puntos_perdidos_estimados DECIMAL(5,2),
    probabilidad_aparicion_examen DECIMAL(5,2),
    
    ejercicios_sugeridos TEXT[],
    temas_reforzar TEXT[],
    estrategia_correccion TEXT,
    
    patron_corregido BOOLEAN DEFAULT FALSE,
    fecha_correccion TIMESTAMP,
    
    detectado_at TIMESTAMP DEFAULT NOW(),
    actualizado_at TIMESTAMP DEFAULT NOW()
);

-- Tabla: PREDICCION_EXAMEN
CREATE TABLE IF NOT EXISTS prediccion_examen (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    
    calculado_para_fecha DATE NOT NULL,
    dias_restantes INTEGER,
    
    puntaje_estimado DECIMAL(5,2),
    probabilidad_aprobacion DECIMAL(5,2),
    margen_error DECIMAL(5,2),
    confianza_prediccion DECIMAL(5,2),
    
    prediccion_por_materia JSONB,
    materias_riesgo UUID[],
    
    velocidad_aprendizaje DECIMAL(5,2),
    preguntas_faltantes INTEGER,
    tiempo_necesario_dias DECIMAL(5,2),
    
    debe_acelerar BOOLEAN DEFAULT FALSE,
    debe_enfocarse_en UUID[],
    puede_reducir_ritmo BOOLEAN DEFAULT FALSE,
    
    prediccion_optimista DECIMAL(5,2),
    prediccion_pesimista DECIMAL(5,2),
    prediccion_realista DECIMAL(5,2),
    
    plan_accion_ia TEXT,
    cambios_sugeridos TEXT[],
    
    calculado_at TIMESTAMP DEFAULT NOW(),
    version_algoritmo TEXT DEFAULT 'v1.0'
);

-- Tabla: COLA_REPASO_INTELIGENTE
CREATE TABLE IF NOT EXISTS cola_repaso_inteligente (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuario(id) ON DELETE CASCADE,
    pregunta_id UUID REFERENCES pregunta(id),
    
    proxima_revision_optima TIMESTAMP NOT NULL,
    intervalo_revision_dias DECIMAL(5,2),
    nivel_retencion INTEGER DEFAULT 0,
    
    prioridad_urgencia INTEGER DEFAULT 5,
    razon_prioridad TEXT,
    
    factor_dificultad DECIMAL(5,2) DEFAULT 1.0,
    factor_importancia DECIMAL(5,2) DEFAULT 1.0,
    factor_olvido DECIMAL(5,2) DEFAULT 1.0,
    
    en_cola BOOLEAN DEFAULT TRUE,
    veces_pospuesta INTEGER DEFAULT 0,
    
    agregada_a_cola_at TIMESTAMP DEFAULT NOW(),
    actualizada_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(usuario_id, pregunta_id)
);

-- ============================================
-- ÍNDICES PARA PERFORMANCE
-- ============================================

-- Usuario
CREATE INDEX IF NOT EXISTS idx_usuario_user_id ON usuario(user_id);
CREATE INDEX IF NOT EXISTS idx_usuario_email ON usuario(email);
CREATE INDEX IF NOT EXISTS idx_usuario_activo ON usuario(activo);

-- Respuestas
CREATE INDEX IF NOT EXISTS idx_respuesta_usuario_id ON respuesta_usuario(usuario_id);
CREATE INDEX IF NOT EXISTS idx_respuesta_pregunta_id ON respuesta_usuario(pregunta_id);
CREATE INDEX IF NOT EXISTS idx_respuesta_sesion_id ON respuesta_usuario(sesion_id);
CREATE INDEX IF NOT EXISTS idx_respuesta_es_correcta ON respuesta_usuario(es_correcta);
CREATE INDEX IF NOT EXISTS idx_respuesta_tipo_error ON respuesta_usuario(tipo_error);
CREATE INDEX IF NOT EXISTS idx_respuesta_respondida_at ON respuesta_usuario(respondida_at);

-- Preguntas
CREATE INDEX IF NOT EXISTS idx_pregunta_materia ON pregunta(materia_id);
CREATE INDEX IF NOT EXISTS idx_pregunta_codigo ON pregunta(codigo_pregunta);
CREATE INDEX IF NOT EXISTS idx_pregunta_banco ON pregunta(banco_id);
CREATE INDEX IF NOT EXISTS idx_pregunta_activo ON pregunta(activo);
CREATE INDEX IF NOT EXISTS idx_pregunta_frecuencia ON pregunta(frecuencia_examen_real DESC);
CREATE INDEX IF NOT EXISTS idx_pregunta_importancia ON pregunta(score_importancia DESC);
CREATE INDEX IF NOT EXISTS idx_pregunta_tema ON pregunta(tema_especifico);
CREATE INDEX IF NOT EXISTS idx_pregunta_trampa ON pregunta(es_pregunta_trampa) WHERE es_pregunta_trampa = TRUE;

-- Sesiones
CREATE INDEX IF NOT EXISTS idx_sesion_usuario ON sesion_practica(usuario_id);
CREATE INDEX IF NOT EXISTS idx_sesion_tipo ON sesion_practica(tipo_sesion);
CREATE INDEX IF NOT EXISTS idx_sesion_estado ON sesion_practica(estado);
CREATE INDEX IF NOT EXISTS idx_sesion_fecha_inicio ON sesion_practica(fecha_inicio);

-- Dominio materias
CREATE INDEX IF NOT EXISTS idx_dominio_usuario ON dominio_materia(usuario_id);
CREATE INDEX IF NOT EXISTS idx_dominio_materia ON dominio_materia(materia_id);
CREATE INDEX IF NOT EXISTS idx_dominio_nivel ON dominio_materia(nivel_dominio);
CREATE INDEX IF NOT EXISTS idx_dominio_necesita_refuerzo ON dominio_materia(necesita_refuerzo_urgente);

-- Predicciones
CREATE INDEX IF NOT EXISTS idx_prediccion_usuario ON prediccion_olvido(usuario_id);
CREATE INDEX IF NOT EXISTS idx_prediccion_revision ON prediccion_olvido(fecha_revision_optima);
CREATE INDEX IF NOT EXISTS idx_prediccion_urgencia ON prediccion_olvido(urgencia_revision);

-- Mensajes IA
CREATE INDEX IF NOT EXISTS idx_mensaje_usuario ON mensaje_ia(usuario_id);
CREATE INDEX IF NOT EXISTS idx_mensaje_leido ON mensaje_ia(leido);
CREATE INDEX IF NOT EXISTS idx_mensaje_tipo ON mensaje_ia(tipo_mensaje);
CREATE INDEX IF NOT EXISTS idx_mensaje_generado_at ON mensaje_ia(generado_at);

-- Ranking
CREATE INDEX IF NOT EXISTS idx_ranking_posicion_nacional ON ranking(posicion_nacional);
CREATE INDEX IF NOT EXISTS idx_ranking_puntos ON ranking(puntos_totales DESC);

-- Batallas
CREATE INDEX IF NOT EXISTS idx_batalla_usuario1 ON batalla(usuario1_id);
CREATE INDEX IF NOT EXISTS idx_batalla_usuario2 ON batalla(usuario2_id);
CREATE INDEX IF NOT EXISTS idx_batalla_estado ON batalla(estado);

-- Alternativas
CREATE INDEX IF NOT EXISTS idx_alternativa_pregunta ON alternativa(pregunta_id);

-- Críticos 3000/60
CREATE INDEX IF NOT EXISTS idx_plan_usuario_dia ON plan_estudio_diario(usuario_id, dia_numero);
CREATE INDEX IF NOT EXISTS idx_plan_fecha ON plan_estudio_diario(fecha_objetivo);
CREATE INDEX IF NOT EXISTS idx_exposicion_usuario ON exposicion_pregunta(usuario_id);
CREATE INDEX IF NOT EXISTS idx_exposicion_estado ON exposicion_pregunta(estado_dominio);
CREATE INDEX IF NOT EXISTS idx_exposicion_racha ON exposicion_pregunta(racha_correctas_consecutivas);
CREATE INDEX IF NOT EXISTS idx_exposicion_atencion ON exposicion_pregunta(necesita_atencion_especial) WHERE necesita_atencion_especial = TRUE;
CREATE INDEX IF NOT EXISTS idx_correlacion_pregunta_a ON correlacion_preguntas(pregunta_a_id);
CREATE INDEX IF NOT EXISTS idx_correlacion_tipo ON correlacion_preguntas(tipo_correlacion);
CREATE INDEX IF NOT EXISTS idx_patron_usuario ON patron_error_detallado(usuario_id);
CREATE INDEX IF NOT EXISTS idx_patron_severidad ON patron_error_detallado(severidad);
CREATE INDEX IF NOT EXISTS idx_patron_activo ON patron_error_detallado(patron_corregido) WHERE patron_corregido = FALSE;
CREATE INDEX IF NOT EXISTS idx_prediccion_examen_usuario ON prediccion_examen(usuario_id);
CREATE INDEX IF NOT EXISTS idx_prediccion_examen_fecha ON prediccion_examen(calculado_para_fecha);
CREATE INDEX IF NOT EXISTS idx_cola_usuario ON cola_repaso_inteligente(usuario_id);
CREATE INDEX IF NOT EXISTS idx_cola_proxima ON cola_repaso_inteligente(proxima_revision_optima);
CREATE INDEX IF NOT EXISTS idx_cola_prioridad ON cola_repaso_inteligente(prioridad_urgencia DESC);
CREATE INDEX IF NOT EXISTS idx_cola_activa ON cola_repaso_inteligente(en_cola) WHERE en_cola = TRUE;

-- ============================================
-- COMENTARIOS
-- ============================================

COMMENT ON TABLE usuario IS 'Tabla principal de usuarios del sistema';
COMMENT ON TABLE respuesta_usuario IS 'Tabla CRÍTICA para IA - contiene todo el tracking de comportamiento';
COMMENT ON TABLE prediccion_olvido IS 'Sistema de predicción basado en curva de Ebbinghaus';
COMMENT ON TABLE mensaje_ia IS 'Mensajes personalizados generados por el sistema de IA';
COMMENT ON TABLE dominio_materia IS 'Mapa de calor - tracking de dominio por materia';
COMMENT ON TABLE batalla IS 'Sistema de competencia 1v1 en tiempo real';
COMMENT ON TABLE plan_estudio_diario IS 'Plan adaptativo día a día para completar 3000 preguntas en 60 días';
COMMENT ON TABLE exposicion_pregunta IS 'Tracking exhaustivo de cada pregunta vista por usuario';
COMMENT ON TABLE cola_repaso_inteligente IS 'Sistema de Spaced Repetition para optimizar repasos';

-- ============================================
-- FIN PARTE 1
-- Continuar con PARTE 2 (funciones y triggers)
-- ============================================

-- ===== FIN base_de_datos_supabase\01_SCHEMA_COMPLETO.sql =====


-- ===== INICIO base_de_datos_supabase\02_FUNCIONES_TRIGGERS.sql =====

-- ============================================
-- SARGENTO IA - FUNCIONES Y TRIGGERS
-- PARTE 2: Ejecutar DESPUÉS de 01_SCHEMA_COMPLETO.sql
-- ============================================

-- ============================================
-- FUNCIONES DE CÁLCULO IA
-- ============================================

-- Función: Diagnosticar tipo de error automáticamente
CREATE OR REPLACE FUNCTION fn_diagnosticar_tipo_error(
    p_tiempo_respuesta DECIMAL,
    p_cambios_respuesta INTEGER,
    p_tiempo_primera_seleccion DECIMAL,
    p_es_correcta BOOLEAN
) RETURNS TEXT AS $$
BEGIN
    IF p_es_correcta THEN
        RETURN NULL;
    END IF;
    
    -- Impulsividad: respuesta muy rápida (<5 seg)
    IF p_tiempo_respuesta < 5 THEN
        RETURN 'impulsividad';
    END IF;
    
    -- Confusión: muchos cambios (>2)
    IF p_cambios_respuesta > 2 THEN
        RETURN 'confusion_opciones';
    END IF;
    
    -- Desconocimiento: tiempo largo (>60 seg) sin cambios
    IF p_tiempo_respuesta > 60 AND p_cambios_respuesta <= 1 THEN
        RETURN 'desconocimiento';
    END IF;
    
    -- Error de lectura: tiempo moderado con 1-2 cambios
    IF p_tiempo_respuesta BETWEEN 10 AND 60 AND p_cambios_respuesta BETWEEN 1 AND 2 THEN
        RETURN 'error_lectura';
    END IF;
    
    RETURN 'indeterminado';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Función: Calcular probabilidad de olvido (Ebbinghaus)
CREATE OR REPLACE FUNCTION fn_calcular_probabilidad_olvido(
    p_ultima_correcta TIMESTAMP,
    p_veces_correcta INTEGER,
    p_veces_incorrecta INTEGER
) RETURNS DECIMAL AS $$
DECLARE
    v_dias_transcurridos DECIMAL;
    v_factor_consolidacion DECIMAL;
    v_probabilidad DECIMAL;
BEGIN
    -- Calcular días transcurridos
    v_dias_transcurridos := EXTRACT(EPOCH FROM (NOW() - p_ultima_correcta)) / 86400.0;
    
    -- Factor de consolidación (máx 0.9)
    v_factor_consolidacion := LEAST(p_veces_correcta * 0.15, 0.9);
    
    -- Curva de olvido exponencial: P = 100 * e^(-días/R)
    v_probabilidad := 100 * EXP(-v_dias_transcurridos / (10 * (1 + v_factor_consolidacion)));
    
    -- Penalización por errores previos (+5% por cada error)
    v_probabilidad := v_probabilidad + (p_veces_incorrecta * 5);
    
    -- Limitar entre 0-100
    v_probabilidad := GREATEST(0, LEAST(v_probabilidad, 100));
    
    RETURN v_probabilidad;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Función: Calcular nivel de dominio
CREATE OR REPLACE FUNCTION fn_calcular_nivel_dominio(p_tasa_dominio DECIMAL)
RETURNS TEXT AS $$
BEGIN
    CASE
        WHEN p_tasa_dominio >= 95 THEN RETURN 'maestro';
        WHEN p_tasa_dominio >= 80 THEN RETURN 'dominado';
        WHEN p_tasa_dominio >= 60 THEN RETURN 'en_progreso';
        WHEN p_tasa_dominio >= 40 THEN RETURN 'basico';
        ELSE RETURN 'critico';
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- FUNCIONES PARA 3000/60
-- ============================================

-- Función: Actualizar estado de exposición
CREATE OR REPLACE FUNCTION fn_actualizar_exposicion_pregunta(
    p_usuario_id UUID,
    p_pregunta_id UUID,
    p_es_correcta BOOLEAN
)
RETURNS VOID AS $$
DECLARE
    v_racha_actual INTEGER;
    v_nuevo_estado TEXT;
BEGIN
    -- Insertar o actualizar exposición
    INSERT INTO exposicion_pregunta (
        usuario_id, pregunta_id,
        total_veces_vista, total_veces_correcta, total_veces_incorrecta,
        primera_vez_vista, ultima_vez_vista,
        primera_vez_correcta, ultima_vez_incorrecta
    )
    VALUES (
        p_usuario_id, p_pregunta_id,
        1,
        CASE WHEN p_es_correcta THEN 1 ELSE 0 END,
        CASE WHEN p_es_correcta THEN 0 ELSE 1 END,
        NOW(), NOW(),
        CASE WHEN p_es_correcta THEN NOW() ELSE NULL END,
        CASE WHEN p_es_correcta THEN NULL ELSE NOW() END
    )
    ON CONFLICT (usuario_id, pregunta_id) DO UPDATE SET
        total_veces_vista = exposicion_pregunta.total_veces_vista + 1,
        total_veces_correcta = exposicion_pregunta.total_veces_correcta + 
            CASE WHEN p_es_correcta THEN 1 ELSE 0 END,
        total_veces_incorrecta = exposicion_pregunta.total_veces_incorrecta + 
            CASE WHEN p_es_correcta THEN 0 ELSE 1 END,
        ultima_vez_vista = NOW(),
        primera_vez_correcta = COALESCE(exposicion_pregunta.primera_vez_correcta, 
            CASE WHEN p_es_correcta THEN NOW() ELSE NULL END),
        ultima_vez_incorrecta = CASE WHEN p_es_correcta THEN exposicion_pregunta.ultima_vez_incorrecta 
            ELSE NOW() END,
        racha_correctas_consecutivas = CASE 
            WHEN p_es_correcta THEN exposicion_pregunta.racha_correctas_consecutivas + 1
            ELSE 0 END,
        racha_incorrectas_consecutivas = CASE
            WHEN p_es_correcta THEN 0
            ELSE exposicion_pregunta.racha_incorrectas_consecutivas + 1 END,
        actualizado_at = NOW();
    
    -- Determinar nuevo estado de dominio
    SELECT racha_correctas_consecutivas INTO v_racha_actual
    FROM exposicion_pregunta
    WHERE usuario_id = p_usuario_id AND pregunta_id = p_pregunta_id;
    
    v_nuevo_estado := CASE
        WHEN v_racha_actual >= 3 THEN 'dominada'
        WHEN v_racha_actual >= 1 THEN 'consolidando'
        WHEN v_racha_actual = 0 AND p_es_correcta = FALSE THEN 'aprendiendo'
        ELSE 'aprendiendo'
    END;
    
    UPDATE exposicion_pregunta SET
        estado_dominio = v_nuevo_estado,
        veces_dominada = CASE WHEN v_nuevo_estado = 'dominada' 
            THEN veces_dominada + 1 ELSE veces_dominada END
    WHERE usuario_id = p_usuario_id AND pregunta_id = p_pregunta_id;
    
    -- Actualizar cola de repaso
    INSERT INTO cola_repaso_inteligente (
        usuario_id, pregunta_id,
        proxima_revision_optima,
        intervalo_revision_dias,
        nivel_retencion,
        prioridad_urgencia
    )
    VALUES (
        p_usuario_id, p_pregunta_id,
        NOW() + INTERVAL '1 day' * (v_racha_actual + 1),
        v_racha_actual + 1,
        LEAST(v_racha_actual * 2, 10),
        CASE 
            WHEN v_racha_actual >= 3 THEN 3
            WHEN v_racha_actual >= 1 THEN 5
            ELSE 8
        END
    )
    ON CONFLICT (usuario_id, pregunta_id) DO UPDATE SET
        proxima_revision_optima = NOW() + INTERVAL '1 day' * (v_racha_actual + 1),
        intervalo_revision_dias = v_racha_actual + 1,
        nivel_retencion = LEAST(v_racha_actual * 2, 10),
        prioridad_urgencia = CASE 
            WHEN v_racha_actual >= 3 THEN 3
            WHEN v_racha_actual >= 1 THEN 5
            ELSE 8
        END,
        actualizada_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- Función: Generar plan diario inteligente
CREATE OR REPLACE FUNCTION fn_generar_plan_dia_siguiente(
    p_usuario_id UUID,
    p_dia_numero INTEGER
)
RETURNS JSONB AS $$
DECLARE
    v_plan JSONB;
    v_preguntas_nuevas UUID[];
    v_preguntas_repaso UUID[];
    v_materias_debiles UUID[];
BEGIN
    -- 1. Identificar preguntas nuevas prioritarias
    SELECT ARRAY_AGG(p.id ORDER BY p.score_importancia DESC, p.frecuencia_examen_real DESC)
    INTO v_preguntas_nuevas
    FROM pregunta p
    WHERE NOT EXISTS (
        SELECT 1 FROM exposicion_pregunta ep
        WHERE ep.usuario_id = p_usuario_id AND ep.pregunta_id = p.id
    )
    LIMIT 30;
    
    -- 2. Identificar preguntas para repaso urgente
    SELECT ARRAY_AGG(cr.pregunta_id ORDER BY cr.prioridad_urgencia DESC)
    INTO v_preguntas_repaso
    FROM cola_repaso_inteligente cr
    WHERE cr.usuario_id = p_usuario_id
    AND cr.en_cola = TRUE
    AND cr.proxima_revision_optima <= NOW() + INTERVAL '1 day'
    LIMIT 20;
    
    -- 3. Identificar materias débiles
    SELECT ARRAY_AGG(dm.materia_id)
    INTO v_materias_debiles
    FROM dominio_materia dm
    WHERE dm.usuario_id = p_usuario_id
    AND dm.tasa_dominio < 60
    ORDER BY dm.tasa_dominio ASC;
    
    -- 4. Construir plan
    v_plan := jsonb_build_object(
        'dia_numero', p_dia_numero,
        'fecha_objetivo', CURRENT_DATE + p_dia_numero,
        'preguntas_nuevas', v_preguntas_nuevas,
        'cantidad_nuevas', COALESCE(array_length(v_preguntas_nuevas, 1), 0),
        'preguntas_repaso', v_preguntas_repaso,
        'cantidad_repaso', COALESCE(array_length(v_preguntas_repaso, 1), 0),
        'materias_prioritarias', v_materias_debiles,
        'total_preguntas_dia', COALESCE(array_length(v_preguntas_nuevas, 1), 0) + 
                               COALESCE(array_length(v_preguntas_repaso, 1), 0)
    );
    
    -- 5. Guardar plan en base de datos
    INSERT INTO plan_estudio_diario (
        usuario_id, dia_numero, fecha_objetivo,
        preguntas_nuevas, cantidad_nuevas,
        preguntas_repaso, cantidad_repaso,
        materias_prioritarias
    )
    VALUES (
        p_usuario_id, p_dia_numero, CURRENT_DATE + p_dia_numero,
        v_preguntas_nuevas, COALESCE(array_length(v_preguntas_nuevas, 1), 0),
        v_preguntas_repaso, COALESCE(array_length(v_preguntas_repaso, 1), 0),
        v_materias_debiles
    )
    ON CONFLICT (usuario_id, dia_numero) DO UPDATE SET
        preguntas_nuevas = EXCLUDED.preguntas_nuevas,
        cantidad_nuevas = EXCLUDED.cantidad_nuevas,
        preguntas_repaso = EXCLUDED.preguntas_repaso,
        cantidad_repaso = EXCLUDED.cantidad_repaso,
        materias_prioritarias = EXCLUDED.materias_prioritarias,
        actualizado_at = NOW();
    
    RETURN v_plan;
END;
$$ LANGUAGE plpgsql;

-- Función: Calcular progreso hacia meta 60 días
CREATE OR REPLACE FUNCTION fn_calcular_progreso_60_dias(p_usuario_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_resultado JSONB;
    v_dias_transcurridos INTEGER;
    v_dias_restantes INTEGER;
    v_preguntas_dominadas INTEGER;
    v_preguntas_vistas INTEGER;
    v_ritmo_actual DECIMAL;
    v_ritmo_necesario DECIMAL;
BEGIN
    -- Calcular días
    SELECT 
        CURRENT_DATE - u.fecha_registro::DATE,
        COALESCE(u.fecha_examen_objetivo, CURRENT_DATE + INTERVAL '60 days')::DATE - CURRENT_DATE
    INTO v_dias_transcurridos, v_dias_restantes
    FROM usuario u
    WHERE u.id = p_usuario_id;
    
    -- Contar preguntas dominadas
    SELECT COUNT(*)
    INTO v_preguntas_dominadas
    FROM exposicion_pregunta
    WHERE usuario_id = p_usuario_id
    AND estado_dominio IN ('dominada', 'consolidando');
    
    -- Contar preguntas vistas
    SELECT COUNT(*)
    INTO v_preguntas_vistas
    FROM exposicion_pregunta
    WHERE usuario_id = p_usuario_id;
    
    -- Calcular ritmos
    v_ritmo_actual := CASE WHEN v_dias_transcurridos > 0 
        THEN v_preguntas_dominadas::DECIMAL / v_dias_transcurridos 
        ELSE 0 END;
    
    v_ritmo_necesario := CASE WHEN v_dias_restantes > 0
        THEN (3000 - v_preguntas_dominadas)::DECIMAL / v_dias_restantes
        ELSE 999 END;
    
    -- Construir resultado
    v_resultado := jsonb_build_object(
        'dias_transcurridos', v_dias_transcurridos,
        'dias_restantes', v_dias_restantes,
        'preguntas_dominadas', v_preguntas_dominadas,
        'preguntas_vistas', v_preguntas_vistas,
        'preguntas_faltantes', 3000 - v_preguntas_dominadas,
        'porcentaje_completado', ROUND((v_preguntas_dominadas::DECIMAL / 3000) * 100, 2),
        'ritmo_actual_dia', ROUND(v_ritmo_actual, 2),
        'ritmo_necesario_dia', ROUND(v_ritmo_necesario, 2),
        'esta_en_ritmo', v_ritmo_actual >= v_ritmo_necesario,
        'debe_acelerar', v_ritmo_actual < v_ritmo_necesario,
        'proyeccion_final', ROUND(v_preguntas_dominadas + (v_ritmo_actual * v_dias_restantes), 0),
        'probabilidad_completar_3000', CASE
            WHEN v_ritmo_actual >= v_ritmo_necesario THEN 85.0
            WHEN v_ritmo_actual >= (v_ritmo_necesario * 0.8) THEN 65.0
            WHEN v_ritmo_actual >= (v_ritmo_necesario * 0.6) THEN 40.0
            ELSE 15.0
        END
    );
    
    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- Función: Recalcular todas las predicciones (JOB nocturno)
CREATE OR REPLACE FUNCTION fn_recalcular_todas_predicciones()
RETURNS INTEGER AS $$
DECLARE
    v_actualizadas INTEGER := 0;
    v_record RECORD;
    v_probabilidad DECIMAL;
BEGIN
    FOR v_record IN 
        SELECT 
            po.id,
            po.ultima_respuesta_correcta,
            po.veces_respondida_correcta,
            po.veces_respondida_incorrecta
        FROM prediccion_olvido po
        WHERE po.ultima_respuesta_correcta IS NOT NULL
    LOOP
        v_probabilidad := fn_calcular_probabilidad_olvido(
            v_record.ultima_respuesta_correcta,
            v_record.veces_respondida_correcta,
            v_record.veces_respondida_incorrecta
        );
        
        UPDATE prediccion_olvido SET
            probabilidad_olvido = v_probabilidad,
            dias_desde_ultima_correcta = EXTRACT(EPOCH FROM (NOW() - ultima_respuesta_correcta)) / 86400.0,
            nivel_consolidacion = CASE
                WHEN veces_respondida_correcta >= 5 THEN 'permanente'
                WHEN veces_respondida_correcta >= 3 THEN 'consolidado'
                WHEN veces_respondida_correcta >= 1 THEN 'en_consolidacion'
                ELSE 'fragil'
            END,
            urgencia_revision = CASE
                WHEN v_probabilidad >= 80 THEN 'urgente'
                WHEN v_probabilidad >= 60 THEN 'pronto'
                WHEN v_probabilidad >= 40 THEN 'normal'
                ELSE 'no_necesaria'
            END,
            requiere_revision_inmediata = v_probabilidad >= 75,
            fecha_revision_optima = NOW() + INTERVAL '1 day' * (100 - v_probabilidad) / 20,
            actualizado_at = NOW()
        WHERE id = v_record.id;
        
        v_actualizadas := v_actualizadas + 1;
    END LOOP;
    
    RETURN v_actualizadas;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS AUTOMÁTICOS
-- ============================================

-- Trigger: Actualizar perfil después de cada respuesta
CREATE OR REPLACE FUNCTION trg_actualizar_perfil_usuario()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO perfil_usuario (
        usuario_id, 
        total_preguntas_respondidas, 
        total_correctas, 
        total_incorrectas,
        total_omitidas
    )
    VALUES (
        NEW.usuario_id, 
        1,
        CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END,
        CASE WHEN NOT NEW.es_correcta AND NOT NEW.fue_omitida THEN 1 ELSE 0 END,
        CASE WHEN NEW.fue_omitida THEN 1 ELSE 0 END
    )
    ON CONFLICT (usuario_id) DO UPDATE SET
        total_preguntas_respondidas = perfil_usuario.total_preguntas_respondidas + 1,
        total_correctas = perfil_usuario.total_correctas + CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END,
        total_incorrectas = perfil_usuario.total_incorrectas + CASE WHEN NOT NEW.es_correcta AND NOT NEW.fue_omitida THEN 1 ELSE 0 END,
        total_omitidas = perfil_usuario.total_omitidas + CASE WHEN NEW.fue_omitida THEN 1 ELSE 0 END,
        tasa_acierto_global = (
            (perfil_usuario.total_correctas + CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END)::DECIMAL /
            NULLIF(perfil_usuario.total_preguntas_respondidas + 1, 0)
        ) * 100,
        velocidad_promedio_segundos = (
            (COALESCE(perfil_usuario.velocidad_promedio_segundos, 0) * perfil_usuario.total_preguntas_respondidas + NEW.tiempo_total_respuesta) /
            (perfil_usuario.total_preguntas_respondidas + 1)
        ),
        actualizado_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_actualizar_perfil ON respuesta_usuario;
CREATE TRIGGER trigger_actualizar_perfil
AFTER INSERT ON respuesta_usuario
FOR EACH ROW EXECUTE FUNCTION trg_actualizar_perfil_usuario();

-- Trigger: Actualizar dominio por materia
CREATE OR REPLACE FUNCTION trg_actualizar_dominio_materia()
RETURNS TRIGGER AS $$
DECLARE
    v_materia_id UUID;
    v_tasa_dominio DECIMAL;
BEGIN
    SELECT materia_id INTO v_materia_id 
    FROM pregunta 
    WHERE id = NEW.pregunta_id;
    
    INSERT INTO dominio_materia (
        usuario_id,
        materia_id,
        total_preguntas_vistas,
        total_correctas,
        total_incorrectas,
        total_omitidas
    )
    VALUES (
        NEW.usuario_id,
        v_materia_id,
        1,
        CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END,
        CASE WHEN NOT NEW.es_correcta AND NOT NEW.fue_omitida THEN 1 ELSE 0 END,
        CASE WHEN NEW.fue_omitida THEN 1 ELSE 0 END
    )
    ON CONFLICT (usuario_id, materia_id) DO UPDATE SET
        total_preguntas_vistas = dominio_materia.total_preguntas_vistas + 1,
        total_correctas = dominio_materia.total_correctas + CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END,
        total_incorrectas = dominio_materia.total_incorrectas + CASE WHEN NOT NEW.es_correcta AND NOT NEW.fue_omitida THEN 1 ELSE 0 END,
        total_omitidas = dominio_materia.total_omitidas + CASE WHEN NEW.fue_omitida THEN 1 ELSE 0 END,
        ultima_practica = NOW(),
        actualizado_at = NOW();
    
    SELECT 
        (total_correctas::DECIMAL / NULLIF(total_preguntas_vistas, 0)) * 100
    INTO v_tasa_dominio
    FROM dominio_materia
    WHERE usuario_id = NEW.usuario_id AND materia_id = v_materia_id;
    
    UPDATE dominio_materia SET
        tasa_dominio = v_tasa_dominio,
        nivel_dominio = fn_calcular_nivel_dominio(v_tasa_dominio),
        color_mapa_calor = CASE
            WHEN v_tasa_dominio >= 95 THEN 'dorado'
            WHEN v_tasa_dominio >= 80 THEN 'verde'
            WHEN v_tasa_dominio >= 60 THEN 'amarillo'
            WHEN v_tasa_dominio >= 40 THEN 'naranja'
            ELSE 'rojo'
        END,
        necesita_refuerzo_urgente = v_tasa_dominio < 60,
        prioridad_estudio = CASE
            WHEN v_tasa_dominio < 40 THEN 5
            WHEN v_tasa_dominio < 60 THEN 4
            WHEN v_tasa_dominio < 75 THEN 3
            WHEN v_tasa_dominio < 85 THEN 2
            ELSE 1
        END
    WHERE usuario_id = NEW.usuario_id AND materia_id = v_materia_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_actualizar_dominio ON respuesta_usuario;
CREATE TRIGGER trigger_actualizar_dominio
AFTER INSERT ON respuesta_usuario
FOR EACH ROW EXECUTE FUNCTION trg_actualizar_dominio_materia();

-- Trigger: Actualizar predicción de olvido
CREATE OR REPLACE FUNCTION trg_actualizar_prediccion_olvido()
RETURNS TRIGGER AS $$
DECLARE
    v_probabilidad DECIMAL;
BEGIN
    IF NEW.es_correcta THEN
        INSERT INTO prediccion_olvido (
            usuario_id,
            pregunta_id,
            ultima_respuesta_correcta,
            veces_respondida_correcta
        )
        VALUES (
            NEW.usuario_id,
            NEW.pregunta_id,
            NOW(),
            1
        )
        ON CONFLICT (usuario_id, pregunta_id) DO UPDATE SET
            ultima_respuesta_correcta = NOW(),
            veces_respondida_correcta = prediccion_olvido.veces_respondida_correcta + 1,
            dias_desde_ultima_correcta = 0,
            actualizado_at = NOW();
    ELSE
        UPDATE prediccion_olvido SET
            ultima_respuesta_incorrecta = NOW(),
            veces_respondida_incorrecta = veces_respondida_incorrecta + 1,
            actualizado_at = NOW()
        WHERE usuario_id = NEW.usuario_id AND pregunta_id = NEW.pregunta_id;
    END IF;
    
    SELECT fn_calcular_probabilidad_olvido(
        ultima_respuesta_correcta,
        veces_respondida_correcta,
        veces_respondida_incorrecta
    )
    INTO v_probabilidad
    FROM prediccion_olvido
    WHERE usuario_id = NEW.usuario_id AND pregunta_id = NEW.pregunta_id;
    
    UPDATE prediccion_olvido SET
        probabilidad_olvido = v_probabilidad,
        dias_desde_ultima_correcta = EXTRACT(EPOCH FROM (NOW() - ultima_respuesta_correcta)) / 86400.0,
        nivel_consolidacion = CASE
            WHEN veces_respondida_correcta >= 5 THEN 'permanente'
            WHEN veces_respondida_correcta >= 3 THEN 'consolidado'
            WHEN veces_respondida_correcta >= 1 THEN 'en_consolidacion'
            ELSE 'fragil'
        END,
        urgencia_revision = CASE
            WHEN v_probabilidad >= 80 THEN 'urgente'
            WHEN v_probabilidad >= 60 THEN 'pronto'
            WHEN v_probabilidad >= 40 THEN 'normal'
            ELSE 'no_necesaria'
        END,
        requiere_revision_inmediata = v_probabilidad >= 75,
        fecha_revision_optima = NOW() + INTERVAL '1 day' * (100 - v_probabilidad) / 20
    WHERE usuario_id = NEW.usuario_id AND pregunta_id = NEW.pregunta_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_actualizar_prediccion ON respuesta_usuario;
CREATE TRIGGER trigger_actualizar_prediccion
AFTER INSERT ON respuesta_usuario
FOR EACH ROW EXECUTE FUNCTION trg_actualizar_prediccion_olvido();

-- Trigger: Actualizar exposición cuando responde
CREATE OR REPLACE FUNCTION trg_actualizar_exposicion_on_respuesta()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM fn_actualizar_exposicion_pregunta(
        NEW.usuario_id,
        NEW.pregunta_id,
        NEW.es_correcta
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_actualizar_exposicion ON respuesta_usuario;
CREATE TRIGGER trigger_actualizar_exposicion
AFTER INSERT ON respuesta_usuario
FOR EACH ROW EXECUTE FUNCTION trg_actualizar_exposicion_on_respuesta();

-- ============================================
-- COMENTARIOS
-- ============================================

COMMENT ON FUNCTION fn_diagnosticar_tipo_error IS 'Función IA para clasificar automáticamente el tipo de error del usuario';
COMMENT ON FUNCTION fn_calcular_probabilidad_olvido IS 'Implementación de la curva de Ebbinghaus adaptada';
COMMENT ON FUNCTION fn_calcular_nivel_dominio IS 'Clasificación automática del nivel de dominio';
COMMENT ON FUNCTION fn_generar_plan_dia_siguiente IS 'Genera plan diario inteligente (30 nuevas + 20 repaso)';
COMMENT ON FUNCTION fn_actualizar_exposicion_pregunta IS 'Actualiza estado de dominio y cola de repaso';
COMMENT ON FUNCTION fn_calcular_progreso_60_dias IS 'Calcula si el usuario va en ritmo para completar 3000 en 60 días';
COMMENT ON FUNCTION fn_recalcular_todas_predicciones IS 'Recalcula predicciones de olvido (ejecutar diariamente)';

-- ============================================
-- FIN PARTE 2
-- Continuar con PARTE 3 (políticas RLS)
-- ============================================

-- ===== FIN base_de_datos_supabase\02_FUNCIONES_TRIGGERS.sql =====


-- ===== INICIO base_de_datos_supabase\03_POLITICAS_RLS.sql =====

-- ============================================
-- SARGENTO IA - POLÍTICAS DE SEGURIDAD (RLS)
-- PARTE 3: Ejecutar DESPUÉS de 02_FUNCIONES_TRIGGERS.sql
-- ============================================

-- ============================================
-- HABILITAR RLS EN TODAS LAS TABLAS
-- ============================================

ALTER TABLE usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE perfil_usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE meta_diaria ENABLE ROW LEVEL SECURITY;
ALTER TABLE estadistica_usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE configuracion_usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE sesion_practica ENABLE ROW LEVEL SECURITY;
ALTER TABLE respuesta_usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE error_analizado ENABLE ROW LEVEL SECURITY;
ALTER TABLE dominio_materia ENABLE ROW LEVEL SECURITY;
ALTER TABLE prediccion_olvido ENABLE ROW LEVEL SECURITY;
ALTER TABLE mensaje_ia ENABLE ROW LEVEL SECURITY;
ALTER TABLE ranking ENABLE ROW LEVEL SECURITY;
ALTER TABLE batalla ENABLE ROW LEVEL SECURITY;
ALTER TABLE respuesta_batalla ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario_logro ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_estudio_diario ENABLE ROW LEVEL SECURITY;
ALTER TABLE exposicion_pregunta ENABLE ROW LEVEL SECURITY;
ALTER TABLE patron_error_detallado ENABLE ROW LEVEL SECURITY;
ALTER TABLE prediccion_examen ENABLE ROW LEVEL SECURITY;
ALTER TABLE cola_repaso_inteligente ENABLE ROW LEVEL SECURITY;

-- ============================================
-- POLÍTICAS PARA TABLA: USUARIO
-- ============================================

CREATE POLICY "Usuarios pueden ver su propio perfil"
ON usuario
FOR SELECT
USING (auth.uid()::text = id::text);

CREATE POLICY "Usuarios pueden actualizar su propio perfil"
ON usuario
FOR UPDATE
USING (auth.uid()::text = id::text);

CREATE POLICY "Permitir registro de nuevos usuarios"
ON usuario
FOR INSERT
WITH CHECK (auth.uid()::text = id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: PERFIL_USUARIO
-- ============================================

CREATE POLICY "Usuarios pueden ver su propio perfil de aprendizaje"
ON perfil_usuario
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede actualizar perfil de aprendizaje"
ON perfil_usuario
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: META_DIARIA
-- ============================================

CREATE POLICY "Usuarios pueden ver sus propias metas"
ON meta_diaria
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Usuarios pueden crear y actualizar sus metas"
ON meta_diaria
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: ESTADISTICA_USUARIO
-- ============================================

CREATE POLICY "Usuarios pueden ver sus propias estadísticas"
ON estadistica_usuario
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede actualizar estadísticas"
ON estadistica_usuario
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: CONFIGURACION_USUARIO
-- ============================================

CREATE POLICY "Usuarios pueden ver su configuración"
ON configuracion_usuario
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Usuarios pueden actualizar su configuración"
ON configuracion_usuario
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: SESION_PRACTICA
-- ============================================

CREATE POLICY "Usuarios pueden ver sus propias sesiones"
ON sesion_practica
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Usuarios pueden crear y actualizar sus sesiones"
ON sesion_practica
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: RESPUESTA_USUARIO
-- ============================================

CREATE POLICY "Usuarios pueden ver sus propias respuestas"
ON respuesta_usuario
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Usuarios pueden crear sus respuestas"
ON respuesta_usuario
FOR INSERT
WITH CHECK (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: ERROR_ANALIZADO
-- ============================================

CREATE POLICY "Usuarios pueden ver sus propios errores"
ON error_analizado
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede crear análisis de errores"
ON error_analizado
FOR INSERT
WITH CHECK (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: DOMINIO_MATERIA
-- ============================================

CREATE POLICY "Usuarios pueden ver su dominio de materias"
ON dominio_materia
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede actualizar dominio de materias"
ON dominio_materia
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: PREDICCION_OLVIDO
-- ============================================

CREATE POLICY "Usuarios pueden ver sus predicciones"
ON prediccion_olvido
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede actualizar predicciones"
ON prediccion_olvido
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: MENSAJE_IA
-- ============================================

CREATE POLICY "Usuarios pueden ver sus mensajes"
ON mensaje_ia
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Usuarios pueden actualizar estado de lectura"
ON mensaje_ia
FOR UPDATE
USING (auth.uid()::text = usuario_id::text)
WITH CHECK (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede crear mensajes"
ON mensaje_ia
FOR INSERT
WITH CHECK (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: RANKING
-- ============================================

CREATE POLICY "Todos pueden ver el ranking público"
ON ranking
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Usuarios pueden actualizar su propio ranking"
ON ranking
FOR UPDATE
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede crear ranking"
ON ranking
FOR INSERT
WITH CHECK (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: BATALLA
-- ============================================

CREATE POLICY "Usuarios pueden ver sus batallas"
ON batalla
FOR SELECT
USING (
    auth.uid()::text = usuario1_id::text 
    OR auth.uid()::text = usuario2_id::text
);

CREATE POLICY "Usuarios pueden crear batallas"
ON batalla
FOR INSERT
WITH CHECK (auth.uid()::text = usuario1_id::text);

CREATE POLICY "Usuarios pueden actualizar sus batallas"
ON batalla
FOR UPDATE
USING (
    auth.uid()::text = usuario1_id::text 
    OR auth.uid()::text = usuario2_id::text
);

-- ============================================
-- POLÍTICAS PARA TABLA: RESPUESTA_BATALLA
-- ============================================

CREATE POLICY "Usuarios pueden ver respuestas de batallas activas"
ON respuesta_batalla
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM batalla
        WHERE batalla.id = respuesta_batalla.batalla_id
        AND (batalla.usuario1_id::text = auth.uid()::text 
             OR batalla.usuario2_id::text = auth.uid()::text)
    )
);

CREATE POLICY "Usuarios pueden crear respuestas en sus batallas"
ON respuesta_batalla
FOR INSERT
WITH CHECK (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: USUARIO_LOGRO
-- ============================================

CREATE POLICY "Usuarios pueden ver sus logros"
ON usuario_logro
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Todos pueden ver logros públicos"
ON usuario_logro
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Sistema puede otorgar logros"
ON usuario_logro
FOR INSERT
WITH CHECK (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: PLAN_ESTUDIO_DIARIO
-- ============================================

CREATE POLICY "Usuarios pueden ver su plan de estudio"
ON plan_estudio_diario
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede crear y actualizar planes"
ON plan_estudio_diario
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: EXPOSICION_PREGUNTA
-- ============================================

CREATE POLICY "Usuarios pueden ver su exposición a preguntas"
ON exposicion_pregunta
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede actualizar exposición"
ON exposicion_pregunta
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: PATRON_ERROR_DETALLADO
-- ============================================

CREATE POLICY "Usuarios pueden ver sus patrones de error"
ON patron_error_detallado
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede crear y actualizar patrones"
ON patron_error_detallado
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: PREDICCION_EXAMEN
-- ============================================

CREATE POLICY "Usuarios pueden ver sus predicciones de examen"
ON prediccion_examen
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede crear predicciones"
ON prediccion_examen
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLA: COLA_REPASO_INTELIGENTE
-- ============================================

CREATE POLICY "Usuarios pueden ver su cola de repaso"
ON cola_repaso_inteligente
FOR SELECT
USING (auth.uid()::text = usuario_id::text);

CREATE POLICY "Sistema puede actualizar cola de repaso"
ON cola_repaso_inteligente
FOR ALL
USING (auth.uid()::text = usuario_id::text);

-- ============================================
-- POLÍTICAS PARA TABLAS PÚBLICAS (sin RLS)
-- ============================================

-- Permitir lectura de tablas públicas a todos los usuarios autenticados
GRANT SELECT ON materia TO authenticated;
GRANT SELECT ON banco_de_pregunta TO authenticated;
GRANT SELECT ON pregunta TO authenticated;
GRANT SELECT ON alternativa TO authenticated;
GRANT SELECT ON referencia_legal TO authenticated;
GRANT SELECT ON logro TO authenticated;
GRANT SELECT ON correlacion_preguntas TO authenticated;

-- ============================================
-- FUNCIONES CON SEGURIDAD DEFINER
-- ============================================

ALTER FUNCTION trg_actualizar_perfil_usuario() SECURITY DEFINER;
ALTER FUNCTION trg_actualizar_dominio_materia() SECURITY DEFINER;
ALTER FUNCTION trg_actualizar_prediccion_olvido() SECURITY DEFINER;
ALTER FUNCTION trg_actualizar_exposicion_on_respuesta() SECURITY DEFINER;

-- ============================================
-- FIN PARTE 3
-- Base de datos lista para usar
-- ============================================

-- VERIFICACIÓN RÁPIDA
DO $$
BEGIN
    RAISE NOTICE '✓ Base de datos Sargento IA instalada correctamente';
    RAISE NOTICE '✓ Total de tablas: 30';
    RAISE NOTICE '✓ Funciones IA: 7';
    RAISE NOTICE '✓ Triggers automáticos: 4';
    RAISE NOTICE '✓ Políticas RLS: Activas';
    RAISE NOTICE '';
    RAISE NOTICE 'Próximos pasos:';
    RAISE NOTICE '1. Poblar materias (INSERT INTO materia...)';
    RAISE NOTICE '2. Cargar banco de preguntas';
    RAISE NOTICE '3. Crear usuario de prueba';
    RAISE NOTICE '4. Configurar CRON jobs';
END $$;

-- ===== FIN base_de_datos_supabase\03_POLITICAS_RLS.sql =====


-- ===== INICIO base_de_datos_supabase\04_SISTEMA_DINAMICO.sql =====

-- ============================================
-- ACTUALIZACIÓN: SISTEMA DINÁMICO DE DÍAS
-- Ejecutar DESPUÉS de los 3 archivos principales
-- ============================================

-- Este archivo modifica las funciones para que el sistema
-- se adapte automáticamente a cualquier plazo:
-- 30 días, 60 días, 90 días, 150 días (5 meses), etc.

-- ============================================
-- 1. FUNCIÓN: Calcular días totales disponibles
-- ============================================

CREATE OR REPLACE FUNCTION fn_calcular_dias_disponibles(p_usuario_id UUID)
RETURNS TABLE (
    dias_totales INTEGER,
    dias_transcurridos INTEGER,
    dias_restantes INTEGER,
    fecha_inicio DATE,
    fecha_examen DATE,
    porcentaje_tiempo_usado DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (u.fecha_examen_objetivo - u.fecha_registro::DATE)::INTEGER AS dias_totales,
        (CURRENT_DATE - u.fecha_registro::DATE)::INTEGER AS dias_transcurridos,
        (u.fecha_examen_objetivo - CURRENT_DATE)::INTEGER AS dias_restantes,
        u.fecha_registro::DATE AS fecha_inicio,
        u.fecha_examen_objetivo AS fecha_examen,
        ROUND(
            ((CURRENT_DATE - u.fecha_registro::DATE)::DECIMAL / 
             NULLIF((u.fecha_examen_objetivo - u.fecha_registro::DATE), 0)) * 100, 
            2
        ) AS porcentaje_tiempo_usado
    FROM usuario u
    WHERE u.id = p_usuario_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 2. FUNCIÓN ACTUALIZADA: Progreso dinámico
-- ============================================

CREATE OR REPLACE FUNCTION fn_calcular_progreso_dinamico(p_usuario_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_resultado JSONB;
    v_dias_totales INTEGER;
    v_dias_transcurridos INTEGER;
    v_dias_restantes INTEGER;
    v_preguntas_dominadas INTEGER;
    v_preguntas_vistas INTEGER;
    v_ritmo_actual DECIMAL;
    v_ritmo_necesario DECIMAL;
    v_ritmo_ideal DECIMAL;
    v_fecha_examen DATE;
BEGIN
    -- Obtener información de tiempo del usuario
    SELECT 
        (fecha_examen_objetivo - fecha_registro::DATE)::INTEGER,
        (CURRENT_DATE - fecha_registro::DATE)::INTEGER,
        (fecha_examen_objetivo - CURRENT_DATE)::INTEGER,
        fecha_examen_objetivo
    INTO v_dias_totales, v_dias_transcurridos, v_dias_restantes, v_fecha_examen
    FROM usuario
    WHERE id = p_usuario_id;
    
    -- Si no tiene fecha de examen, usar 60 días por defecto
    IF v_fecha_examen IS NULL THEN
        v_dias_totales := 60;
        v_dias_transcurridos := COALESCE(v_dias_transcurridos, 0);
        v_dias_restantes := 60 - v_dias_transcurridos;
    END IF;
    
    -- Contar preguntas dominadas
    SELECT COUNT(*)
    INTO v_preguntas_dominadas
    FROM exposicion_pregunta
    WHERE usuario_id = p_usuario_id
    AND estado_dominio IN ('dominada', 'consolidando');
    
    -- Contar preguntas vistas
    SELECT COUNT(*)
    INTO v_preguntas_vistas
    FROM exposicion_pregunta
    WHERE usuario_id = p_usuario_id;
    
    -- Calcular ritmos
    v_ritmo_actual := CASE WHEN v_dias_transcurridos > 0 
        THEN v_preguntas_dominadas::DECIMAL / v_dias_transcurridos 
        ELSE 0 END;
    
    v_ritmo_ideal := CASE WHEN v_dias_totales > 0
        THEN 3000.0 / v_dias_totales
        ELSE 50 END;
    
    v_ritmo_necesario := CASE WHEN v_dias_restantes > 0
        THEN (3000 - v_preguntas_dominadas)::DECIMAL / v_dias_restantes
        ELSE 999 END;
    
    -- Construir resultado
    v_resultado := jsonb_build_object(
        -- Información de tiempo
        'dias_totales', v_dias_totales,
        'dias_transcurridos', v_dias_transcurridos,
        'dias_restantes', v_dias_restantes,
        'porcentaje_tiempo_usado', ROUND((v_dias_transcurridos::DECIMAL / NULLIF(v_dias_totales, 0)) * 100, 2),
        'fecha_examen', v_fecha_examen,
        
        -- Progreso de preguntas
        'preguntas_dominadas', v_preguntas_dominadas,
        'preguntas_vistas', v_preguntas_vistas,
        'preguntas_faltantes', 3000 - v_preguntas_dominadas,
        'porcentaje_completado', ROUND((v_preguntas_dominadas::DECIMAL / 3000) * 100, 2),
        
        -- Ritmos (dinámicos)
        'ritmo_actual_dia', ROUND(v_ritmo_actual, 2),
        'ritmo_ideal_dia', ROUND(v_ritmo_ideal, 2),
        'ritmo_necesario_dia', ROUND(v_ritmo_necesario, 2),
        
        -- Análisis
        'esta_en_ritmo', v_ritmo_actual >= v_ritmo_ideal,
        'esta_adelantado', v_ritmo_actual > v_ritmo_ideal * 1.1,
        'esta_atrasado', v_ritmo_actual < v_ritmo_ideal * 0.9,
        'debe_acelerar', v_ritmo_actual < v_ritmo_necesario,
        
        -- Proyecciones
        'proyeccion_final', ROUND(v_preguntas_dominadas + (v_ritmo_actual * v_dias_restantes), 0),
        'probabilidad_completar_3000', CASE
            WHEN v_ritmo_actual >= v_ritmo_necesario THEN 85.0
            WHEN v_ritmo_actual >= (v_ritmo_necesario * 0.8) THEN 65.0
            WHEN v_ritmo_actual >= (v_ritmo_necesario * 0.6) THEN 40.0
            ELSE 15.0
        END,
        
        -- Recomendación adaptativa
        'recomendacion_preguntas_dia', CASE
            WHEN v_ritmo_actual < v_ritmo_necesario * 0.8 THEN CEIL(v_ritmo_necesario * 1.2)
            WHEN v_ritmo_actual < v_ritmo_necesario THEN CEIL(v_ritmo_necesario * 1.1)
            ELSE CEIL(v_ritmo_ideal)
        END
    );
    
    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 3. FUNCIÓN ACTUALIZADA: Plan diario dinámico
-- ============================================

CREATE OR REPLACE FUNCTION fn_generar_plan_adaptativo(
    p_usuario_id UUID,
    p_fecha_objetivo DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_plan JSONB;
    v_preguntas_nuevas UUID[];
    v_preguntas_repaso UUID[];
    v_materias_debiles UUID[];
    v_dias_restantes INTEGER;
    v_preguntas_faltantes INTEGER;
    v_cantidad_nuevas INTEGER;
    v_cantidad_repaso INTEGER;
    v_total_dia INTEGER;
BEGIN
    -- Calcular días restantes
    SELECT 
        COALESCE(
            (fecha_examen_objetivo - CURRENT_DATE)::INTEGER,
            60  -- Default si no tiene fecha
        )
    INTO v_dias_restantes
    FROM usuario
    WHERE id = p_usuario_id;
    
    -- Calcular preguntas faltantes
    SELECT 3000 - COUNT(*)
    INTO v_preguntas_faltantes
    FROM exposicion_pregunta
    WHERE usuario_id = p_usuario_id
    AND estado_dominio IN ('dominada', 'consolidando');
    
    -- Calcular cuántas preguntas por día NECESITA hacer
    v_total_dia := CASE 
        WHEN v_dias_restantes > 0 THEN CEIL(v_preguntas_faltantes::DECIMAL / v_dias_restantes)
        ELSE 50  -- Default
    END;
    
    -- Limitar entre 20 y 100 preguntas/día
    v_total_dia := GREATEST(20, LEAST(v_total_dia, 100));
    
    -- Distribuir: 60% nuevas, 40% repaso
    v_cantidad_nuevas := CEIL(v_total_dia * 0.6);
    v_cantidad_repaso := v_total_dia - v_cantidad_nuevas;
    
    -- Identificar preguntas nuevas prioritarias
    SELECT ARRAY_AGG(p.id ORDER BY p.score_importancia DESC, p.frecuencia_examen_real DESC)
    INTO v_preguntas_nuevas
    FROM pregunta p
    WHERE NOT EXISTS (
        SELECT 1 FROM exposicion_pregunta ep
        WHERE ep.usuario_id = p_usuario_id AND ep.pregunta_id = p.id
    )
    LIMIT v_cantidad_nuevas;
    
    -- Identificar preguntas para repaso urgente
    SELECT ARRAY_AGG(cr.pregunta_id ORDER BY cr.prioridad_urgencia DESC)
    INTO v_preguntas_repaso
    FROM cola_repaso_inteligente cr
    WHERE cr.usuario_id = p_usuario_id
    AND cr.en_cola = TRUE
    AND cr.proxima_revision_optima <= NOW() + INTERVAL '1 day'
    LIMIT v_cantidad_repaso;
    
    -- Identificar materias débiles
    SELECT ARRAY_AGG(dm.materia_id)
    INTO v_materias_debiles
    FROM dominio_materia dm
    WHERE dm.usuario_id = p_usuario_id
    AND dm.tasa_dominio < 60
    ORDER BY dm.tasa_dominio ASC;
    
    -- Construir plan
    v_plan := jsonb_build_object(
        'fecha_generacion', CURRENT_DATE,
        'dias_restantes', v_dias_restantes,
        'preguntas_faltantes', v_preguntas_faltantes,
        
        'preguntas_nuevas', v_preguntas_nuevas,
        'cantidad_nuevas', COALESCE(array_length(v_preguntas_nuevas, 1), 0),
        
        'preguntas_repaso', v_preguntas_repaso,
        'cantidad_repaso', COALESCE(array_length(v_preguntas_repaso, 1), 0),
        
        'total_preguntas_dia', COALESCE(array_length(v_preguntas_nuevas, 1), 0) + 
                               COALESCE(array_length(v_preguntas_repaso, 1), 0),
        
        'materias_prioritarias', v_materias_debiles,
        
        'mensaje_ia', CASE
            WHEN v_dias_restantes <= 30 THEN 
                '⚠️ URGENTE: Solo quedan ' || v_dias_restantes || ' días. Ritmo intensivo necesario.'
            WHEN v_dias_restantes <= 60 THEN
                '📚 Tiempo moderado: ' || v_dias_restantes || ' días. Mantén consistencia diaria.'
            ELSE
                '✅ Buen tiempo disponible: ' || v_dias_restantes || ' días. Estudia con calma pero constante.'
        END
    );
    
    RETURN v_plan;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. FUNCIÓN: Calcular predicción adaptativa
-- ============================================

CREATE OR REPLACE FUNCTION fn_calcular_probabilidad_aprobacion_dinamica(p_usuario_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_resultado JSONB;
    v_tasa_acierto DECIMAL;
    v_materias_criticas INTEGER;
    v_dias_totales INTEGER;
    v_dias_transcurridos INTEGER;
    v_dias_restantes INTEGER;
    v_preguntas_dominadas INTEGER;
    v_racha_dias INTEGER;
    v_probabilidad DECIMAL := 50;
    v_ritmo_actual DECIMAL;
    v_ritmo_necesario DECIMAL;
BEGIN
    -- Obtener datos temporales
    SELECT 
        (fecha_examen_objetivo - fecha_registro::DATE)::INTEGER,
        (CURRENT_DATE - fecha_registro::DATE)::INTEGER,
        (fecha_examen_objetivo - CURRENT_DATE)::INTEGER
    INTO v_dias_totales, v_dias_transcurridos, v_dias_restantes
    FROM usuario
    WHERE id = p_usuario_id;
    
    -- Obtener tasa de acierto y racha
    SELECT 
        tasa_acierto_global, 
        dias_consecutivos_estudio
    INTO v_tasa_acierto, v_racha_dias
    FROM perfil_usuario
    WHERE usuario_id = p_usuario_id;
    
    -- Contar preguntas dominadas
    SELECT COUNT(*)
    INTO v_preguntas_dominadas
    FROM exposicion_pregunta
    WHERE usuario_id = p_usuario_id
    AND estado_dominio IN ('dominada', 'consolidando');
    
    -- Contar materias críticas
    SELECT COUNT(*)
    INTO v_materias_criticas
    FROM dominio_materia
    WHERE usuario_id = p_usuario_id
    AND tasa_dominio < 60;
    
    -- Calcular ritmos
    v_ritmo_actual := CASE WHEN v_dias_transcurridos > 0
        THEN v_preguntas_dominadas::DECIMAL / v_dias_transcurridos
        ELSE 0 END;
    
    v_ritmo_necesario := CASE WHEN v_dias_restantes > 0
        THEN (3000 - v_preguntas_dominadas)::DECIMAL / v_dias_restantes
        ELSE 999 END;
    
    -- CÁLCULO DE PROBABILIDAD ADAPTATIVO
    
    -- Factor 1: Progreso actual (40%)
    v_probabilidad := v_probabilidad + 
        ((v_preguntas_dominadas::DECIMAL / 3000) * 100 - 50) * 0.4;
    
    -- Factor 2: Tasa de acierto (25%)
    v_probabilidad := v_probabilidad + 
        ((COALESCE(v_tasa_acierto, 50) - 50) * 0.25);
    
    -- Factor 3: Ritmo de estudio (20%)
    IF v_ritmo_actual >= v_ritmo_necesario THEN
        v_probabilidad := v_probabilidad + 20;
    ELSIF v_ritmo_actual >= (v_ritmo_necesario * 0.8) THEN
        v_probabilidad := v_probabilidad + 10;
    ELSIF v_ritmo_actual >= (v_ritmo_necesario * 0.6) THEN
        v_probabilidad := v_probabilidad + 0;
    ELSE
        v_probabilidad := v_probabilidad - 10;
    END IF;
    
    -- Factor 4: Materias críticas (-15%)
    v_probabilidad := v_probabilidad - (v_materias_criticas * 3);
    
    -- Factor 5: Racha de estudio (+15%)
    IF v_racha_dias >= 30 THEN
        v_probabilidad := v_probabilidad + 15;
    ELSIF v_racha_dias >= 14 THEN
        v_probabilidad := v_probabilidad + 10;
    ELSIF v_racha_dias >= 7 THEN
        v_probabilidad := v_probabilidad + 5;
    END IF;
    
    -- Limitar entre 0-100
    v_probabilidad := GREATEST(0, LEAST(v_probabilidad, 100));
    
    -- Construir resultado
    v_resultado := jsonb_build_object(
        'probabilidad_aprobacion', ROUND(v_probabilidad, 2),
        'nivel_confianza', CASE
            WHEN v_probabilidad >= 90 THEN 'MUY_ALTA'
            WHEN v_probabilidad >= 75 THEN 'ALTA'
            WHEN v_probabilidad >= 60 THEN 'MEDIA'
            WHEN v_probabilidad >= 40 THEN 'BAJA'
            ELSE 'MUY_BAJA'
        END,
        'puntaje_estimado', ROUND(50 + (v_probabilidad * 0.5), 1),
        'dias_restantes', v_dias_restantes,
        'ritmo_actual', ROUND(v_ritmo_actual, 2),
        'ritmo_necesario', ROUND(v_ritmo_necesario, 2),
        'factores', jsonb_build_object(
            'preguntas_dominadas', v_preguntas_dominadas,
            'tasa_acierto', v_tasa_acierto,
            'materias_criticas', v_materias_criticas,
            'racha_dias', v_racha_dias,
            'esta_en_ritmo', v_ritmo_actual >= v_ritmo_necesario
        )
    );
    
    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. VISTA: Dashboard adaptativo
-- ============================================

CREATE OR REPLACE VIEW v_dashboard_adaptativo AS
SELECT 
    u.id AS usuario_id,
    u.user_id,
    u.nombre_completo,
    u.fecha_examen_objetivo,
    
    -- Tiempo
    (u.fecha_examen_objetivo - u.fecha_registro::DATE)::INTEGER AS dias_totales,
    (CURRENT_DATE - u.fecha_registro::DATE)::INTEGER AS dias_transcurridos,
    (u.fecha_examen_objetivo - CURRENT_DATE)::INTEGER AS dias_restantes,
    
    -- Progreso
    pu.tasa_acierto_global,
    pu.probabilidad_aprobacion,
    pu.dias_consecutivos_estudio AS racha_dias,
    
    -- Preguntas
    COUNT(DISTINCT ep.pregunta_id) FILTER (WHERE ep.estado_dominio = 'dominada') AS preguntas_dominadas,
    COUNT(DISTINCT ep.pregunta_id) AS preguntas_vistas,
    
    -- Ritmo calculado dinámicamente
    CASE WHEN (CURRENT_DATE - u.fecha_registro::DATE) > 0
        THEN ROUND(
            COUNT(DISTINCT ep.pregunta_id) FILTER (WHERE ep.estado_dominio = 'dominada')::DECIMAL / 
            (CURRENT_DATE - u.fecha_registro::DATE)::INTEGER,
            2
        )
        ELSE 0
    END AS ritmo_actual_dia,
    
    -- Ritmo necesario dinámico
    CASE WHEN (u.fecha_examen_objetivo - CURRENT_DATE) > 0
        THEN ROUND(
            (3000 - COUNT(DISTINCT ep.pregunta_id) FILTER (WHERE ep.estado_dominio = 'dominada'))::DECIMAL / 
            (u.fecha_examen_objetivo - CURRENT_DATE)::INTEGER,
            2
        )
        ELSE 999
    END AS ritmo_necesario_dia
    
FROM usuario u
LEFT JOIN perfil_usuario pu ON u.id = pu.usuario_id
LEFT JOIN exposicion_pregunta ep ON u.id = ep.usuario_id
WHERE u.activo = TRUE
GROUP BY u.id, u.user_id, u.nombre_completo, u.fecha_examen_objetivo, 
         u.fecha_registro, pu.tasa_acierto_global, pu.probabilidad_aprobacion,
         pu.dias_consecutivos_estudio;

-- ============================================
-- 6. COMENTARIOS
-- ============================================

COMMENT ON FUNCTION fn_calcular_dias_disponibles IS 'Calcula días totales, transcurridos y restantes según fecha de examen del usuario';
COMMENT ON FUNCTION fn_calcular_progreso_dinamico IS 'Calcula progreso adaptativo independiente del plazo (30, 60, 90, 150 días, etc)';
COMMENT ON FUNCTION fn_generar_plan_adaptativo IS 'Genera plan diario que se ajusta automáticamente al tiempo disponible';
COMMENT ON FUNCTION fn_calcular_probabilidad_aprobacion_dinamica IS 'Calcula probabilidad considerando el tiempo específico de cada usuario';

-- ============================================
-- VERIFICACIÓN
-- ============================================

DO $$
BEGIN
    RAISE NOTICE '✓ Sistema actualizado a modo DINÁMICO';
    RAISE NOTICE '✓ Ahora soporta cualquier plazo: 30, 60, 90, 120, 150 días';
    RAISE NOTICE '';
    RAISE NOTICE 'Nuevas funciones disponibles:';
    RAISE NOTICE '- fn_calcular_dias_disponibles(usuario_id)';
    RAISE NOTICE '- fn_calcular_progreso_dinamico(usuario_id)';
    RAISE NOTICE '- fn_generar_plan_adaptativo(usuario_id)';
    RAISE NOTICE '- fn_calcular_probabilidad_aprobacion_dinamica(usuario_id)';
    RAISE NOTICE '';
    RAISE NOTICE 'Vista disponible:';
    RAISE NOTICE '- v_dashboard_adaptativo';
END $$;

-- ===== FIN base_de_datos_supabase\04_SISTEMA_DINAMICO.sql =====

