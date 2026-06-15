class CalculadoraProduccion {
  // Meta por hora que se puede ajustar desde Admin
  static double metaPorHora = 1380 / 9; // Aprox 153.33

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

  // META DIARIA: MetaHora * 4 máquinas * horas de ese día según turno
  static double calcularMetaDiariaMetros(String turno, DateTime fecha) {
    int diaSemana = fecha.weekday; // 1=Lunes, 6=Sábado
    double horasDia = 0.0;

    switch (turno) {
      case 'A':
        if (diaSemana >= 1 && diaSemana <= 6) horasDia = 7.5;
        break;
      case 'B':
        if (diaSemana >= 1 && diaSemana <= 5) horasDia = 7.5;
        if (diaSemana == 6) horasDia = 5.5;
        break;
      case 'C':
        if (diaSemana >= 1 && diaSemana <= 5) horasDia = 9.0;
        break;
    }
    return metaPorHora * 4 * horasDia; // Multiplicado por 4 telares
  }

  // NUEVA LÓGICA: META TOTAL QUINCENAL AUTOMÁTICA MENOS DÍAS DE ASUETO
  static double calcularMetaQuincenalMetros(String turno, {int? diasAsuetoLV, int? diasAsuetoSabado}) {
    double metaTotal = 0.0;

    // 1. Cálculo automático base recorriendo todos los días calendario de la quincena actual
    final rango = obtenerRangoQuincenaActual();
    DateTime current = rango['inicio']!;
    DateTime fin = rango['fin']!;
    
    while (!current.isAfter(fin)) {
      metaTotal += calcularMetaDiariaMetros(turno, current);
      current = current.add(const Duration(days: 1));
    }

    // 2. Restar el valor de producción de los días de asueto según las horas de cada turno
    double horasLV = turno == 'C' ? 9.0 : 7.5;
    double horasSab = turno == 'A' ? 7.5 : (turno == 'B' ? 5.5 : 0.0);

    if (diasAsuetoLV != null && diasAsuetoLV > 0) {
      metaTotal -= (metaPorHora * 4 * horasLV) * diasAsuetoLV;
    }
    
    if (diasAsuetoSabado != null && diasAsuetoSabado > 0) {
      metaTotal -= (metaPorHora * 4 * horasSab) * diasAsuetoSabado;
    }

    return metaTotal < 0 ? 0.0 : metaTotal;
  }
}