o # 🤖 IA TUTOR - FUNCIONES COMPLETAS

## Con las 27 tablas + 11 funciones + 4 triggers de tu base de datos

---

## 📊 RESUMEN EJECUTIVO

El **IA Tutor** puede realizar **50+ funciones inteligentes** agrupadas en:

✅ **10 Funciones de Análisis** - Diagnosticar al estudiante  
✅ **10 Funciones de Predicción** - Predecir resultados  
✅ **10 Funciones de Recomendación** - Sugerir acciones  
✅ **10 Funciones de Detección** - Identificar problemas  
✅ **5 Funciones de Coaching** - Motivar y guiar  
✅ **5 Funciones de Personalización** - Adaptar al usuario  

---

**Actualización (Sistema Dinámico):** al ejecutar `04_SISTEMA_DINAMICO.sql` se agregan 4 funciones para adaptar el plan a cualquier plazo:
- `fn_calcular_dias_disponibles`
- `fn_calcular_progreso_dinamico`
- `fn_generar_plan_adaptativo`
- `fn_calcular_probabilidad_aprobacion_dinamica`

---

## 🎯 CATEGORÍA 1: ANÁLISIS DEL ESTUDIANTE (10 funciones)

### 1.1 📊 Análisis Completo del Perfil

**Qué hace:**
Analiza el perfil completo del usuario y genera un diagnóstico

**Tablas que usa:**
- `perfil_usuario`
- `dominio_materia`
- `exposicion_pregunta`
- `respuesta_usuario`

**Código:**
```dart
Future<Map<String, dynamic>> analizarPerfilCompleto(String userId) async {
  // 1. Obtener perfil
  final perfil = await supabase
    .from('perfil_usuario')
    .select('*')
    .eq('usuario_id', userId)
    .single();
  
  // 2. Obtener dominio por materia
  final dominios = await supabase
    .from('dominio_materia')
    .select('*, materia(*)')
    .eq('usuario_id', userId);
  
  // 3. Calcular estadísticas avanzadas
  final totalDominadas = await supabase
    .from('exposicion_pregunta')
    .select('id')
    .eq('usuario_id', userId)
    .eq('estado_dominio', 'dominada')
    .count();
  
  return {
    'nivel_global': _calcularNivelGlobal(perfil),
    'fortalezas': _identificarFortalezas(dominios),
    'debilidades': _identificarDebilidades(dominios),
    'materias_criticas': _obtenerMateriasCriticas(dominios),
    'preguntas_dominadas': totalDominadas,
    'tasa_acierto': perfil['tasa_acierto_global'],
    'velocidad_promedio': perfil['velocidad_promedio_segundos'],
    'diagnostico': _generarDiagnostico(perfil, dominios),
  };
}
```

**Resultado (UI):**
```
📊 Análisis de tu Perfil

Derechos Humanos: INTERMEDIO
━━━━━━━━━━░░░░░  60%

✅ Fortalezas:
• Constitución Política (88%)
• Derechos Humanos (85%)
• Buena velocidad (12 seg/preg)
• Racha de 7 días

⚠️ Áreas de Mejora:
• Código Penal (42%) - CRÍTICO
• Ley PNP (55%) - Básico
• Tendencia a impulsividad (32%)

📈 Progreso:
• 1,250/3000 preguntas dominadas
• Tasa de acierto: 82%
• Tiempo estudiado: 45h 30min

💡 Diagnóstico:
"Vas bien en general, pero debes
 enfocarte en Código Penal. Te
 recomiendo 30 min/día en esta
 materia durante 2 semanas."
```

---

### 1.2 🎯 Análisis Post-Sesión

**Qué hace:**
Después de cada práctica, analiza cómo le fue

**Tablas que usa:**
- `sesion_practica`
- `respuesta_usuario`

**Código:**
```dart
Future<Map<String, dynamic>> analizarSesion(String sesionId) async {
  // 1. Obtener sesión
  final sesion = await supabase
    .from('sesion_practica')
    .select('*')
    .eq('id', sesionId)
    .single();
  
  // 2. Obtener todas las respuestas
  final respuestas = await supabase
    .from('respuesta_usuario')
    .select('*')
    .eq('sesion_id', sesionId);
  
  // 3. Análisis detallado
  return {
    'rendimiento_general': sesion['tasa_acierto'],
    'comparacion_promedio': _compararConPromedio(sesion),
    'materias_bien': _materiasBien(respuestas),
    'materias_mal': _materiasMal(respuestas),
    'velocidad_analisis': _analizarVelocidad(respuestas),
    'patrones_detectados': _detectarPatrones(respuestas),
    'errores_criticos': _identificarErroresCriticos(respuestas),
    'recomendaciones': _generarRecomendaciones(respuestas),
  };
}
```

**Resultado (UI):**
```
📊 Análisis de Sesión

Simulacro 100 preguntas
85/100 correctas (85%) ✅

━━━━━━━━━━━━━━━━━━━━━━━━

📈 Destacado:
• Mejoraste 15% vs anterior sesión
• 40% más rápido que tu promedio
• Cero errores de impulsividad
• Racha de 10 correctas consecutivas

⚠️ Áreas de Mejora:
• Código Penal: 5/8 incorrectas
  → Artículos 185-190 necesitan repaso
• 3 errores por no leer "excepto"
• Fatiga detectada en pregunta 85+

🔍 Patrones Detectados:
• Confundes Art. 185 y 186
• Respondes mejor en la mañana
• Cambias de respuesta 2+ veces
  cuando no estás seguro

💡 Recomendaciones:
1. Dedica 20 min a estudiar hurto
2. Lee 2 veces las preguntas largas
3. Descansa cada 80 preguntas
4. Repasa artículos consecutivos

🎯 Próximos Pasos:
[Repasar Código Penal]
[Ver errores en detalle]
```

---

### 1.3 📚 Análisis por Materia

**Qué hace:**
Analiza en profundidad una materia específica

**Tablas que usa:**
- `dominio_materia`
- `exposicion_pregunta`
- `respuesta_usuario`

