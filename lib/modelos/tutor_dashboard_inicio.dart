class TutorDashboardInicio {
  final String estado;
  final bool sesionValida;
  final TutorHeroStats hero;
  final TutorMissionBlock misionDiaria;
  final List<TutorInsightCard> insights;
  final List<String> atajosChat;

  const TutorDashboardInicio({
    required this.estado,
    required this.sesionValida,
    required this.hero,
    required this.misionDiaria,
    required this.insights,
    required this.atajosChat,
  });

  factory TutorDashboardInicio.fromMap(Map<String, dynamic> map) {
    final heroRaw = map['hero'] is Map
        ? Map<String, dynamic>.from(map['hero'])
        : const <String, dynamic>{};
    final misionRaw = map['mision_diaria'] is Map
        ? Map<String, dynamic>.from(map['mision_diaria'])
        : const <String, dynamic>{};

    final insightsRaw = map['insights'];
    final insights = insightsRaw is List
        ? insightsRaw
              .whereType<Map>()
              .map(
                (e) => TutorInsightCard.fromMap(Map<String, dynamic>.from(e)),
              )
              .toList()
        : <TutorInsightCard>[];

    final atajosRaw = map['atajos_chat'];
    final atajos = atajosRaw is List
        ? atajosRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    return TutorDashboardInicio(
      estado: (map['estado'] ??'sin_datos').toString(),
      sesionValida: map['sesion_valida'] == true,
      hero: TutorHeroStats.fromMap(heroRaw),
      misionDiaria: TutorMissionBlock.fromMap(misionRaw),
      insights: insights,
      atajosChat: atajos,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'estado': estado,
      'sesion_valida': sesionValida,
      'hero': hero.toMap(),
      'mision_diaria': misionDiaria.toMap(),
      'insights': insights.map((e) => e.toMap()).toList(),
      'atajos_chat': atajosChat,
    };
  }

  factory TutorDashboardInicio.fallback() {
    return const TutorDashboardInicio(
      estado: 'sin_datos',
      sesionValida: false,
      hero: TutorHeroStats(
        nivel: 'INICIAL',
        aprobacion: 0,
        dominadasHoy: 0,
        rachaDias: 0,
      ),
      misionDiaria: TutorMissionBlock(
        preguntasObjetivo: 20,
        minutosObjetivo: 30,
        preguntasCompletadas: 0,
        minutosCompletados: 0,
        cantidadPractica: 20,
        tiempoPractica: 30,
        resumen:
            'Inicia tu primera sesion para activar una mision diaria real.',
        ctaHabilitada: false,
      ),
      insights: <TutorInsightCard>[],
      atajosChat: <String>[
        'dame mi plan diario',
        'que estudiar hoy',
        'analiza mi ultima sesion',
        'analisis de velocidad',
        'cuales son mis materias en riesgo',
        'prediccion de olvido',
        'dame un mensaje motivacional',
      ],
    );
  }
}

class TutorHeroStats {
  final String nivel;
  final double aprobacion;
  final int dominadasHoy;
  final int rachaDias;

  const TutorHeroStats({
    required this.nivel,
    required this.aprobacion,
    required this.dominadasHoy,
    required this.rachaDias,
  });

  factory TutorHeroStats.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ??0.0;
      return 0.0;
    }

    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ??0;
      return 0;
    }

    return TutorHeroStats(
      nivel: (map['nivel'] ??'INICIAL').toString(),
      aprobacion: toDouble(map['aprobacion']),
      dominadasHoy: toInt(map['dominadas_hoy']),
      rachaDias: toInt(map['racha_dias']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nivel': nivel,
      'aprobacion': aprobacion,
      'dominadas_hoy': dominadasHoy,
      'racha_dias': rachaDias,
    };
  }
}

class TutorMissionBlock {
  final int preguntasObjetivo;
  final int minutosObjetivo;
  final int preguntasCompletadas;
  final int minutosCompletados;
  final int cantidadPractica;
  final int tiempoPractica;
  final String resumen;
  final bool ctaHabilitada;

  const TutorMissionBlock({
    required this.preguntasObjetivo,
    required this.minutosObjetivo,
    required this.preguntasCompletadas,
    required this.minutosCompletados,
    required this.cantidadPractica,
    required this.tiempoPractica,
    required this.resumen,
    required this.ctaHabilitada,
  });

