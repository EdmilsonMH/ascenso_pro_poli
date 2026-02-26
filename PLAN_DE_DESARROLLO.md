# Plan de Desarrollo: Ascenso PNP - App Móvil

Este documento define la estructura, funcionales y arquitectura de la aplicación móvil para la preparación de exámenes de ascenso de la PNP.

## 1. Visión del Producto
Una aplicación móvil premium, intuitiva y eficaz que permite a Oficiales y Suboficiales de la PNP prepararse para sus exámenes de ascenso mediante simulacros, estudio por materias y seguimiento de estadísticas.

## 2. Estructura de Usuarios
- **Perfiles**:
  - **Oficiales PNP**: Acceso a banco de preguntas de gestión, leyes avanzadas, etc.
  - **Suboficiales PNP**: Acceso a banco de preguntas operativo, normas específicas, etc.
- **Datos**: Nombre, Grado (opcional), Unidad (opcional), Correo.

## 3. Módulos Principales

### A. Módulo de Autenticación (Listo ✅)
- Login / Registro.
- Selección de Categoría (Oficial/Suboficial) que adapta el contenido.

### B. Módulo de Estudio (El Núcleo)
Este es el corazón de la app. Debe tener varios modos:
1.  **Modo Práctica Rápida**: 10, 20 o 50 preguntas aleatorias.
2.  **Modo Por Materias**: El usuario elige "Derecho Penal" o "Constitución" para estudiar un tema específico.
3.  **Modo Simulacro**: 100 preguntas con temporizador (120 min), simulando el examen real.
4.  **Buscador**: Buscar preguntas específicas por palabras clave.

**Características de la Pantalla de Pregunta:**
- **Texto de la pregunta** claro y legible.
- **Alternativas (A, B, C, D, E)** seleccionables.
- **Feedback Inmediato** (en modo práctica): Color verde/rojo al instante.
- **Explicación**: Texto detallando por qué es la respuesta correcta (aparece tras responder).
- **Audio**: Botón para escuchar la pregunta y respuesta (Accesibilidad/Estudio en movimiento).

### C. Módulo de Estadísticas y Progreso
- **Dashboard**: Resumen visual (Donut chart o Bar chart) de respuestas correctas vs incorrectas.
- **Por Materia**: Ver en qué materias falla más el usuario para recomendar estudio.
- **Historial**: Lista de simulacros pasados con notas y fechas.

### D. Módulo de Ranking y Competencia
- **Tabla de Posiciones**: Top 10 o Top 100 usuarios (General o por Categoría).
- **Mi Posición**: Dónde estoy yo respecto a los demás.
- **Insignias**: (Opcional) "Experto en DDHH", "Racha de 7 días", etc.

## 4. Arquitectura de Datos (Preguntas para definir)

Para que la app funcione, necesitamos definir de dónde vienen los datos.
**Opciones:**
1.  **100% Offline**: Las preguntas vienen dentro de la app (un archivo JSON o base de datos local). No requiere internet para practicar.
2.  **Híbrido (Recomendado)**: Las preguntas están en la nube (Firebase/Supabase) y se descargan al celular. Permite actualizar preguntas sin actualizar la app en la tienda.

**Modelo de Datos (Ejemplo de una Pregunta):**
```json
{
  "id": "p001",
  "texto": "¿Cuál es el artículo...?",
  "materia": "Derecho Constitucional",
  "categoria": ["Oficiales", "Suboficiales"],
  "opciones": [
    {"id": "A", "texto": "Artículo 1º"},
    {"id": "B", "texto": "Artículo 2º"}
  ],
  "respuestaCorrecta": "A",
  "explicacion": "El artículo 1 establece...",
  "audioUrl": "https://..."
}
```

## 5. Próximos Pasos Técnicos
1.  **Definir la Base de Datos**: Elegir Firebase (Nube) o SQLite (Local) para guardar las preguntas.
2.  **Diseñar la Pantalla "Realizar Práctica"**: Crear la UI para responder preguntas.
3.  **Implementar la Lógica de "Examen"**: Controlar aciertos, fallos y tiempo.