**Código:**
```dart
Future<Map<String, dynamic>> analizarMateria(
  String userId, 
  String materiaId
) async {
  // 1. Dominio general
  final dominio = await supabase
    .from('dominio_materia')
    .select('*')
    .eq('usuario_id', userId)
    .eq('materia_id', materiaId)
    .single();
  
  // 2. Preguntas de esta materia
  final exposiciones = await supabase
    .from('exposicion_pregunta')
    .select('*, pregunta!inner(*)')
    .eq('usuario_id', userId)
    .eq('pregunta.materia_id', materiaId);
  
  // 3. Análisis detallado
  final noDominadas = exposiciones
    .where((e) => e['estado_dominio'] != 'dominada')
    .length;
  
  final criticas = exposiciones
    .where((e) => e['necesita_atencion_especial'] == true)
    .length;
  
  return {
    'tasa_dominio': dominio['tasa_dominio_actual'],
    'nivel': dominio['nivel_dominio_texto'],
    'total_vistas': dominio['total_preguntas_vistas'],
    'preguntas_dominadas': dominio['preguntas_dominadas'],
    'preguntas_pendientes': noDominadas,
    'preguntas_criticas': criticas,
    'tendencia': dominio['tendencia_ultimos_7_dias'],
    'tiempo_recomendado': dominio['tiempo_recomendado_minutos'],
    'temas_debiles': dominio['temas_debiles'],
  };
}
```

**Resultado (UI):**
```
📚 Análisis: Código Penal

Estado General:
🔴 CRÍTICO (42%)

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Progreso:
Vistas:     280/500 (56%)
Dominadas:  118/280 (42%)
Pendientes: 162
Críticas:   45 ⚠️

📈 Tendencia: Estable ━

━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ Temas Débiles:
• Hurto y Robo (Arts. 185-190)
• Lesiones (Arts. 121-125)
• Falsificación (Arts. 427-438)

💡 Recomendación:
Dedica 30 min/día durante 14 días

📅 Plan Sugerido:
• Días 1-5: Hurto y Robo
• Días 6-10: Lesiones
• Días 11-14: Falsificación

⏱️ Tiempo estimado para dominar:
14 días con 30 min/día

[Empezar Plan de Código Penal]
```

---

### 1.4 ⏱️ Análisis de Velocidad

**Qué hace:**
Analiza si responde muy rápido, muy lento o perfecto

**Tablas que usa:**
- `respuesta_usuario`
- `perfil_usuario`

**Código:**
```dart
Future<Map<String, dynamic>> analizarVelocidad(String userId) async {
  // Obtener todas las respuestas
  final respuestas = await supabase
    .from('respuesta_usuario')
    .select('tiempo_total_ms, es_correcta')
    .eq('usuario_id', userId)
    .order('created_at', ascending: false)
    .limit(100);
  
  // Calcular promedios
  final totalTiempo = respuestas.fold<int>(
    0, (sum, r) => sum + (r['tiempo_total_ms'] as int)
  );
  final promedio = totalTiempo / respuestas.length / 1000; // segundos
  
  // Detectar impulsividad (respuestas <5 seg)
  final impulsivas = respuestas.where(
    (r) => r['tiempo_total_ms'] < 5000
  ).length;
  
  final tasaImpulsividad = (impulsivas / respuestas.length) * 100;
  
  // Detectar lentitud (respuestas >30 seg)
  final lentas = respuestas.where(
    (r) => r['tiempo_total_ms'] > 30000
  ).length;
  
  final tasaLentitud = (lentas / respuestas.length) * 100;
  
  return {
    'velocidad_promedio': promedio,
    'tasa_impulsividad': tasaImpulsividad,
    'tasa_lentitud': tasaLentitud,
    'diagnostico': _diagnosticarVelocidad(promedio, tasaImpulsividad),
    'recomendacion': _recomendarVelocidad(promedio, tasaImpulsividad),
  };
}
```

**Resultado (UI):**
```
⏱️ Análisis de Velocidad

Tu velocidad promedio:
12 segundos/pregunta

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Distribución:
• <5 seg (impulsivas):   18% ⚠️
• 5-20 seg (normales):   70% ✅
• 20-30 seg (reflexivas): 10%
• >30 seg (lentas):       2%

━━━━━━━━━━━━━━━━━━━━━━━━

🎯 Diagnóstico:
Velocidad BUENA en general, pero
tienes tendencia a impulsividad
(18% de respuestas <5 seg)

⚠️ Problema detectado:
Cuando respondes en <5 seg,
tu tasa de error es 45%

✅ Cuando te tomas 10-15 seg,
tu tasa de error es solo 15%

💡 Recomendación:
Tómate al menos 8 segundos en
cada pregunta. Lee 2 veces antes
de seleccionar.

📈 Impacto estimado:
+12 puntos en el examen
```

---

### 1.5 🧠 Análisis Cognitivo

**Qué hace:**
Analiza patrones de pensamiento y comportamiento

**Tablas que usa:**
- `respuesta_usuario` (15+ variables)
- `patron_error_detallado`

**Código:**
```dart
Future<Map<String, dynamic>> analizarCognitivo(String userId) async {
  // 1. Obtener respuestas con tracking completo
  final respuestas = await supabase
    .from('respuesta_usuario')
    .select('''
      tiempo_primera_lectura_ms,
      tiempo_primera_seleccion_ms,
      numero_cambios_respuesta,
      veces_leyo_enunciado,
      confianza_usuario,
      es_correcta,
      momento_del_dia,
      posicion_en_sesion
    ''')
    .eq('usuario_id', userId)
    .limit(200);
  
  // 2. Análisis de patrones
  final cambiosPromedio = respuestas
    .fold<int>(0, (sum, r) => sum + (r['numero_cambios_respuesta'] as int))
    / respuestas.length;
  
  final relecturasPromedio = respuestas
    .fold<int>(0, (sum, r) => sum + (r['veces_leyo_enunciado'] as int))
    / respuestas.length;
  
  // 3. Rendimiento por momento
  final rendimientoManana = _calcularRendimiento(
    respuestas.where((r) => r['momento_del_dia'] == 'manana')
  );
  final rendimientoTarde = _calcularRendimiento(
    respuestas.where((r) => r['momento_del_dia'] == 'tarde')
  );
  final rendimientoNoche = _calcularRendimiento(
    respuestas.where((r) => r['momento_del_dia'] == 'noche')
  );
  
  return {
    'cambios_promedio': cambiosPromedio,
    'relecturas_promedio': relecturasPromedio,
    'mejor_horario': _identificarMejorHorario(
      rendimientoManana,
      rendimientoTarde,
      rendimientoNoche,
    ),
    'perfil_cognitivo': _determinarPerfil(cambiosPromedio, relecturasPromedio),
    'recomendaciones': _generarRecomendacionesCognitivas(),
  };
}
```

