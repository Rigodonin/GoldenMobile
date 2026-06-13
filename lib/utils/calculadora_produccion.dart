class CalculadoraProduccion {
  // Variable estática para que pueda ser modificada desde los ajustes del admin
  static double metaPorHora = 1380 / 9; // Aprox 153.33 metros/hora

  // 1. Determina las fechas de inicio y fin de la quincena actual
  static Map<String, DateTime> obtenerRangoQuincenaActual() {
    final hoy = DateTime.now();
    DateTime inicio;
    DateTime fin;

    if (hoy.day <= 15) {
      inicio = DateTime(hoy.year, hoy.month, 1);
      fin = DateTime(hoy.year, hoy.month, 15);
    } else {
      inicio = DateTime(hoy.year, hoy.month, 16);
      fin = DateTime(hoy.year, hoy.month + 1, 0); 
    }
    return {'inicio': inicio, 'fin': fin};
  }

  // 2. Calcula las horas exactas laborables con soporte para días personalizados
  static double calcularHorasQuincena(String turno, {int? diasLV, int? diasSabado}) {
    // Si el operador configuró sus días manualmente
    if (diasLV != null) {
      double horasTotales = diasLV * (turno == 'C' ? 9.0 : 7.5);
      if (diasSabado != null) {
        if (turno == 'A') horasTotales += diasSabado * 7.5;
        if (turno == 'B') horasTotales += diasSabado * 5.5;
      }
      return horasTotales;
    }

    // Cálculo automático original basado en el calendario
    final rango = obtenerRangoQuincenaActual();
    DateTime fechaActual = rango['inicio']!;
    DateTime fechaFin = rango['fin']!;
    
    double horasTotales = 0.0;

    while (fechaActual.isBefore(fechaFin) || fechaActual.isAtSameMomentAs(fechaFin)) {
      int diaSemana = fechaActual.weekday;
      switch (turno) {
        case 'A':
          if (diaSemana >= 1 && diaSemana <= 6) horasTotales += 7.5;
          break;
        case 'B':
          if (diaSemana >= 1 && diaSemana <= 5) {
            horasTotales += 7.5;
          } else if (diaSemana == 6) {
            horasTotales += 5.5;
          }
          break;
        case 'C':
          if (diaSemana >= 1 && diaSemana <= 5) horasTotales += 9.0;
          break;
      }
      fechaActual = fechaActual.add(const Duration(days: 1));
    }
    return horasTotales;
  }

  // 3. Obtiene la meta final de metros para la quincena completa
  static double calcularMetaQuincenalMetros(String turno, {int? diasLV, int? diasSabado}) {
    double horasQuincena = calcularHorasQuincena(turno, diasLV: diasLV, diasSabado: diasSabado);
    return horasQuincena * metaPorHora;
  }

  // 4. NUEVO: Obtiene la meta diaria dependiendo del turno y el día de la semana
  static double calcularMetaDiariaMetros(String turno, DateTime fecha) {
    int diaSemana = fecha.weekday; // 1 = Lunes, 6 = Sábado, 7 = Domingo

    switch (turno) {
      case 'A':
        if (diaSemana >= 1 && diaSemana <= 6) return 7.5 * metaPorHora;
        break;
      case 'B':
        if (diaSemana >= 1 && diaSemana <= 5) return 7.5 * metaPorHora;
        if (diaSemana == 6) return 5.5 * metaPorHora;
        break;
      case 'C':
        if (diaSemana >= 1 && diaSemana <= 5) return 9.0 * metaPorHora;
        break;
    }
    return 0.0; // Domingos o días no laborales
  }
}