import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/calculadora_produccion.dart'; // Importación obligatoria para reutilizar las metas

class HistorialScreen extends StatelessWidget {
  const HistorialScreen({super.key});

  Map<String, String?> _obtenerRangoDesdePeriodoOFecha(dynamic periodo, dynamic fechaCierre) {
    try {
      if (periodo != null) {
        final str = periodo.toString();
        final regExp = RegExp(r'\d{4}-\d{2}-\d{2}');
        final matches = regExp.allMatches(str).map((m) => m.group(0)).toList();
        if (matches.length >= 2) {
          return {'inicio': matches[0], 'fin': matches[1]};
        }
      }
    } catch (_) {}

    try {
      if (fechaCierre != null) {
        final fecha = DateTime.parse(fechaCierre.toString());
        DateTime inicio;
        DateTime fin;
        if (fecha.day <= 15) {
          inicio = DateTime(fecha.year, fecha.month, 1);
          fin = DateTime(fecha.year, fecha.month, 15);
        } else {
          inicio = DateTime(fecha.year, fecha.month, 16);
          fin = DateTime(fecha.year, fecha.month + 1, 0);
        }
        return {
          'inicio': "${inicio.year}-${inicio.month.toString().padLeft(2, '0')}-${inicio.day.toString().padLeft(2, '0')}",
          'fin': "${fin.year}-${fin.month.toString().padLeft(2, '0')}-${fin.day.toString().padLeft(2, '0')}"
        };
      }
    } catch (_) {}

    return {'inicio': null, 'fin': null};
  }

  // 🆕 Función para calcular la meta que correspondía a ese periodo histórico exacto
  double _calcularMetaHistorica(String turno, String inicioStr, String finStr) {
    try {
      DateTime current = DateTime.parse(inicioStr);
      DateTime fFin = DateTime.parse(finStr);
      double metaTotal = 0.0;
      
      while (!current.isAfter(fFin)) {
        metaTotal += CalculadoraProduccion.calcularMetaDiariaMetros(turno, current);
        current = current.add(const Duration(days: 1));
      }
      return metaTotal;
    } catch (e) {
      return 0.0;
    }
  }

  // 🆕 Future consolidado para obtener el turno del usuario y su historial a la vez
  Future<Map<String, dynamic>> _cargarDatos() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    // Obtener turno laboral para calcular la meta real
    final perfil = await Supabase.instance.client
        .from('perfiles')
        .select('turno_laboral')
        .eq('id', user.id)
        .single();

    final historial = await Supabase.instance.client
        .from('historial_quincenas')
        .select()
        .eq('operador_id', user.id)
        .order('fecha_cierre', ascending: false);

    return {
      'turno': perfil['turno_laboral'] ?? 'A',
      'historial': historial as List<dynamic>,
      'user_id': user.id
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Quincenas'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _cargarDatos(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar historial: ${snapshot.error}'));
          }
          
          final listaHistorial = snapshot.data?['historial'] as List<dynamic>? ?? [];
          final turnoUsuario = snapshot.data?['turno'] as String? ?? 'A';
          final userId = snapshot.data?['user_id'] as String;

          if (listaHistorial.isEmpty) {
            return const Center(child: Text('No hay cierres quincenales registrados aún.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: listaHistorial.length,
            itemBuilder: (context, i) {
              final item = listaHistorial[i];
              final totalMetros = (item['total_metros'] as num?)?.toDouble() ?? 0.0;
              
              final rango = _obtenerRangoDesdePeriodoOFecha(item['periodo'], item['fecha_cierre']);
              
              // 🆕 Lógica de Porcentajes implementada
              double metaPeriodo = 0.0;
              double porcentaje = 0.0;
              if (rango['inicio'] != null && rango['fin'] != null) {
                metaPeriodo = _calcularMetaHistorica(turnoUsuario, rango['inicio']!, rango['fin']!);
                if (metaPeriodo > 0) porcentaje = (totalMetros / metaPeriodo) * 100;
              }

              // Color dinámico según rendimiento
              Color colorPorcentaje = Colors.grey;
              if (porcentaje >= 100) colorPorcentaje = Colors.green;
              else if (porcentaje >= 80) colorPorcentaje = Colors.orange;
              else if (porcentaje > 0) colorPorcentaje = Colors.red;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFFE2E0E6)), borderRadius: BorderRadius.circular(8)),
                child: ExpansionTile(
                  leading: const Icon(Icons.archive_outlined, color: Color(0xFF2E3192)),
                  title: Text('Cerrada el: ${item['fecha_cierre']}'),
                  subtitle: Text('${item['periodo']}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${totalMetros.toStringAsFixed(0)} mts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (porcentaje > 0)
                         Text('${porcentaje.toStringAsFixed(1)}%', style: TextStyle(color: colorPorcentaje, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  children: [
                    if (porcentaje > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Meta del periodo: ${metaPeriodo.toStringAsFixed(0)} mts', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                            LinearProgressIndicator(
                              value: (porcentaje / 100).clamp(0.0, 1.0),
                              backgroundColor: Colors.grey.shade200,
                              color: colorPorcentaje,
                              minHeight: 6,
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    FutureBuilder<List<dynamic>>(
                      future: () async {
                        if (rango['inicio'] == null || rango['fin'] == null) return [];
                        
                        final res = await Supabase.instance.client
                            .from('registros_produccion')
                            .select()
                            .eq('operador_id', userId)
                            .gte('fecha', rango['inicio']!)
                            .lte('fecha', rango['fin']!)
                            .order('fecha', ascending: false);
                        return res as List<dynamic>;
                      }(),
                      builder: (context, detailSnapshot) {
                        if (detailSnapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        if (!detailSnapshot.hasData || detailSnapshot.data!.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Text('No se encontraron registros diarios detallados.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: detailSnapshot.data!.length,
                          itemBuilder: (context, idx) {
                            final reg = detailSnapshot.data![idx];
                            final totalReg = (reg['t1_metros'] ?? 0) + (reg['t2_metros'] ?? 0) + (reg['t3_metros'] ?? 0) + (reg['t4_metros'] ?? 0);
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text('Fecha: ${reg['fecha']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('T1:${reg['t1_metros']?.toStringAsFixed(0) ?? '0'}m | T2:${reg['t2_metros']?.toStringAsFixed(0) ?? '0'}m\nT3:${reg['t3_metros']?.toStringAsFixed(0) ?? '0'}m | T4:${reg['t4_metros']?.toStringAsFixed(0) ?? '0'}m'),
                                trailing: Text('${totalReg.toStringAsFixed(0)}m', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E2265))),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}