**Resultado (UI):**
```
🧠 Análisis Cognitivo

Tu Perfil: REFLEXIVO

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Patrones de Pensamiento:

Cambios de respuesta:
Promedio: 1.2 cambios
🟢 Normal (óptimo: 0.5-1.5)

Relecturas de enunciado:
Promedio: 2.3 veces
🟡 Algo alto (óptimo: 1-2)

Nivel de confianza:
Promedio: 3.8/5
🟢 Bueno

━━━━━━━━━━━━━━━━━━━━━━━━

🕐 Rendimiento por Horario:

🌅 Mañana (6am-12pm):   88% ⭐
🌆 Tarde (12pm-6pm):    75%
🌙 Noche (6pm-12am):    68%

Tu mejor horario: 8am-11am

━━━━━━━━━━━━━━━━━━━━━━━━

🎯 Diagnóstico:

Perfil: REFLEXIVO
• Piensas bien antes de responder
• Revisas tus respuestas (bueno)
• Relee mucho el enunciado (puede
  indicar inseguridad)

💡 Recomendaciones:
1. Confía más en tu primera lectura
2. Si ya entendiste, no releas tanto
3. Estudia entre 8am-11am siempre

📈 Impacto estimado:
+8 puntos reduciendo relecturas
```

---

### 1.6-1.10 Otros Análisis

**1.6 📈 Análisis de Evolución Temporal**
- Compara rendimiento actual vs hace 7, 30, 60 días
- Detecta si está mejorando o empeorando
- Muestra gráfico de progreso

**1.7 🎯 Análisis de Confianza**
- Analiza correlación entre confianza y acierto
- Detecta exceso de confianza o inseguridad
- Recomienda calibrar confianza

**1.8 📍 Análisis de Posición en Sesión**
- Detecta si rinde mejor al inicio, medio o final
- Identifica fatiga mental
- Recomienda descansos

**1.9 🔄 Análisis de Cambios de Respuesta**
- Analiza si cambiar ayuda o perjudica
- Detecta inseguridad vs reflexión
- Recomienda estrategia de cambios

**1.10 📚 Análisis de Uso de Recursos**
- Analiza si usa audio (TTS)
- Detecta si ayuda o distrae
- Recomienda uso óptimo

---

## 🎯 CATEGORÍA 2: PREDICCIONES (10 funciones)

### 2.1 🎯 Predicción de Aprobación del Examen

**Qué hace:**
Predice la probabilidad de aprobar el examen

**Función:** `fn_calcular_probabilidad_aprobacion_dinamica()`

**Tablas que usa:**
- `prediccion_examen`
- `exposicion_pregunta`
- `perfil_usuario`
- `dominio_materia`

**Algoritmo:**
```
Puntaje Estimado = (
  30% * preguntas_dominadas +
  25% * rendimiento_reciente +
  15% * velocidad_aprendizaje +
  10% * tiempo_restante +
  10% * racha_estudio +
  10% * tendencia
) - penalizacion_materias_debiles
```

**Código:**
```dart
Future<Map<String, dynamic>> predecirAprobacion(String userId) async {
  // Llamar función de Supabase
  final prediccion = await supabase.rpc(
    'fn_calcular_probabilidad_aprobacion_dinamica',
    params: {'p_usuario_id': userId}
  );
  
  return prediccion;
}
```

**Resultado (UI):**
```
🎯 Predictor de Aprobación

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Semana 8/10

Puntaje estimado:
78 ± 5 puntos

Probabilidad aprobación:
████████░░  85%

Nivel de confianza: 92%

━━━━━━━━━━━━━━━━━━━━━━━━

📈 Escenarios:

Optimista:   85 pts (96% aprobación)
Realista:    78 pts (85% aprobación) ⭐
Pesimista:   72 pts (75% aprobación)

━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ Materias en Riesgo:
• Código Penal (65%)
  → -8 puntos estimados

✅ Materias Seguras:
• Constitución (88%)
  → +12 puntos estimados
• DD.HH. (85%)
  → +10 puntos estimados

━━━━━━━━━━━━━━━━━━━━━━━━

💡 Plan de Acción:
"Si estudias Código Penal 30 min/día
durante 2 semanas, tu probabilidad
de aprobación subirá a 92%"

[Empezar Plan de Código Penal]
```

---

### 2.2 📅 Predicción de Tiempo para Dominar

**Qué hace:**
Predice cuánto tiempo falta para dominar las 3000

**Función:** `fn_calcular_progreso_dinamico()`

**Código:**
```dart
Future<Map<String, dynamic>> predecirTiempoRestante(String userId) async {
  final progreso = await supabase.rpc(
    'fn_calcular_progreso_dinamico',
    params: {'p_usuario_id': userId}
  );
  
  final preguntasFaltantes = 3000 - progreso['preguntas_dominadas'];
  final ritmoActual = progreso['ritmo_actual_dia'];
  
  final diasRestantes = (preguntasFaltantes / ritmoActual).ceil();
  final fechaEstimada = DateTime.now().add(Duration(days: diasRestantes));
  
  return {
    'dias_restantes': diasRestantes,
    'fecha_estimada': fechaEstimada,
    'probabilidad_cumplir': progreso['probabilidad_completar_3000'],
  };
}
```

**Resultado (UI):**
```
📅 Predicción de Tiempo

━━━━━━━━━━━━━━━━━━━━━━━━

Preguntas dominadas:
1,250 / 3,000 (42%)

Faltan: 1,750 preguntas

━━━━━━━━━━━━━━━━━━━━━━━━

Tu ritmo actual: 28/día

Con este ritmo:
⏰ 62 días restantes
📅 Fecha estimada: 7 Abril 2026

━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ Pero tu examen es: 5 Abril

Necesitas acelerar a: 39/día

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Probabilidades:

Si mantienes 28/día:  ❌ 35%
Si aceleras a 39/día: ✅ 85%
Si aceleras a 50/día: ✅ 95%

💡 Recomendación:
Aumenta tu ritmo a 40 preguntas
diarias para llegar con tiempo.
```

---

### 2.3 🔮 Predicción de Olvido

**Qué hace:**
Predice cuándo olvidará cada pregunta

**Tabla:** `prediccion_olvido`  
**Trigger:** Actualización automática

**Algoritmo de Ebbinghaus:**
```
Día 1:  40% probabilidad olvido
Día 2:  60% probabilidad olvido
Día 4:  75% probabilidad olvido
Día 8:  85% probabilidad olvido
Día 16: 92% probabilidad olvido
```

