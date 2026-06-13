import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/calculadora_produccion.dart';

class OperadorScreen extends StatefulWidget {
  const OperadorScreen({super.key});

  @override
  State<OperadorScreen> createState() => _OperadorScreenState();
}

class _OperadorScreenState extends State<OperadorScreen> {
  final _notasController = TextEditingController();
  final List<TextEditingController> _telarControllers = List.generate(4, (_) => TextEditingController());
  
  String _nombreOperador = 'Cargando...';
  String _turnoLaboral = 'A';
  
  // Variables Quincena
  double _metrosTotalesQuincena = 0.0;
  double _metaQuincena = 0.0;
  
  // Variables del Día (NUEVO)
  double _metrosDiaSeleccionado = 0.0;
  double _metaDiaSeleccionado = 0.0;
  
  DateTime _fechaSeleccionada = DateTime.now();
  List<dynamic> _historialQuincena = [];
  bool _isLoading = true;

  // Variables para la configuración manual de días (NUEVO)
  int? _diasLVManuales;
  int? _diasSabadoManuales;

  @override
  void initState() {
    super.initState();
    _cargarDatosOperador();
  }

  Future<void> _cargarDatosOperador() async {
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final perfil = await Supabase.instance.client
          .from('perfiles')
          .select('nombre_completo, turno_laboral')
          .eq('id', user.id)
          .single();

      _nombreOperador = perfil['nombre_completo'];
      _turnoLaboral = perfil['turno_laboral'] ?? 'A';
      
      // Cálculo de meta quincenal con posibles variables manuales
      _metaQuincena = CalculadoraProduccion.calcularMetaQuincenalMetros(
        _turnoLaboral, 
        diasLV: _diasLVManuales, 
        diasSabado: _diasSabadoManuales
      );
      
      // Cálculo de la meta del día seleccionado
      _metaDiaSeleccionado = CalculadoraProduccion.calcularMetaDiariaMetros(_turnoLaboral, _fechaSeleccionada);

      final rango = CalculadoraProduccion.obtenerRangoQuincenaActual();
      final historial = await Supabase.instance.client
          .from('registros_produccion')
          .select()
          .eq('operador_id', user.id)
          .gte('fecha', rango['inicio']!.toIso8601String().split('T')[0])
          .lte('fecha', rango['fin']!.toIso8601String().split('T')[0])
          .order('fecha', ascending: false);

      double sumaAcumuladaQuincena = 0;
      double sumaDiaActual = 0;
      String fechaFiltroStr = _fechaSeleccionada.toString().split(' ')[0];

      for (var reg in historial) {
        double totalReg = (reg['t1_metros'] ?? 0) + (reg['t2_metros'] ?? 0) + (reg['t3_metros'] ?? 0) + (reg['t4_metros'] ?? 0);
        sumaAcumuladaQuincena += totalReg;
        if (reg['fecha'] == fechaFiltroStr) {
          sumaDiaActual += totalReg;
        }
      }

      if (mounted) {
        setState(() {
          _historialQuincena = historial;
          _metrosTotalesQuincena = sumaAcumuladaQuincena;
          _metrosDiaSeleccionado = sumaDiaActual;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error al cargar datos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _seleccionarFecha() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _fechaSeleccionada) {
      setState(() => _fechaSeleccionada = picked);
      _cargarDatosOperador(); // Recargar para actualizar metas y metros del día
    }
  }

  Future<void> _verificarYGuardar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final fechaStr = _fechaSeleccionada.toString().split(' ')[0];
    final registroExistente = await Supabase.instance.client
        .from('registros_produccion')
        .select('id')
        .eq('operador_id', user.id)
        .eq('fecha', fechaStr)
        .maybeSingle();

    if (registroExistente != null) {
      _mostrarDialogoReemplazo(registroExistente['id'], fechaStr);
    } else {
      await _ejecutarGuardadoDB(null);
    }
  }

  void _mostrarDialogoReemplazo(String idExistente, String fechaStr) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Registro Existente'),
          content: Text('Ya existe un registro para la fecha $fechaStr. ¿Qué deseas hacer?'),
          actions: [
            TextButton(child: const Text('Cancelar', style: TextStyle(color: Colors.grey)), onPressed: () => Navigator.pop(context)),
            TextButton(child: const Text('Cambiar Fecha'), onPressed: () { Navigator.pop(context); _seleccionarFecha(); }),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Reemplazar', style: TextStyle(color: Colors.white)),
              onPressed: () { Navigator.pop(context); _ejecutarGuardadoDB(idExistente); },
            ),
          ],
        );
      },
    );
  }

  Future<void> _ejecutarGuardadoDB(String? idActualizar) async {
    final user = Supabase.instance.client.auth.currentUser;
    final fechaStr = _fechaSeleccionada.toString().split(' ')[0];
    final datosAGuardar = {
      'operador_id': user!.id,
      'fecha': fechaStr,
      't1_metros': double.tryParse(_telarControllers[0].text) ?? 0.0,
      't2_metros': double.tryParse(_telarControllers[1].text) ?? 0.0,
      't3_metros': double.tryParse(_telarControllers[2].text) ?? 0.0,
      't4_metros': double.tryParse(_telarControllers[3].text) ?? 0.0,
      'notas': _notasController.text.trim(),
    };

    try {
      if (idActualizar != null) {
        await Supabase.instance.client.from('registros_produccion').update(datosAGuardar).eq('id', idActualizar);
      } else {
        await Supabase.instance.client.from('registros_produccion').insert(datosAGuardar);
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro guardado exitosamente'), backgroundColor: Colors.green));
      for (var ctrl in _telarControllers) { ctrl.clear(); }
      _notasController.clear();
      _cargarDatosOperador();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red));
    }
  }

  // --- NUEVA LÓGICA DE CONFIGURACIÓN Y ARCHIVADO ---

  void _mostrarDialogoConfigDias() {
    final ctrlLV = TextEditingController(text: _diasLVManuales?.toString() ?? '');
    final ctrlSab = TextEditingController(text: _diasSabadoManuales?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Configurar Días Laborales', style: TextStyle(color: Color(0xFF1E2265))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ajusta la cantidad de días que trabajarás en esta quincena para recalcular tu meta.', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrlLV, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Días Completos (Lunes a Viernes)', border: OutlineInputBorder()),
              ),
              if (_turnoLaboral == 'B' || _turnoLaboral == 'A') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: ctrlSab, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Días Sábado (Medio Turno)', border: OutlineInputBorder()),
                ),
              ]
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() { _diasLVManuales = null; _diasSabadoManuales = null; });
                _cargarDatosOperador();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuración restablecida al automático')));
              },
              child: const Text('Restablecer Auto', style: TextStyle(color: Colors.grey))
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _diasLVManuales = int.tryParse(ctrlLV.text);
                  if (_turnoLaboral == 'B' || _turnoLaboral == 'A') {
                    _diasSabadoManuales = int.tryParse(ctrlSab.text);
                  }
                });
                _cargarDatosOperador();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2265), foregroundColor: Colors.white),
              child: const Text('Guardar Días'),
            ),
          ],
        );
      }
    );
  }

  void _confirmarArchivarQuincena() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('¿Archivar Quincena?', style: TextStyle(color: Colors.red)),
          content: const Text('Al archivar, tus metros totales se guardarán en tu historial y se borrarán los registros actuales para que inicies una nueva quincena desde 0. ¿Estás seguro?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
            ElevatedButton.icon(
              icon: const Icon(Icons.archive),
              label: const Text('Archivar y Reiniciar'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                _ejecutarArchivado();
              },
            ),
          ],
        );
      }
    );
  }

  Future<void> _ejecutarArchivado() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _metrosTotalesQuincena <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay registros suficientes para archivar.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isLoading = true);

    try {
      // 1. Guardar en Historial de Quincenas
      await Supabase.instance.client.from('historial_quincenas').insert({
        'operador_id': user.id,
        'fecha_cierre': DateTime.now().toIso8601String().split('T')[0],
        'periodo': 'Quincena Cerrada Manualmente',
        'total_metros': _metrosTotalesQuincena
      });

      // 2. Borrar registros de esta quincena para iniciar de 0
      final rango = CalculadoraProduccion.obtenerRangoQuincenaActual();
      await Supabase.instance.client.from('registros_produccion')
          .delete()
          .eq('operador_id', user.id)
          .gte('fecha', rango['inicio']!.toIso8601String().split('T')[0])
          .lte('fecha', rango['fin']!.toIso8601String().split('T')[0]);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quincena archivada correctamente. Iniciando desde 0.'), backgroundColor: Colors.green));
      _cargarDatosOperador();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al archivar: $e'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Porcentaje Quincena
    double porcentajeQuincena = _metaQuincena > 0 ? (_metrosTotalesQuincena / _metaQuincena) : 0;
    if (porcentajeQuincena > 1.0) porcentajeQuincena = 1.0;

    // Porcentaje del Día Actual
    double porcentajeDia = _metaDiaSeleccionado > 0 ? (_metrosDiaSeleccionado / _metaDiaSeleccionado) : 0;
    if (porcentajeDia > 1.0) porcentajeDia = 1.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Producción: $_nombreOperador', style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Ajuste de Días',
            icon: const Icon(Icons.settings),
            onPressed: _mostrarDialogoConfigDias,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PANEL 1: META QUINCENA
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF5F3F7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Acumulado de Quincena', style: TextStyle(color: Colors.grey)),
                          Text('${_metrosTotalesQuincena.toInt()} / ${_metaQuincena.toInt()} m', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Rendimiento Global', style: TextStyle(color: Colors.grey)),
                          Text('${(porcentajeQuincena * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00A99D))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: porcentajeQuincena, backgroundColor: Colors.grey.shade300, color: const Color(0xFF00A99D), minHeight: 8, borderRadius: BorderRadius.circular(4)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // PANEL 2: META DEL DÍA
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFE2E2F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E2265).withOpacity(0.2))),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rendimiento del Día Seleccionado', style: TextStyle(color: Color(0xFF1E2265))),
                          Text('${_metrosDiaSeleccionado.toInt()} / ${_metaDiaSeleccionado.toInt()} m', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E2265))),
                        ],
                      ),
                      Text('${(porcentajeDia * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E2265))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: porcentajeDia, backgroundColor: Colors.white, color: const Color(0xFF1E2265), minHeight: 8, borderRadius: BorderRadius.circular(4)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Selector de Fecha
            InkWell(
              onTap: _seleccionarFecha,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Fecha del Registro:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                    Row(
                      children: [
                        Text(_fechaSeleccionada.toString().split(' ')[0], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00A99D))),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_calendar, color: Color(0xFF00A99D)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Campos de Telares
            const Text('Captura de Metros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: List.generate(4, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          SizedBox(width: 70, child: Text('Telar ${index + 1}:', style: const TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(
                            child: TextField(
                              controller: _telarControllers[index],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(hintText: '0.0', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notasController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notas / Incidencias', hintText: 'Falla en trama...', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            
            // Botón Guardar
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Guardar Registro Diarios', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: _verificarYGuardar,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2265), foregroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 12),

            // Botón Archivar Quincena (NUEVO)
            SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archivar y Finalizar Quincena', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: _confirmarArchivarQuincena,
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1E2265), side: const BorderSide(color: Color(0xFF1E2265), width: 1.5)),
              ),
            ),
            const Divider(height: 40, thickness: 2),

            // Historial Inferior
            const Text('Historial de esta Quincena', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _historialQuincena.isEmpty 
              ? const Text('Aún no hay registros en esta quincena.', style: TextStyle(color: Colors.grey))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _historialQuincena.length,
                  itemBuilder: (context, i) {
                    final h = _historialQuincena[i];
                    final t1 = h['t1_metros'] ?? 0;
                    final t2 = h['t2_metros'] ?? 0;
                    final t3 = h['t3_metros'] ?? 0;
                    final t4 = h['t4_metros'] ?? 0;
                    final totalDia = t1 + t2 + t3 + t4;
                    return Card(
                      color: const Color(0xFFFAFAFA),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('Fecha: ${h['fecha']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('T1:$t1 | T2:$t2 | T3:$t3 | T4:$t4\nNotas: ${h['notas'] ?? 'Ninguna'}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Total', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text('${totalDia.toInt()}m', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00A99D))),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                )
          ],
        ),
      ),
    );
  }
}