  factory TutorMissionBlock.fromMap(Map<String, dynamic> map) {
    int toInt(dynamic value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ??fallback;
      return fallback;
    }

    return TutorMissionBlock(
      preguntasObjetivo: toInt(map['preguntas_objetivo'], 20),
      minutosObjetivo: toInt(map['minutos_objetivo'], 30),
      preguntasCompletadas: toInt(map['preguntas_completadas'], 0),
      minutosCompletados: toInt(map['minutos_completados'], 0),
      cantidadPractica: toInt(map['cantidad_practica'], 20),
      tiempoPractica: toInt(map['tiempo_practica'], 30),
      resumen: (map['resumen'] ??'Sin resumen de mision').toString(),
      ctaHabilitada: map['cta_habilitada'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'preguntas_objetivo': preguntasObjetivo,
      'minutos_objetivo': minutosObjetivo,
      'preguntas_completadas': preguntasCompletadas,
      'minutos_completados': minutosCompletados,
      'cantidad_practica': cantidadPractica,
      'tiempo_practica': tiempoPractica,
      'resumen': resumen,
      'cta_habilitada': ctaHabilitada,
    };
  }
}

class TutorInsightCard {
  final String id;
  final String titulo;
  final String resumen;
  final String detalle;
  final String promptAccion;
  final String cta;
  final String colorHex;
  final String iconName;
  final bool expandable;
  final int?cantidadPractica;
  final int?tiempoPractica;
  final String?materia;
  final List<String> preguntaIds;
  final List<String> preguntasNuevasIds;
  final List<String> preguntasRepasoIds;
  final List<String> materiasPrioritariasIds;
  final List<TutorRiskItem> riesgos;

  const TutorInsightCard({
    required this.id,
    required this.titulo,
    required this.resumen,
    required this.detalle,
    required this.promptAccion,
    required this.cta,
    required this.colorHex,
    required this.iconName,
    required this.expandable,
    this.cantidadPractica,
    this.tiempoPractica,
    this.materia,
    this.preguntaIds = const <String>[],
    this.preguntasNuevasIds = const <String>[],
    this.preguntasRepasoIds = const <String>[],
    this.materiasPrioritariasIds = const <String>[],
    this.riesgos = const <TutorRiskItem>[],
  });

  factory TutorInsightCard.fromMap(Map<String, dynamic> map) {
    int?toOptionalInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    List<String> toStringList(dynamic value) {
      if (value is! List) return const <String>[];
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final riesgosRaw = map['riesgos'];
    final riesgos = riesgosRaw is List
        ? riesgosRaw
              .whereType<Map>()
              .map((e) => TutorRiskItem.fromMap(Map<String, dynamic>.from(e)))
              .toList()
        : <TutorRiskItem>[];

    return TutorInsightCard(
      id: (map['id'] ??'card').toString(),
      titulo: (map['titulo'] ??'Insight').toString(),
      resumen: (map['resumen'] ??'').toString(),
      detalle: (map['detalle'] ??'').toString(),
      promptAccion: (map['prompt'] ??'').toString(),
      cta: (map['cta'] ??'Abrir en chat').toString(),
      colorHex: (map['color'] ??'#CBD5E1').toString(),
      iconName: (map['icono'] ??'insights').toString(),
      expandable: map['expandable'] != false,
      cantidadPractica: toOptionalInt(map['cantidad_practica']),
      tiempoPractica: toOptionalInt(map['tiempo_practica']),
      materia: map['materia']?.toString(),
      preguntaIds: toStringList(map['pregunta_ids']),
      preguntasNuevasIds: toStringList(map['preguntas_nuevas_ids']),
      preguntasRepasoIds: toStringList(map['preguntas_repaso_ids']),
      materiasPrioritariasIds: toStringList(map['materias_prioritarias_ids']),
      riesgos: riesgos,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titulo': titulo,
      'resumen': resumen,
      'detalle': detalle,
      'prompt': promptAccion,
      'cta': cta,
      'color': colorHex,
      'icono': iconName,
      'expandable': expandable,
      if (cantidadPractica != null) 'cantidad_practica': cantidadPractica,
      if (tiempoPractica != null) 'tiempo_practica': tiempoPractica,
      if (materia != null && materia!.trim().isNotEmpty) 'materia': materia,
      if (preguntaIds.isNotEmpty) 'pregunta_ids': preguntaIds,
      if (preguntasNuevasIds.isNotEmpty)
        'preguntas_nuevas_ids': preguntasNuevasIds,
      if (preguntasRepasoIds.isNotEmpty)
        'preguntas_repaso_ids': preguntasRepasoIds,
      if (materiasPrioritariasIds.isNotEmpty)
        'materias_prioritarias_ids': materiasPrioritariasIds,
      'riesgos': riesgos.map((e) => e.toMap()).toList(),
    };
  }
}

class TutorRiskItem {
  final String materia;
  final double tasa;
  final String tendencia;
  final String semaforo;

  const TutorRiskItem({
    required this.materia,
    required this.tasa,
    required this.tendencia,
    required this.semaforo,
  });

  factory TutorRiskItem.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ??0.0;
      return 0.0;
    }

    return TutorRiskItem(
      materia: (map['materia'] ??'Materia').toString(),
      tasa: toDouble(map['tasa']),
      tendencia: (map['tendencia'] ??'estable').toString(),
      semaforo: (map['semaforo'] ??'verde').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'materia': materia,
      'tasa': tasa,
      'tendencia': tendencia,
      'semaforo': semaforo,
    };
  }
}