**Código:**
```dart
Future<List<Map>> predecirOlvidos(String userId) async {
  final predicciones = await supabase
    .from('prediccion_olvido')
    .select('*, pregunta(*)')
    .eq('usuario_id', userId)
    .gt('probabilidad_olvido', 75)
    .order('probabilidad_olvido', ascending: false);
  
  return predicciones;
}
```

**Resultado (UI):**
```
🔮 Predicción de Olvido

⚠️ 23 preguntas en riesgo

━━━━━━━━━━━━━━━━━━━━━━━━

🔴 Urgentes (15)

Pregunta CP-045:
"El hurto agravado..."

Prob. olvido: 🔴 85%
Última correcta: Hace 8 días
Estado: En consolidación
Urgencia: Revisar HOY

━━━━━━━━━━━━━━━━━━━━━━━━

Pregunta DDHH-122:
"La Declaración Universal..."

Prob. olvido: 🔴 78%
Última correcta: Hace 6 días
Estado: Frágil
Urgencia: Revisar HOY

━━━━━━━━━━━━━━━━━━━━━━━━

🟠 Próximas (8)
[Lista de preguntas...]

━━━━━━━━━━━━━━━━━━━━━━━━

💡 Recomendación:
Repasa las 15 urgentes hoy.
Te tomará ~20 minutos.

[Empezar Repaso Urgente]
```

---

### 2.4 📈 Predicción de Puntaje por Materia

**Qué hace:**
Predice cuántos puntos sacará en cada materia

**Código:**
```dart
Future<Map<String, double>> predecirPuntajePorMateria(String userId) async {
  final dominios = await supabase
    .from('dominio_materia')
    .select('*, materia(*)')
    .eq('usuario_id', userId);
  
  Map<String, double> puntajes = {};
  
  for (var dominio in dominios) {
    // En el examen cada materia vale ~17 puntos (100/6)
    final puntajeEstimado = (dominio['tasa_dominio_actual'] / 100) * 17;
    puntajes[dominio['materia']['nombre']] = puntajeEstimado;
  }
  
  return puntajes;
}
```

**Resultado (UI):**
```
📈 Puntaje Estimado por Materia

Total estimado: 78/100 puntos

━━━━━━━━━━━━━━━━━━━━━━━━

✅ Constitución:     15/17  88%
✅ DD.HH.:          14/17  85%
🟡 C.P.P.:          12/17  68%
🟡 Rég. Disc.:      12/17  72%
🟠 Ley PNP:          9/17  55%
🔴 Código Penal:     7/17  42% ⚠️

━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ Código Penal puede costarte
   10 puntos (15-7 = 8 pts perdidos)

💡 Si mejoras CP a 70%:
   Ganarías +5 puntos → 83 total

[Plan para Código Penal]
```

---

### 2.5-2.10 Otras Predicciones

**2.5 🎲 Predicción de Preguntas del Examen**
- Basado en `score_importancia` y `frecuencia_examen_real`
- Identifica las 100 más probables
- Prioriza estudio

**2.6 ⏱️ Predicción de Tiempo de Sesión**
- Predice cuánto tardará en X preguntas
- Basado en velocidad histórica
- Ajusta por dificultad

**2.7 📊 Predicción de Rendimiento Semanal**
- Predice cómo le irá esta semana
- Basado en tendencias
- Alerta si va a empeorar

**2.8 🎯 Predicción de Próximos Errores**
- Identifica preguntas que probablemente falle
- Basado en patrones similares
- Recomienda refuerzo

**2.9 📅 Predicción de Fecha Óptima de Examen**
- Calcula cuándo estará 100% preparado
- Considera velocidad de aprendizaje
- Recomienda si adelantar/retrasar

**2.10 🔮 Predicción de Racha**
- Predice si mantendrá la racha
- Basado en historial
- Envía recordatorios preventivos

---

## 🎯 CATEGORÍA 3: RECOMENDACIONES (10 funciones)

### 3.1 📅 Generación de Plan Diario

**Qué hace:**
Genera el plan de estudio del día

**Función:** `fn_generar_plan_adaptativo()`

**Código:**
```dart
Future<Map<String, dynamic>> generarPlanDiario(String userId) async {
  final plan = await supabase.rpc(
    'fn_generar_plan_adaptativo',
    params: {'p_usuario_id': userId}
  );
  
  return plan;
}
```

**Resultado (UI):**
```
📅 Plan del Día
Martes, 4 de Febrero

━━━━━━━━━━━━━━━━━━━━━━━━

🎯 Meta de Hoy:
50 preguntas | 75 minutos
Intensidad: 🔥 Intensivo

━━━━━━━━━━━━━━━━━━━━━━━━

📝 Preguntas Nuevas (30)
Priorizadas por importancia

• Código Penal (12)
  → Arts. 185-190 (hurto)
• DD.HH. (10)
  → Declaraciones internacionales
• Constitución (8)
  → Poderes del Estado

━━━━━━━━━━━━━━━━━━━━━━━━

🔄 Preguntas Repaso (20)
Spaced Repetition

• Urgentes (8)
  → Prob. olvido >75%
• Próximas (12)
  → Revisión óptima hoy

━━━━━━━━━━━━━━━━━━━━━━━━

💡 Mensaje del Tutor IA:

"Tienes 45 días restantes. Este
ritmo te llevará a 2,850 preguntas.
Necesitas acelerar ligeramente.
Aumenta a 55 preguntas/día para
llegar cómodo a las 3,000."

━━━━━━━━━━━━━━━━━━━━━━━━

[▶️ Comenzar Plan del Día]
[📊 Ver Dashboard 60 Días]
```

---

### 3.2 📚 Recomendación de Qué Estudiar

**Qué hace:**
Recomienda qué materias/temas estudiar

**Código:**
```dart
Future<Map<String, dynamic>> recomendarQueEstudiar(String userId) async {
  // 1. Obtener dominios
  final dominios = await supabase
    .from('dominio_materia')
    .select('*, materia(*)')
    .eq('usuario_id', userId)
    .order('prioridad_estudio', ascending: false);
  
  // 2. La más crítica primero
  final materiaCritica = dominios.first;
  
  // 3. Temas débiles de esa materia
  final temasDebiles = materiaCritica['temas_debiles'] as List;
  
  return {
    'materia_prioridad': materiaCritica['materia']['nombre'],
    'razon': 'Es tu materia más débil (${materiaCritica['tasa_dominio_actual']}%)',
    'temas_estudiar': temasDebiles,
    'tiempo_recomendado': materiaCritica['tiempo_recomendado_minutos'],
    'impacto_estimado': _calcularImpacto(materiaCritica),
  };
}
```

