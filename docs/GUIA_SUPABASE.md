# 📚 Guía para Subir 5000 Preguntas a Supabase

## 1. Configuración de Supabase

### Paso 1: Crear proyecto en Supabase
1. Ve a [supabase.com](https://supabase.com)
2. Crea una cuenta o inicia sesión
3. Click en "New Project"
4. Nombra tu proyecto: `ascenso-pro-poli`
5. Elige una contraseña segura para la base de datos
6. Selecciona la región más cercana (ej: South America - São Paulo)

### Paso 2: Crear las tablas

Ve a **SQL Editor** en Supabase y ejecuta este script:

```sql
-- =====================================================
-- TABLA DE MATERIAS
-- =====================================================
CREATE TABLE materias (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nombre TEXT NOT NULL UNIQUE,
    descripcion TEXT,
    icono TEXT DEFAULT 'book',
    color TEXT DEFAULT '#3B82F6',
    orden INT DEFAULT 0,
    activo BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índice para búsquedas rápidas
CREATE INDEX idx_materias_nombre ON materias(nombre);

-- =====================================================
-- TABLA DE PREGUNTAS (5000+ preguntas)
-- =====================================================
CREATE TABLE preguntas (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    numero INT NOT NULL, -- Número secuencial para ordenar
    texto TEXT NOT NULL,
    opcion_a TEXT NOT NULL,
    opcion_b TEXT NOT NULL,
    opcion_c TEXT NOT NULL,
    opcion_d TEXT NOT NULL,
    respuesta_correcta CHAR(1) NOT NULL CHECK (respuesta_correcta IN ('A', 'B', 'C', 'D')),
    explicacion TEXT,
    materia_id UUID REFERENCES materias(id) ON DELETE SET NULL,
    categoria TEXT NOT NULL CHECK (categoria IN ('Oficiales', 'Suboficiales', 'Ambos')),
    dificultad TEXT DEFAULT 'Media' CHECK (dificultad IN ('Fácil', 'Media', 'Difícil')),
    activo BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices para optimizar consultas
CREATE INDEX idx_preguntas_materia ON preguntas(materia_id);
CREATE INDEX idx_preguntas_categoria ON preguntas(categoria);
CREATE INDEX idx_preguntas_numero ON preguntas(numero);
CREATE INDEX idx_preguntas_activo ON preguntas(activo);

-- =====================================================
-- TABLA DE USUARIOS
-- =====================================================
CREATE TABLE usuarios (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    nombre_completo TEXT,
    categoria TEXT CHECK (categoria IN ('Oficiales', 'Suboficiales')),
    rol TEXT DEFAULT 'usuario' CHECK (rol IN ('usuario', 'admin')), -- admin o usuario
    plan TEXT DEFAULT 'free' CHECK (plan IN ('free', 'premium')),
    fecha_premium_inicio TIMESTAMP WITH TIME ZONE,
    fecha_premium_fin TIMESTAMP WITH TIME ZONE,
    codigo_referido TEXT UNIQUE,
    referido_por UUID REFERENCES usuarios(id),
    puntos_totales INT DEFAULT 0,
    preguntas_respondidas INT DEFAULT 0,
    preguntas_correctas INT DEFAULT 0,
    racha_dias INT DEFAULT 0,
    ultimo_estudio DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================================
-- TABLA DE RESPUESTAS DEL USUARIO
-- =====================================================
CREATE TABLE respuestas_usuario (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    usuario_id UUID REFERENCES usuarios(id) ON DELETE CASCADE,
    pregunta_id UUID REFERENCES preguntas(id) ON DELETE CASCADE,
    respuesta_seleccionada CHAR(1) NOT NULL,
    es_correcta BOOLEAN NOT NULL,
    tiempo_respuesta_segundos INT,
    sesion_id UUID, -- Para agrupar por sesión de práctica
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Evitar duplicados en la misma sesión
    UNIQUE(usuario_id, pregunta_id, sesion_id)
);

CREATE INDEX idx_respuestas_usuario ON respuestas_usuario(usuario_id);
CREATE INDEX idx_respuestas_pregunta ON respuestas_usuario(pregunta_id);
CREATE INDEX idx_respuestas_sesion ON respuestas_usuario(sesion_id);

-- =====================================================
-- TABLA DE SESIONES DE PRÁCTICA
-- =====================================================
CREATE TABLE sesiones_practica (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    usuario_id UUID REFERENCES usuarios(id) ON DELETE CASCADE,
    total_preguntas INT NOT NULL,
    preguntas_correctas INT DEFAULT 0,
    preguntas_incorrectas INT DEFAULT 0,
    tiempo_total_segundos INT,
    materias_ids UUID[], -- Array de materias practicadas
    completada BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    finished_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_sesiones_usuario ON sesiones_practica(usuario_id);

-- =====================================================
-- VISTA PARA RANKING
-- =====================================================
CREATE VIEW ranking_usuarios AS
SELECT 
    u.id,
    u.nombre_completo,
    u.categoria,
    u.puntos_totales,
    u.preguntas_respondidas,
    u.preguntas_correctas,
    CASE 
        WHEN u.preguntas_respondidas > 0 
        THEN ROUND((u.preguntas_correctas::DECIMAL / u.preguntas_respondidas) * 100, 1)
        ELSE 0 
    END as porcentaje_aciertos,
    u.racha_dias,
    ROW_NUMBER() OVER (ORDER BY u.puntos_totales DESC) as posicion
FROM usuarios u
WHERE u.preguntas_respondidas > 0
ORDER BY u.puntos_totales DESC;

-- =====================================================
-- FUNCIÓN PARA ACTUALIZAR ESTADÍSTICAS
-- =====================================================
CREATE OR REPLACE FUNCTION actualizar_estadisticas_usuario()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE usuarios
    SET 
        preguntas_respondidas = preguntas_respondidas + 1,
        preguntas_correctas = preguntas_correctas + CASE WHEN NEW.es_correcta THEN 1 ELSE 0 END,
        puntos_totales = puntos_totales + CASE WHEN NEW.es_correcta THEN 10 ELSE 0 END,
        ultimo_estudio = CURRENT_DATE,
        updated_at = NOW()
    WHERE id = NEW.usuario_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_actualizar_estadisticas
AFTER INSERT ON respuestas_usuario
FOR EACH ROW
EXECUTE FUNCTION actualizar_estadisticas_usuario();

-- =====================================================
-- POLÍTICAS DE SEGURIDAD (RLS)
-- =====================================================
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE respuestas_usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE sesiones_practica ENABLE ROW LEVEL SECURITY;
ALTER TABLE preguntas ENABLE ROW LEVEL SECURITY;
ALTER TABLE materias ENABLE ROW LEVEL SECURITY;

-- Preguntas: Todos pueden leer
CREATE POLICY "Preguntas visibles para todos" ON preguntas
    FOR SELECT USING (activo = true);

-- Materias: Todos pueden leer
CREATE POLICY "Materias visibles para todos" ON materias
    FOR SELECT USING (activo = true);

-- Usuarios: Solo pueden ver/editar su propio perfil
CREATE POLICY "Usuarios pueden ver su perfil" ON usuarios
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Usuarios pueden actualizar su perfil" ON usuarios
    FOR UPDATE USING (auth.uid() = id);

-- Respuestas: Solo pueden ver/crear sus propias respuestas
CREATE POLICY "Usuarios pueden ver sus respuestas" ON respuestas_usuario
    FOR SELECT USING (auth.uid() = usuario_id);

CREATE POLICY "Usuarios pueden crear respuestas" ON respuestas_usuario
    FOR INSERT WITH CHECK (auth.uid() = usuario_id);

-- Sesiones: Solo pueden ver/crear sus propias sesiones
CREATE POLICY "Usuarios pueden ver sus sesiones" ON sesiones_practica
    FOR SELECT USING (auth.uid() = usuario_id);

CREATE POLICY "Usuarios pueden crear sesiones" ON sesiones_practica
    FOR INSERT WITH CHECK (auth.uid() = usuario_id);

CREATE POLICY "Usuarios pueden actualizar sus sesiones" ON sesiones_practica
    FOR UPDATE USING (auth.uid() = usuario_id);
```

---

## 2. Formato para las 5000 Preguntas

### Opción A: Archivo CSV (Recomendado para Excel)

Crea un archivo `preguntas.csv` con este formato:

```csv
numero,texto,opcion_a,opcion_b,opcion_c,opcion_d,respuesta_correcta,explicacion,materia,categoria,dificultad
1,"¿Cuál es el artículo de la Constitución que establece la defensa de la persona?","Artículo 1º","Artículo 2º","Artículo 3º","Artículo 44º",A,"El Artículo 1º establece que la defensa de la persona humana es el fin supremo.","Derecho Constitucional",Ambos,Media
2,"¿Quién es el Jefe Supremo de las FF.AA. y PNP?","Ministro del Interior","Comandante General","Presidente de la República","Presidente del Congreso",C,"Según la Constitución, el Presidente es el Jefe Supremo.","Derecho Constitucional",Ambos,Fácil
```

### Opción B: Archivo JSON

```json
[
  {
    "numero": 1,
    "texto": "¿Cuál es el artículo de la Constitución que establece la defensa de la persona?",
    "opcion_a": "Artículo 1º",
    "opcion_b": "Artículo 2º",
    "opcion_c": "Artículo 3º",
    "opcion_d": "Artículo 44º",
    "respuesta_correcta": "A",
    "explicacion": "El Artículo 1º establece que la defensa de la persona humana es el fin supremo.",
    "materia": "Derecho Constitucional",
    "categoria": "Ambos",
    "dificultad": "Media"
  }
]
```

---

## 3. Subir Preguntas Masivamente

### Método 1: Usando el Dashboard de Supabase (Hasta 500 registros)

1. Ve a **Table Editor** → **preguntas**
2. Click en **Insert** → **Import data from CSV**
3. Sube tu archivo CSV

### Método 2: Script SQL para inserción masiva

Primero, inserta las materias:

```sql
INSERT INTO materias (nombre, descripcion, orden) VALUES
('Derecho Constitucional', 'Constitución Política del Perú', 1),
('Derecho Procesal Penal', 'Código Procesal Penal', 2),
('Derecho Penal', 'Código Penal y delitos', 3),
('Derechos Humanos', 'Tratados y convenios internacionales', 4),
('Función Policial', 'Ley de la PNP y reglamentos', 5),
('Ética Policial', 'Código de ética y conducta', 6),
('Criminalística', 'Técnicas de investigación', 7),
('Orden Público', 'Mantenimiento del orden', 8);
```

### Método 3: Script Python para subir 5000 preguntas

Crea un archivo `subir_preguntas.py`:

```python
import csv
import json
from supabase import create_client, Client

# Configuración de Supabase
SUPABASE_URL = "https://TU_PROYECTO.supabase.co"
SUPABASE_KEY = "TU_ANON_KEY"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def cargar_materias():
    """Carga las materias y retorna un diccionario nombre -> id"""
    response = supabase.table("materias").select("id, nombre").execute()
    return {m["nombre"]: m["id"] for m in response.data}

def subir_preguntas_csv(archivo_csv: str):
    """Sube preguntas desde un archivo CSV"""
    materias = cargar_materias()
    
    with open(archivo_csv, 'r', encoding='utf-8') as file:
        reader = csv.DictReader(file)
        preguntas = []
        
        for i, row in enumerate(reader):
            materia_id = materias.get(row['materia'])
            
            pregunta = {
                "numero": int(row['numero']),
                "texto": row['texto'],
                "opcion_a": row['opcion_a'],
                "opcion_b": row['opcion_b'],
                "opcion_c": row['opcion_c'],
                "opcion_d": row['opcion_d'],
                "respuesta_correcta": row['respuesta_correcta'].upper(),
                "explicacion": row.get('explicacion', ''),
                "materia_id": materia_id,
                "categoria": row['categoria'],
                "dificultad": row.get('dificultad', 'Media'),
                "activo": True
            }
            preguntas.append(pregunta)
            
            # Insertar en lotes de 500 para mejor rendimiento
            if len(preguntas) >= 500:
                print(f"Subiendo lote... ({i+1} preguntas procesadas)")
                supabase.table("preguntas").insert(preguntas).execute()
                preguntas = []
        
        # Subir las restantes
        if preguntas:
            print(f"Subiendo último lote... ({len(preguntas)} preguntas)")
            supabase.table("preguntas").insert(preguntas).execute()
    
    print("✅ Todas las preguntas han sido subidas!")

if __name__ == "__main__":
    subir_preguntas_csv("preguntas.csv")
```

Ejecutar:
```bash
pip install supabase
python subir_preguntas.py
```

---

## 4. Obtener las credenciales de Supabase

1. Ve a tu proyecto en Supabase
2. Click en **Settings** (⚙️) → **API**
3. Copia:
   - **Project URL**: `https://xxxxx.supabase.co`
   - **anon public key**: `eyJhbGciOiJIUzI1...`

---

## 5. Verificar la carga

```sql
-- Contar preguntas por materia
SELECT m.nombre, COUNT(p.id) as total_preguntas
FROM materias m
LEFT JOIN preguntas p ON p.materia_id = m.id
GROUP BY m.nombre
ORDER BY total_preguntas DESC;

-- Contar total de preguntas
SELECT COUNT(*) as total FROM preguntas WHERE activo = true;

-- Ver distribución por categoría
SELECT categoria, COUNT(*) as total 
FROM preguntas 
GROUP BY categoria;
```

---

## 📝 Plantilla Excel para las Preguntas

| numero | texto | opcion_a | opcion_b | opcion_c | opcion_d | respuesta_correcta | explicacion | materia | categoria | dificultad |
|--------|-------|----------|----------|----------|----------|-------------------|-------------|---------|-----------|------------|
| 1 | ¿Pregunta aquí? | Opción A | Opción B | Opción C | Opción D | A | Explicación... | Derecho Constitucional | Ambos | Media |
| 2 | ¿Otra pregunta? | ... | ... | ... | ... | B | ... | Derecho Penal | Oficiales | Difícil |

**Guardar como CSV (UTF-8) para importar.**
