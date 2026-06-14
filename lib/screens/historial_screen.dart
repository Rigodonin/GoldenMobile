import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistorialScreen extends StatelessWidget {
  const HistorialScreen({super.key});

  String _porcentajeTexto(dynamic item) {
    final porcentaje = item['porcentaje_cumplido'];
    if (porcentaje is num) return '${porcentaje.toStringAsFixed(1)}% alcanzado';

    final total = item['total_metros'];
    final meta = item['meta_metros'];
    if (total is num && meta is num && meta > 0) {
      return '${((total / meta) * 100).toStringAsFixed(1)}% alcanzado';
    }

    return 'Porcentaje no disponible';
  }

  // Extrae de forma inteligente el rango de fechas basándose en la fecha de cierre de la quincena archivada
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Quincenas'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: FutureBuilder(
        future: Supabase.instance.client
            .from('historial_quincenas')
            .select()
            .eq('operador_id', user?.id ?? ''),
        builder: (context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data.isEmpty) {
            return const Center(child: Text('No hay cierres quincenales registrados aún.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data.length,
            itemBuilder: (context, i) {
              final item = snapshot.data[i];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFFE2E0E6)), borderRadius: BorderRadius.circular(8)),
                child: ExpansionTile(
                  leading: const Icon(Icons.archive_outlined, color: Color(0xFF2E3192)),
                  title: Text('Cerrada el: ${item['fecha_cierre']}'),
                  subtitle: Text('${item['periodo']}\n${_porcentajeTexto(item)}'),
                  trailing: Text('${item['total_metros']} mts', style: const TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    const Divider(height: 1),
                    FutureBuilder<List<dynamic>>(
                      future: () async {
                        final rango = _obtenerRangoDesdePeriodoOFecha(item['periodo'], item['fecha_cierre']);
                        if (rango['inicio'] == null || rango['fin'] == null) return [];
                        
                        final res = await Supabase.instance.client
                            .from('registros_produccion')
                            .select()
                            .eq('operador_id', user?.id ?? '')
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
                            child: Text('No se encontraron registros de producción para este periodo.', style: TextStyle(color: Colors.grey, fontSize: 13)),
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
                                subtitle: Text('T1:${reg['t1_metros']?.toStringAsFixed(0) ?? '0'}m | T2:${reg['t2_metros']?.toStringAsFixed(0) ?? '0'}m\nT3:${reg['t3_metros']?.toStringAsFixed(0) ?? '0'}m | T4:${reg['t4_metros']?.toStringAsFixed(0) ?? '0'}m\nNotas: ${reg['notas'] ?? ''}'),
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