**Resultado (UI):**
```
📚 Qué Estudiar Hoy

━━━━━━━━━━━━━━━━━━━━━━━━

🎯 Prioridad #1:
CÓDIGO PENAL

¿Por qué?
Es tu materia más débil (42%)
Puede costarte 10 puntos en examen

━━━━━━━━━━━━━━━━━━━━━━━━

📖 Temas a Estudiar:

1. Hurto y Robo (Arts. 185-190)
   30 preguntas pendientes
   
2. Lesiones (Arts. 121-125)
   18 preguntas pendientes
   
3. Falsificación (Arts. 427-438)
   12 preguntas pendientes

━━━━━━━━━━━━━━━━━━━━━━━━

⏱️ Tiempo Recomendado:
30 minutos/día × 14 días

📈 Impacto Estimado:
Si mejoras CP de 42% a 70%:
+5 puntos en examen final

━━━━━━━━━━━━━━━━━━━━━━━━

[Empezar Plan de CP]
[Ver todas las prioridades]
```

---

### 3.3 ⏰ Recomendación de Horario de Estudio

**Qué hace:**
Recomienda la mejor hora para estudiar

**Tablas:** `respuesta_usuario` (momento_del_dia)

**Código:**
```dart
Future<Map<String, dynamic>> recomendarHorario(String userId) async {
  final respuestas = await supabase
    .from('respuesta_usuario')
    .select('momento_del_dia, es_correcta')
    .eq('usuario_id', userId);
  
  // Calcular rendimiento por momento
  final rendimientos = {
    'manana': _calcularRendimiento(
      respuestas.where((r) => r['momento_del_dia'] == 'manana')
    ),
    'tarde': _calcularRendimiento(
      respuestas.where((r) => r['momento_del_dia'] == 'tarde')
    ),
    'noche': _calcularRendimiento(
      respuestas.where((r) => r['momento_del_dia'] == 'noche')
    ),
  };
  
  // Encontrar el mejor
  final mejor = rendimientos.entries
    .reduce((a, b) => a.value > b.value ? a : b);
  
  return {
    'mejor_momento': mejor.key,
    'rendimiento': mejor.value,
    'recomendacion': _generarRecomendacionHorario(mejor.key),
  };
}
```

**Resultado (UI):**
```
⏰ Tu Mejor Horario

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Rendimiento por Horario:

🌅 Mañana (6am-12pm)
   Tasa acierto: 88% ⭐
   Velocidad: 12 seg
   Sesiones: 35

🌆 Tarde (12pm-6pm)
   Tasa acierto: 75%
   Velocidad: 15 seg
   Sesiones: 28

🌙 Noche (6pm-12am)
   Tasa acierto: 68%
   Velocidad: 18 seg
   Sesiones: 15

━━━━━━━━━━━━━━━━━━━━━━━━

💡 Recomendación:

Estudia en la MAÑANA (8am-11am)

Razones:
• +13% mejor rendimiento vs tarde
• +20% mejor rendimiento vs noche
• Más rápido y preciso
• Menos errores de impulsividad

📈 Impacto Estimado:
Si estudias siempre en la mañana:
+6 puntos en examen final

━━━━━━━━━━━━━━━━━━━━━━━━

[Configurar recordatorio 8am]
```

---

### 3.4-3.10 Otras Recomendaciones

**3.4 📊 Recomendación de Cantidad Diaria**
- Según días restantes y ritmo
- Ajusta por capacidad personal
- Balancea intensidad

**3.5 🎯 Recomendación de Tipo de Práctica**
- Simulacro vs práctica libre
- Por materia vs mixto
- Según necesidades

**3.6 🔄 Recomendación de Cuándo Repasar**
- Basado en Spaced Repetition
- Calcula momento óptimo
- Maximiza retención

**3.7 ⚡ Recomendación de Velocidad**
- Si va muy rápido: "Tómate tu tiempo"
- Si va muy lento: "Confía más, no releas tanto"
- Optimiza velocidad/precisión

**3.8 💪 Recomendación de Descansos**
- Detecta fatiga
- Sugiere pausas
- Previene agotamiento

**3.9 📱 Recomendación de Uso de Audio**
- Si ayuda o distrae
- Cuándo usarlo
- Velocidad óptima

**3.10 🎯 Recomendación de Metas**
- Metas realistas
- Ajustadas al progreso
- Alcanzables pero desafiantes

---

## 🎯 CATEGORÍA 4: DETECCIÓN DE PROBLEMAS (10 funciones)

### 4.1 🚨 Detección de Patrones de Error

**Qué hace:**
Detecta patrones recurrentes de error

**Función:** `fn_diagnosticar_tipo_error()`  
**Tabla:** `patron_error_detallado`

**Patrones detectables:**
1. **Impulsividad** - Responde <5 seg y falla
2. **Confusión de opciones** - Cambia >2 veces
3. **Desconocimiento** - Tiempo largo sin cambios y falla
4. **Error de lectura** - No lee "excepto", "no", "salvo"
5. **Confunde consecutivos** - Art. 185 vs 186
6. **Confunde plazos** - 24h vs 48h vs 72h

**Código:**
```dart
Future<List<Map>> detectarPatrones(String userId) async {
  final patrones = await supabase
    .from('patron_error_detallado')
    .select('*')
    .eq('usuario_id', userId)
    .eq('corregido', false)
    .order('gravedad', ascending: false);
  
  return patrones;
}
```

**Resultado (UI):**
```
🔍 Patrones de Error Detectados

━━━━━━━━━━━━━━━━━━━━━━━━

1. 🔴 Impulsividad
   Frecuencia: 35%
   Gravedad: GRAVE
   Puntos en riesgo: 15

   📊 Detalles:
   Respondes en <5 seg y fallas
   en 45% de estos casos
   
   📝 Estrategia:
   "Lee 2 veces antes de responder.
    Tómate al menos 8 segundos."
   
   📈 Tendencia: Mejorando ↗️

━━━━━━━━━━━━━━━━━━━━━━━━

2. 🟠 Confunde Arts. Consecutivos
   Frecuencia: 22%
   Gravedad: MODERADO
   Puntos en riesgo: 8
   
   📊 Ejemplos:
   • Art. 185 vs 186 (hurto)
   • Art. 121 vs 122 (lesiones)
   
   📝 Estrategia:
   "Crea tabla comparativa.
    Estudia diferencias clave."
   
   📈 Tendencia: Estable ━

━━━━━━━━━━━━━━━━━━━━━━━━

3. 🟡 Error de Lectura
   Frecuencia: 18%
   Gravedad: LEVE
   Puntos en riesgo: 5
   
   📊 Detalles:
   No lees palabras clave:
   "EXCEPTO", "NO", "SALVO"
   
   📝 Estrategia:
   "Subraya mentalmente estas
    palabras antes de leer opciones."
   
   📈 Tendencia: Mejorando ↗️

━━━━━━━━━━━━━━━━━━━━━━━━

💡 Plan de Corrección:
1. Dedica 1 semana a impulsividad
2. Crea tabla de artículos
3. Practica con palabras clave

📈 Impacto Total:
Corrigiendo estos 3 patrones:
+28 puntos estimados
```

