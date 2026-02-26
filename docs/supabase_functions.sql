-- =====================================================
-- FUNCIÓN PARA OBTENER PREGUNTAS ALEATORIAS
-- Ejecutar en SQL Editor de Supabase
-- =====================================================

CREATE OR REPLACE FUNCTION obtener_preguntas_aleatorias(
    cantidad INT,
    materias_ids UUID[] DEFAULT NULL,
    categoria_filtro TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    numero INT,
    texto TEXT,
    opcion_a TEXT,
    opcion_b TEXT,
    opcion_c TEXT,
    opcion_d TEXT,
    respuesta_correcta CHAR(1),
    explicacion TEXT,
    materia_id UUID,
    materia_nombre TEXT,
    categoria TEXT,
    dificultad TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.numero,
        p.texto,
        p.opcion_a,
        p.opcion_b,
        p.opcion_c,
        p.opcion_d,
        p.respuesta_correcta,
        p.explicacion,
        p.materia_id,
        m.nombre as materia_nombre,
        p.categoria,
        p.dificultad
    FROM preguntas p
    LEFT JOIN materias m ON m.id = p.materia_id
    WHERE p.activo = true
        AND (materias_ids IS NULL OR p.materia_id = ANY(materias_ids))
        AND (
            categoria_filtro IS NULL 
            OR p.categoria = categoria_filtro 
            OR p.categoria = 'Ambos'
        )
    ORDER BY RANDOM()
    LIMIT cantidad;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCIÓN PARA ESTADÍSTICAS DEL USUARIO
-- =====================================================

CREATE OR REPLACE FUNCTION obtener_estadisticas_usuario(user_id UUID)
RETURNS TABLE (
    total_respondidas BIGINT,
    total_correctas BIGINT,
    total_incorrectas BIGINT,
    porcentaje_aciertos DECIMAL,
    racha_actual INT,
    mejor_racha INT,
    total_sesiones BIGINT,
    tiempo_total_estudio INT,
    puntos_totales INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.preguntas_respondidas::BIGINT,
        u.preguntas_correctas::BIGINT,
        (u.preguntas_respondidas - u.preguntas_correctas)::BIGINT,
        CASE 
            WHEN u.preguntas_respondidas > 0 
            THEN ROUND((u.preguntas_correctas::DECIMAL / u.preguntas_respondidas) * 100, 2)
            ELSE 0 
        END,
        u.racha_dias,
        u.racha_dias, -- Por ahora igual, se puede agregar mejor_racha a la tabla
        (SELECT COUNT(*) FROM sesiones_practica sp WHERE sp.usuario_id = user_id AND sp.completada = true),
        COALESCE((SELECT SUM(tiempo_total_segundos) FROM sesiones_practica sp WHERE sp.usuario_id = user_id), 0)::INT,
        u.puntos_totales
    FROM usuarios u
    WHERE u.id = user_id;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCIÓN PARA ACTUALIZAR RACHA DIARIA
-- =====================================================

CREATE OR REPLACE FUNCTION actualizar_racha_usuario()
RETURNS TRIGGER AS $$
DECLARE
    ultimo_dia DATE;
    racha_actual INT;
BEGIN
    SELECT ultimo_estudio, racha_dias INTO ultimo_dia, racha_actual
    FROM usuarios WHERE id = NEW.usuario_id;
    
    IF ultimo_dia IS NULL THEN
        -- Primera vez estudiando
        UPDATE usuarios SET racha_dias = 1, ultimo_estudio = CURRENT_DATE 
        WHERE id = NEW.usuario_id;
    ELSIF ultimo_dia = CURRENT_DATE - INTERVAL '1 day' THEN
        -- Día consecutivo
        UPDATE usuarios SET racha_dias = racha_dias + 1, ultimo_estudio = CURRENT_DATE 
        WHERE id = NEW.usuario_id;
    ELSIF ultimo_dia < CURRENT_DATE - INTERVAL '1 day' THEN
        -- Perdió la racha
        UPDATE usuarios SET racha_dias = 1, ultimo_estudio = CURRENT_DATE 
        WHERE id = NEW.usuario_id;
    END IF;
    -- Si es el mismo día, no hace nada
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger para actualizar racha (solo en primera respuesta del día)
CREATE OR REPLACE TRIGGER trigger_actualizar_racha
AFTER INSERT ON respuestas_usuario
FOR EACH ROW
EXECUTE FUNCTION actualizar_racha_usuario();

-- =====================================================
-- FUNCIÓN PARA PREGUNTAS NO RESPONDIDAS
-- =====================================================

CREATE OR REPLACE FUNCTION obtener_preguntas_no_respondidas(
    user_id UUID,
    cantidad INT DEFAULT 50,
    materias_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    numero INT,
    texto TEXT,
    opcion_a TEXT,
    opcion_b TEXT,
    opcion_c TEXT,
    opcion_d TEXT,
    respuesta_correcta CHAR(1),
    explicacion TEXT,
    materia_id UUID,
    materia_nombre TEXT,
    categoria TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.numero,
        p.texto,
        p.opcion_a,
        p.opcion_b,
        p.opcion_c,
        p.opcion_d,
        p.respuesta_correcta,
        p.explicacion,
        p.materia_id,
        m.nombre,
        p.categoria
    FROM preguntas p
    LEFT JOIN materias m ON m.id = p.materia_id
    WHERE p.activo = true
        AND (materias_ids IS NULL OR p.materia_id = ANY(materias_ids))
        AND NOT EXISTS (
            SELECT 1 FROM respuestas_usuario r 
            WHERE r.pregunta_id = p.id AND r.usuario_id = user_id
        )
    ORDER BY RANDOM()
    LIMIT cantidad;
END;
$$ LANGUAGE plpgsql;
