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
  
  double _metrosTotalesQuincena = 0.0;
  double _metaQuincenaTotal = 0.0;
  double _metaRitmoActual = 0.0; // La meta sumada solo de los días que ya trabajó
  
  DateTime _fechaSeleccionada = DateTime.now();
  String? _idRegistroEditando; // Para saber si estamos editando
  List<dynamic> _historialQuincena = [];
  bool _isLoading = true;

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
      final perfil = await Supabase.instance.client.from('perfiles').select().eq('id', user.id).single();
      _nombreOperador = perfil['nombre_completo'];
      _turnoLaboral = perfil['turno_laboral'] ?? 'A';
      
      _metaQuincenaTotal = CalculadoraProduccion.calcularMetaQuincenalMetros(_turnoLaboral, diasLV: _diasLVManuales, diasSabado: _diasSabadoManuales);

      final rango = CalculadoraProduccion.obtenerRangoQuincenaActual();
      
      // TRAER SOLO LOS NO ARCHIVADOS (o donde archivado sea null/false)
      final historial = await Supabase.instance.client
          .from('registros_produccion')
          .select()
          .eq('operador_id', user.id)
          .gte('fecha', rango['inicio']!.toIso8601String().split('T')[0])
          .lte('fecha', rango['fin']!.toIso8601String().split('T')[0])
          .isFilter('archivado', false) // MAGIA PARA OCULTAR ARCHIVADOS
          .order('fecha', ascending: false);

      double acumulado = 0;
      double ritmoTarget = 0;

      for (var reg in historial) {
        // Sumar metros reales
        acumulado += (reg['t1_metros'] ?? 0) + (reg['t2_metros'] ?? 0) + (reg['t3_metros'] ?? 0) + (reg['t4_metros'] ?? 0);
        
        // Sumar la meta ideal de ESE DÍA específico para calcular el Ritmo
        DateTime fechaReg = DateTime.parse(reg['fecha']);
        ritmoTarget += CalculadoraProduccion.calcularMetaDiariaMetros(_turnoLaboral, fechaReg);
      }

      if (mounted) {
        setState(() {
          _historialQuincena = historial;
          _metrosTotalesQuincena = acumulado;
          _metaRitmoActual = ritmoTarget;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _cargarRegistroParaEditar(Map<String, dynamic> reg) {
    setState(() {
      _idRegistroEditando = reg['id'];
      _fechaSeleccionada = DateTime.parse(reg['fecha']);
      _telarControllers[0].text = reg['t1_metros'].toString();
      _telarControllers[1].text = reg['t2_metros'].toString();
      _telarControllers[2].text = reg['t3_metros'].toString();
      _telarControllers[3].text = reg['t4_metros'].toString();
      _notasController.text = reg['notas'] ?? '';
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editando registro seleccionado. Modifica y guarda.')));
  }

  void _limpiarFormulario() {
    setState(() {
      _idRegistroEditando = null;
      _fechaSeleccionada = DateTime.now();
      for (var ctrl in _telarControllers) { ctrl.clear(); }
      _notasController.clear();
    });
  }

  Future<void> _verificarYGuardar() async {
    final fechaStr = _fechaSeleccionada.toString().split(' ')[0];
    
    // Si NO estamos editando, revisamos si ya hay un registro con esta fecha en la pantalla
    if (_idRegistroEditando == null) {
      bool existe = _historialQuincena.any((reg) => reg['fecha'] == fechaStr);
      if (existe) {
        _mostrarAlertaSobreescritura(fechaStr);
        return;
      }
    }
    await _ejecutarGuardadoDB();
  }

  void _mostrarAlertaSobreescritura(String fechaStr) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¡Advertencia!', style: TextStyle(color: Colors.orange)),
        content: Text('Ya tienes un registro guardado para la fecha $fechaStr.\n\nPara modificarlo, mejor búscalo en el historial de abajo y tócalo para editarlo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ],
      )
    );
  }

  Future<void> _ejecutarGuardadoDB() async {
    final user = Supabase.instance.client.auth.currentUser;
    final datos = {
      'operador_id': user!.id,
      'fecha': _fechaSeleccionada.toString().split(' ')[0],
      't1_metros': double.tryParse(_telarControllers[0].text) ?? 0.0,
      't2_metros': double.tryParse(_telarControllers[1].text) ?? 0.0,
      't3_metros': double.tryParse(_telarControllers[2].text) ?? 0.0,
      't4_metros': double.tryParse(_telarControllers[3].text) ?? 0.0,
      'notas': _notasController.text.trim(),
      'archivado': false // Por si acaso
    };

    try {
      if (_idRegistroEditando != null) {
        await Supabase.instance.client.from('registros_produccion').update(datos).eq('id', _idRegistroEditando!);
      } else {
        await Supabase.instance.client.from('registros_produccion').insert(datos);
      }
      _limpiarFormulario();
      _cargarDatosOperador();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado exitosamente'), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _archivarQuincena() async {
    final user = Supabase.instance.client.auth.currentUser;
    setState(() => _isLoading = true);
    try {
      // 1. Guardar en historial
      await Supabase.instance.client.from('historial_quincenas').insert({
        'operador_id': user!.id, 'fecha_cierre': DateTime.now().toIso8601String().split('T')[0],
        'periodo': 'Cierre Manual', 'total_metros': _metrosTotalesQuincena
      });

      // 2. Soft Delete: Marcar como archivados para que desaparezcan de la pantalla
      final rango = CalculadoraProduccion.obtenerRangoQuincenaActual();
      await Supabase.instance.client.from('registros_produccion')
          .update({'archivado': true})
          .eq('operador_id', user.id)
          .gte('fecha', rango['inicio']!.toIso8601String().split('T')[0])
          .lte('fecha', rango['fin']!.toIso8601String().split('T')[0]);

      // 3. Limpiar estado local
      _limpiarFormulario();
      _cargarDatosOperador();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Asegúrate de agregar la columna "archivado" (boolean) en Supabase. Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _mostrarConfigDias() {
    final cLV = TextEditingController(text: _diasLVManuales?.toString() ?? '');
    final cS = TextEditingController(text: _diasSabadoManuales?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Días Laborales'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: cLV, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Días Lunes a Viernes')),
            if (_turnoLaboral != 'C') TextField(controller: cS, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Días Sábado')),
          ],
        ),
        actions: [
          TextButton(onPressed: () { setState(() { _diasLVManuales = null; _diasSabadoManuales = null; }); _cargarDatosOperador(); Navigator.pop(context); }, child: const Text('Restablecer Auto')),
          ElevatedButton(onPressed: () { setState(() { _diasLVManuales = int.tryParse(cLV.text); _diasSabadoManuales = int.tryParse(cS.text); }); _cargarDatosOperador(); Navigator.pop(context); }, child: const Text('Guardar')),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    double pctQuincena = _metaQuincenaTotal > 0 ? (_metrosTotalesQuincena / _metaQuincenaTotal) : 0;
    double pctRitmo = _metaRitmoActual > 0 ? (_metrosTotalesQuincena / _metaRitmoActual) : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Producción: $_nombreOperador', style: const TextStyle(fontSize: 16, color: Colors.white)),
        backgroundColor: const Color(0xFF1E2265),
        actions: [
          IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: _mostrarConfigDias),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: () async { await Supabase.instance.client.auth.signOut(); if(mounted) Navigator.pushReplacementNamed(context, '/'); }),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // BARRA 1: META TOTAL DE LA QUINCENA
            Container(
              padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Progreso Quincena Total', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_metrosTotalesQuincena.toInt()} / ${_metaQuincenaTotal.toInt()} m', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('${(pctQuincena * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 18, color: Color(0xFF1E2265), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: pctQuincena.clamp(0.0, 1.0), backgroundColor: Colors.grey.shade200, color: const Color(0xFF1E2265), minHeight: 8),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // BARRA 2: RITMO (Basado en registros capturados)
            Container(
              padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFE8F5E9), border: Border.all(color: Colors.green.shade300), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ritmo de Trabajo (Según días laborados)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_metrosTotalesQuincena.toInt()} / ${_metaRitmoActual.toInt()} m', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('${(pctRitmo * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: pctRitmo.clamp(0.0, 1.0), backgroundColor: Colors.white, color: Colors.green, minHeight: 8),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // FORMULARIO
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Captura de Metros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (_idRegistroEditando != null)
                  TextButton.icon(onPressed: _limpiarFormulario, icon: const Icon(Icons.cancel, color: Colors.red), label: const Text('Cancelar Edición', style: TextStyle(color: Colors.red))),
              ],
            ),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _fechaSeleccionada, firstDate: DateTime(2024), lastDate: DateTime.now());
                if(d != null) setState(() => _fechaSeleccionada = d);
              },
              child: Container(
                padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Fecha: ${_fechaSeleccionada.toString().split(' ')[0]}', style: const TextStyle(fontWeight: FontWeight.bold)), const Icon(Icons.calendar_month)]),
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(4, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [SizedBox(width: 60, child: Text('Telar ${i+1}:')), Expanded(child: TextField(controller: _telarControllers[i], keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)))]),
            )),
            TextField(controller: _notasController, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(onPressed: _verificarYGuardar, icon: const Icon(Icons.save), label: Text(_idRegistroEditando != null ? 'Actualizar Registro' : 'Guardar Nuevo Registro'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2265), foregroundColor: Colors.white)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton.icon(onPressed: _archivarQuincena, icon: const Icon(Icons.archive), label: const Text('Archivar y Limpiar Quincena'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red))),
            ),
            
            const Divider(height: 40),
            const Text('Historial Activo (Toca para editar)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _historialQuincena.isEmpty 
              ? const Text('Pantalla limpia. Inicia tus registros.') 
              : ListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _historialQuincena.length,
                  itemBuilder: (ctx, i) {
                    final h = _historialQuincena[i];
                    final total = (h['t1_metros']??0)+(h['t2_metros']??0)+(h['t3_metros']??0)+(h['t4_metros']??0);
                    return Card(
                      color: _idRegistroEditando == h['id'] ? Colors.yellow.shade100 : Colors.white,
                      child: ListTile(
                        onTap: () => _cargarRegistroParaEditar(h),
                        title: Text('Fecha: ${h['fecha']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('T1:${h['t1_metros']} T2:${h['t2_metros']} T3:${h['t3_metros']} T4:${h['t4_metros']}'),
                        trailing: Text('${total.toInt()}m', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E2265))),
                      ),
                    );
                  }
                )
          ],
        ),
      ),
    );
  }
}