---

### 4.2 ⚠️ Detección de Materias en Riesgo

**Qué hace:**
Identifica materias en peligro de reprobar

**Código:**
```dart
Future<List<Map>> detectarMateriasEnRiesgo(String userId) async {
  final materias = await supabase
    .from('dominio_materia')
    .select('*, materia(*)')
    .eq('usuario_id', userId)
    .lt('tasa_dominio_actual', 60);  // Menos de 60%
  
  return materias;
}
```

**Resultado (UI):**
```
⚠️ Materias en Riesgo

2 materias necesitan atención urgente

━━━━━━━━━━━━━━━━━━━━━━━━

🔴 CÓDIGO PENAL
   Dominio: 42% (CRÍTICO)
   
   ⚠️ Riesgos:
   • Puedes perder 10 puntos
   • 162 preguntas pendientes
   • Tendencia: Estable (no mejora)
   
   💡 Acción requerida:
   30 min/día durante 14 días
   
   [Plan de Código Penal]

━━━━━━━━━━━━━━━━━━━━━━━━

🟠 LEY PNP
   Dominio: 55% (BÁSICO)
   
   ⚠️ Riesgos:
   • Puedes perder 5 puntos
   • 90 preguntas pendientes
   • Tendencia: Empeorando ↘️
   
   💡 Acción requerida:
   20 min/día durante 7 días
   
   [Plan de Ley PNP]
```

---

### 4.3 📉 Detección de Bajón de Rendimiento

**Qué hace:**
Detecta si el rendimiento está bajando

**Código:**
```dart
Future<Map<String, dynamic>> detectarBajon(String userId) async {
  // Últimas 10 sesiones
  final recientes = await supabase
    .from('sesion_practica')
    .select('tasa_acierto, fecha_inicio')
    .eq('usuario_id', userId)
    .order('fecha_inicio', ascending: false)
    .limit(10);
  
  final promedioReciente = recientes
    .take(5)
    .fold(0.0, (sum, s) => sum + s['tasa_acierto']) / 5;
  
  final promedioAnterior = recientes
    .skip(5)
    .fold(0.0, (sum, s) => sum + s['tasa_acierto']) / 5;
  
  final diferencia = promedioReciente - promedioAnterior;
  
  if (diferencia < -10) {
    return {
      'hay_bajon': true,
      'diferencia': diferencia,
      'diagnostico': 'Tu rendimiento bajó ${diferencia.abs()}%',
      'posibles_causas': _analizarCausas(userId),
    };
  }
  
  return {'hay_bajon': false};
}
```

**Resultado (UI):**
```
📉 Alerta: Bajón Detectado

Tu rendimiento bajó 15% en las
últimas 5 sesiones

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Comparación:
Sesiones 6-10: 85%
Sesiones 1-5:  70% ↘️

━━━━━━━━━━━━━━━━━━━━━━━━

🔍 Posibles Causas:

• Llevas 3 días sin descansar
  → Fatiga mental probable
  
• Estudiaste 3h ayer vs 1h normal
  → Exceso puede cansar
  
• 80% de estudio nocturno
  → No es tu mejor horario

━━━━━━━━━━━━━━━━━━━━━━━━

💡 Recomendaciones:

1. Toma 1 día de descanso
2. Vuelve a 1h/día (tu óptimo)
3. Estudia en la mañana
4. Duerme 8 horas

📈 Impacto esperado:
Recuperarás tu 85% en 3 días
```

---

### 4.4 🔄 Detección de Estancamiento

**Qué hace:**
Detecta si no está progresando

**Código:**
```dart
Future<bool> detectarEstancamiento(String userId) async {
  // Preguntas dominadas hace 30 días
  final hace30 = await supabase.rpc(
    'contar_dominadas_en_fecha',
    params: {
      'p_usuario_id': userId,
      'p_fecha': DateTime.now().subtract(Duration(days: 30)),
    }
  );
  
  // Preguntas dominadas hoy
  final hoy = await supabase
    .from('exposicion_pregunta')
    .select('id')
    .eq('usuario_id', userId)
    .eq('estado_dominio', 'dominada')
    .count();
  
  final progreso = hoy - hace30;
  
  // Si en 30 días dominó menos de 50
  return progreso < 50;
}
```

**Resultado (UI):**
```
⚠️ Estancamiento Detectado

Has dominado solo 35 preguntas
en los últimos 30 días

━━━━━━━━━━━━━━━━━━━━━━━━

📊 Comparación:
Ritmo necesario: 50/mes
Tu ritmo actual: 35/mes ↘️
Déficit: -15 preguntas

━━━━━━━━━━━━━━━━━━━━━━━━

🔍 Análisis:

Causas probables:
• Estudiando solo 15 min/día
  (recomendado: 40 min)
• 5 días sin estudiar este mes
• No estás repasando errores

━━━━━━━━━━━━━━━━━━━━━━━━

💡 Plan de Recuperación:

1. Aumenta a 40 min/día
2. Estudia 6 días/semana
3. Repasa errores diariamente
4. Sigue plan del día IA

📈 Resultados esperados:
En 15 días estarás al día
```

---

### 4.5-4.10 Otras Detecciones

**4.5 😴 Detección de Fatiga Mental**
- Analiza posición en sesión
- Detecta bajón después de X preguntas
- Recomienda descanso

**4.6 🎯 Detección de Sobre-confianza**
- Compara confianza vs resultados
- Detecta exceso de seguridad
- Recomienda calibración

**4.7 😰 Detección de Inseguridad**
- Detecta baja confianza pero buena precisión
- Recomienda confiar más
- Reduce ansiedad

**4.8 📚 Detección de Abandono de Materias**
- Detecta materias sin estudiar
- Alerta antes que se olviden
- Recomienda retomar

**4.9 ⏰ Detección de Mala Gestión del Tiempo**
- Detecta sesiones muy largas/cortas
- Identifica ineficiencia
- Optimiza tiempo

**4.10 🔄 Detección de Pérdida de Racha**
- Predice si romperá racha
- Envía recordatorio preventivo
- Mantiene motivación

---

## 🎯 CATEGORÍA 5: COACHING Y MOTIVACIÓN (5 funciones)

### 5.1 💬 Mensajes Motivacionales Personalizados

**Qué hace:**
Envía mensajes motivadores basados en contexto

**Tabla:** `mensaje_ia`

**Código:**
```dart
Future<void> generarMensajeMotivacional(String userId) async {
  // Analizar contexto
  final perfil = await obtenerPerfil(userId);
  final progreso = await obtenerProgreso(userId);
  
  String mensaje;
  
  if (progreso['esta_adelantado']) {
    mensaje = '''
🎉 ¡Excelente trabajo!

Vas adelantado en tu preparación.
${progreso['preguntas_dominadas']} dominadas
y solo ${progreso['dias_transcurridos']} días.

Mantén este ritmo y tendrás tiempo
de sobra para repasar todo antes
del examen.

¡Sigue así, vas muy bien! 💪
''';
  } else if (progreso['esta_atrasado']) {
    mensaje = '''
⚡ Es momento de acelerar

Llevas ${progreso['dias_transcurridos']} días
y has dominado ${progreso['preguntas_dominadas']}.

Necesitas ${progreso['ritmo_necesario_dia']}
preguntas diarias para llegar a tiempo.

¡Tú puedes! Otros lo han logrado
y tú también lo harás. 💪

[Ver Plan Acelerado]
''';
  }
  
  // Guardar mensaje
  await supabase.from('mensaje_ia').insert({
    'usuario_id': userId,
    'tipo_mensaje': 'motivacion',
    'titulo': '💪 Mensaje del Tutor',
    'contenido': mensaje,
    'prioridad': 'normal',
  });
}
```

---

### 5.2 🎯 Celebración de Logros

**Qué hace:**
Celebra cuando alcanza hitos importantes

**Código:**
```dart
Future<void> celebrarLogro(String userId, String tipoLogro) async {
  Map<String, String> celebraciones = {
    '100_dominadas': '''
🎉 ¡100 PREGUNTAS DOMINADAS!

Has alcanzado un hito importante.
100 preguntas que ya no olvidarás.

Quedan 2,900. ¡Vamos por más! 💪
''',
    '500_dominadas': '''
🎉 ¡500 PREGUNTAS DOMINADAS!

¡Increíble! Ya dominas el 17%
del material del examen.

Estás en camino al éxito. 🚀
''',
    '1000_dominadas': '''
🎉 ¡1000 PREGUNTAS DOMINADAS!

¡WOW! Un tercio del camino recorrido.

Estás demostrando disciplina y
constancia. ¡Sigue así! 🏆
''',
    'racha_7': '''
🔥 ¡RACHA DE 7 DÍAS!

Una semana completa de estudio.
Esto es lo que separa a los que
aprueban de los que no.

¡Sigue construyendo el hábito! 💪
''',
  };
  
  await enviarNotificacion(
    userId,
    'logro',
    '🎉 ¡Logro Desbloqueado!',
    celebraciones[tipoLogro] ?? 'Genial',
  );
}
```

---

### 5.3 📊 Comparación con Versión Anterior

**Qué hace:**
Muestra cuánto ha mejorado

**Código:**
```dart
Future<Map> compararConAnterior(String userId) async {
  final ahora = await obtenerEstadoActual(userId);
  final hace30 = await obtenerEstadoEnFecha(
    userId, 
    DateTime.now().subtract(Duration(days: 30))
  );
  
  return {
    'mejora_tasa_acierto': ahora['tasa_acierto'] - hace30['tasa_acierto'],
    'mejora_velocidad': hace30['velocidad'] - ahora['velocidad'],
    'nuevas_dominadas': ahora['dominadas'] - hace30['dominadas'],
    'mensaje_motivacional': _generarMensajeComparacion(),
  };
}
```

**Resultado (UI):**
```
📊 Tú hace 30 días vs Hoy

━━━━━━━━━━━━━━━━━━━━━━━━

Tasa de acierto:
65% → 82% (+17%) 📈

Velocidad:
18 seg → 12 seg (+33%) ⚡

Preguntas dominadas:
400 → 1,250 (+850) 🚀

━━━━━━━━━━━━━━━━━━━━━━━━

💬 Mensaje del Tutor:

"¡Increíble progreso! Has mejorado
17% en precisión y 33% en velocidad.
Dominaste 850 preguntas en 30 días.

A este ritmo, aprobarás con nota
sobresaliente. ¡Sigue así! 💪"
```

---

### 5.4 🎯 Recordatorios Inteligentes

**Qué hace:**
Envía recordatorios en el momento perfecto

**Código:**
```dart
Future<void> enviarRecordatorioInteligente(String userId) async {
  // Analizar historial de estudio
  final patron = await analizarPatronEstudio(userId);
  
  // Momento óptimo según historial
  final mejorHora = patron['mejor_hora'];
  
  // Programar recordatorio
  await programarNotificacion(
    hora: mejorHora,
    titulo: '📚 Hora de estudiar',
    mensaje: _generarMensajePersonalizado(userId),
  );
}
```

---

### 5.5 💪 Consejos de Mentalidad

**Qué hace:**
Da consejos de mentalidad ganadora

**Ejemplos:**
```
💭 Consejo del Día

"El éxito no es resultado de un
día de trabajo duro, sino de
semanas de constancia."

Tu racha de 7 días lo demuestra.
¡Sigue así! 💪

━━━━━━━━━━━━━━━━━━━━━━━━

💭 Consejo del Día

"No te compares con otros.
Compárate con la versión de ti
de hace 30 días."

Has mejorado 17% desde entonces.
¡Eso es lo que importa! 📈

━━━━━━━━━━━━━━━━━━━━━━━━

💭 Consejo del Día

"Los errores no son fracasos,
son oportunidades de aprender."

Has convertido 850 errores en
850 preguntas dominadas. 🎯
```

---

## 🎯 CATEGORÍA 6: PERSONALIZACIÓN (5 funciones)

### 6.1 🎯 Adaptación de Dificultad

**Qué hace:**
Ajusta dificultad según nivel del usuario

**Código:**
```dart
Future<List<Map>> seleccionarPreguntasAdaptativas(String userId) async {
  final perfil = await obtenerPerfil(userId);
  final tasaAcierto = perfil['tasa_acierto_global'];
  
  String dificultadOptima;
  
  if (tasaAcierto < 60) {
    dificultadOptima = 'facil';
  } else if (tasaAcierto < 80) {
    dificultadOptima = 'media';
  } else {
    dificultadOptima = 'dificil';
  }
  
  final preguntas = await supabase
    .from('pregunta')
    .select('*')
    .eq('dificultad_estimada', dificultadOptima)
    .limit(20);
  
  return preguntas;
}
```

---

### 6.2 📊 Personalización del Dashboard

**Qué hace:**
Muestra métricas relevantes para cada usuario

---

### 6.3 🎨 Estilo de Mensajes

**Qué hace:**
Adapta tono según personalidad del usuario

**Ejemplos:**

**Usuario motivado:**
```
"¡Genial! Dominaste 50 hoy.
¿Listo para 60 mañana? 🚀"
```

**Usuario inseguro:**
```
"Muy bien. Dominaste 30 hoy.
Cada pregunta cuenta. Vas bien. 💪"
```

**Usuario competitivo:**
```
"¡50 dominadas! Estás en el top 15%
nacional. ¿Quieres llegar al top 10%? 🏆"
```

---

### 6.4-6.5 Otras Personalizaciones

**6.4 ⏰ Horarios Personalizados**
- Según historial
- Adapta recordatorios
- Optimiza aprendizaje

**6.5 🎯 Metas Personalizadas**
- Según capacidad
- Realistas pero desafiantes
- Ajusta dinámicamente

---

## ✅ RESUMEN DE FUNCIONES DEL IA TUTOR

| Categoría | Funciones | Descripción |
|-----------|-----------|-------------|
| **Análisis** | 10 | Diagnosticar al estudiante en profundidad |
| **Predicción** | 10 | Predecir resultados futuros |
| **Recomendación** | 10 | Sugerir acciones específicas |
| **Detección** | 10 | Identificar problemas temprano |
| **Coaching** | 5 | Motivar y guiar |
| **Personalización** | 5 | Adaptar a cada usuario |
| **TOTAL** | **50+** | |

---

## 🎯 LAS 10 MÁS PODEROSAS

1. ⭐ **Análisis Post-Sesión** - Feedback inmediato después de practicar
2. ⭐ **Plan Diario Generado** - Qué estudiar cada día
3. ⭐ **Predicción de Aprobación** - Probabilidad de aprobar
4. ⭐ **Detección de Patrones de Error** - Identifica errores recurrentes
5. ⭐ **Predicción de Olvido** - Cuándo olvidará cada pregunta
6. ⭐ **Recomendación de Qué Estudiar** - Prioriza materias
7. ⭐ **Detección de Materias en Riesgo** - Alerta temprana
8. ⭐ **Mensajes Motivacionales** - Personaliza motivación
9. ⭐ **Análisis de Velocidad** - Optimiza tiempo
10. ⭐ **Recomendación de Horario** - Mejor momento para estudiar

---

## 🚀 CÓMO IMPLEMENTARLO

### Ejemplo Completo: Análisis Post-Sesión

**1. Después de que termina una sesión:**
```dart
await supabase.from('sesion_practica').update({
  'fecha_fin': DateTime.now(),
}).eq('id', sesionId);

// El IA Tutor analiza automáticamente
final analisis = await analizarSesion(sesionId);

// Muestra pantalla de análisis
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => PantallaAnalisisSesion(analisis: analisis),
  ),
);
```

**2. La pantalla muestra:**
```
📊 Análisis de tu Sesión

✅ 85/100 correctas (85%)

📈 Destacado:
• +15% mejor que anterior
• +40% más rápido

⚠️ Mejoras:
• CP: 5/8 incorrectas
• 3 errores por "excepto"

💡 Recomendaciones:
1. Repasa Arts. 185-190
2. Lee 2 veces preguntas largas

[Repasar errores]
[Ver plan diario]
```

**3. Genera mensaje en tabla:**
```dart
await supabase.from('mensaje_ia').insert({
  'usuario_id': userId,
  'tipo_mensaje': 'analisis_sesion',
  'titulo': '📊 Análisis de Sesión',
  'contenido': analisis['mensaje'],
});
```

---

## 🎉 CONCLUSIÓN

El IA Tutor con tu base de datos puede:

✅ **Analizar** al estudiante en 10+ dimensiones  
✅ **Predecir** con 92% de confianza  
✅ **Recomendar** acciones específicas  
✅ **Detectar** problemas antes que empeoren  
✅ **Motivar** de forma personalizada  
✅ **Personalizar** la experiencia  

**50+ funciones inteligentes** todas posibles gracias a:
- 27 tablas bien diseñadas
- 11 funciones SQL (7 base + 4 dinámicas)
- 4 triggers automáticos
- 15+ variables de tracking

**¡Tu base de datos permite crear el mejor IA Tutor del mercado! 🤖🚀**

---

¿Quieres que te ayude a implementar alguna función específica del IA Tutor? 🎯

---

## PANEL IA DINAMICO (DEEPSEEK)

**Objetivo:** DeepSeek controla las tarjetas del "Tutor Personal" y genera acciones dinamicas (practicas, rachas, planes, alertas y recomendaciones).

**Contrato JSON (respuesta del Edge Function):**
```json
{
  "diagnostico": "texto breve (<= 300 caracteres)",
  "cards": [
    {
      "type": "practice|streak|message|plan|recommendation|alert",
      "title": "titulo corto",
      "message": "descripcion breve",
      "cta": "texto boton opcional",
      "items": ["item opcional 1", "item 2"],
      "payload": {
        "cantidad": 20,
        "tiempo": 25,
        "materia": "Derecho Penal"
      }
    }
  ]
}
```

**Reglas del panel:**
- 3 a 6 tarjetas por respuesta.
- Siempre incluir al menos 1 card `practice`.
- Incluir al menos 1 card `streak` o `message`.
- Si se recomienda materia, usar `payload.materia`.

**Uso en UI:**
- Las tarjetas se renderizan en `PantallaPlanEstudioIA`.
- Las cards `practice` lanzan practica con `cantidad` y `tiempo`.
- Las cards `streak/message/plan/recommendation/alert` muestran guidance.
