import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/calculadora_produccion.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<dynamic> _todosLosRegistros = [];
  List<dynamic> _registrosFiltrados = [];
  bool _isLoadingDashboard = true;
  

  // NUEVAS VARIABLES PARA FILTROS
  String _tipoFiltro = 'Operador'; // 'Operador', 'Fecha', 'Rango'
  final _busquedaController = TextEditingController();
  final _fechaInicioController = TextEditingController();
  final _fechaFinController = TextEditingController();

  final _nombreController = TextEditingController();
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _maquinaSeleccionada;
  String _turnoSeleccionado = 'C';
  bool _isLoadingForm = false;

  final List<String> _opcionesMaquinas = [
    'T-01 al T-04', 'T-05 al T-08', 'T-15 al T-18', 
    'T-19 al T-22', 'T-23 al T-26', 'T-27 al T-30', 
    'T-31 al T-34', 'T-35 al T-38', 'T-39 al T-42', 'T-43 al T-46'
  ];

  @override
  void initState() {
    super.initState();
    _cargarRegistros();
  }

  Future<void> _cargarRegistros() async {
    setState(() => _isLoadingDashboard = true);
    try {
      final response = await Supabase.instance.client
          .from('registros_produccion')
          .select('*, perfiles(nombre_completo)')
          .order('fecha', ascending: false);

      setState(() {
        _todosLosRegistros = response;
        _aplicarFiltro();
      });
    } catch (e) {
      _mostrarSnackBar('Error al cargar registros: $e', Colors.red);
    } finally {
      setState(() => _isLoadingDashboard = false);
    }
  }

  // LÓGICA DE FILTRADO AVANZADA
  void _aplicarFiltro() {
    setState(() {
      if (_tipoFiltro == 'Operador') {
        final query = _busquedaController.text.toLowerCase().trim();
        _registrosFiltrados = _todosLosRegistros.where((reg) {
          final nombre = (reg['perfiles']?['nombre_completo'] ?? '').toString().toLowerCase();
          return nombre.contains(query);
        }).toList();
      } else if (_tipoFiltro == 'Fecha') {
        _registrosFiltrados = _todosLosRegistros.where((reg) => 
            (reg['fecha'] ?? '').toString() == _busquedaController.text.trim()
        ).toList();
      } else if (_tipoFiltro == 'Rango') {
        _registrosFiltrados = _todosLosRegistros.where((reg) {
          final f = (reg['fecha'] ?? '').toString();
          return f.compareTo(_fechaInicioController.text.trim()) >= 0 && 
                 f.compareTo(_fechaFinController.text.trim()) <= 0;
        }).toList();
      }
    });
  }

  

  void _copiarAExcel() {
    if (_registrosFiltrados.isEmpty) {
      _mostrarSnackBar('No hay datos para copiar', Colors.orange);
      return;
    }
    String tsvData = "Fecha\tOperador\tTelar 1\tTelar 2\tTelar 3\tTelar 4\tTotal Metros\tNotas\n";
    for (var reg in _registrosFiltrados) {
      final fecha = reg['fecha'] ?? '';
      final nombre = reg['perfiles']?['nombre_completo'] ?? 'Desconocido';
      final total = (reg['t1_metros'] ?? 0) + (reg['t2_metros'] ?? 0) + (reg['t3_metros'] ?? 0) + (reg['t4_metros'] ?? 0);
      final notas = (reg['notas'] ?? '').toString().replaceAll('\n', ' ');
      tsvData += "$fecha\t$nombre\t${reg['t1_metros']}\t${reg['t2_metros']}\t${reg['t3_metros']}\t${reg['t4_metros']}\t$total\t$notas\n";
    }
    Clipboard.setData(ClipboardData(text: tsvData)).then((_) {
      _mostrarSnackBar('Copiado. Pégalo en Excel.', Colors.green);
    });
  }

  // ... (tus funciones _mostrarDialogoAjustes y _mostrarDialogoAlta permanecen iguales) ...
  void _mostrarDialogoAjustes() {
    final metaCtrl = TextEditingController(text: CalculadoraProduccion.metaPorHora.toStringAsFixed(2));
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Ajustes Generales'), content: TextField(controller: metaCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Meta por Hora (1 Telar)', border: OutlineInputBorder())), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), ElevatedButton(onPressed: () { final nuevaMeta = double.tryParse(metaCtrl.text); if (nuevaMeta != null) { CalculadoraProduccion.metaPorHora = nuevaMeta; Navigator.pop(context); _mostrarSnackBar('Meta actualizada', Colors.green); } }, child: const Text('Guardar'))]));
  }

  void _mostrarDialogoAlta() {
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setStateDialog) => AlertDialog(title: const Text('Dar de Alta Nuevo Operador'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre')), TextField(controller: _usuarioController, decoration: const InputDecoration(labelText: 'Usuario/Nómina')), TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true), DropdownButtonFormField<String>(value: _maquinaSeleccionada, items: _opcionesMaquinas.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setStateDialog(() => _maquinaSeleccionada = v), decoration: const InputDecoration(labelText: 'Máquinas')), DropdownButtonFormField<String>(value: _turnoSeleccionado, items: const [DropdownMenuItem(value: 'A', child: Text('Turno A')), DropdownMenuItem(value: 'B', child: Text('Turno B')), DropdownMenuItem(value: 'C', child: Text('Turno C'))], onChanged: (v) => setStateDialog(() => _turnoSeleccionado = v!), decoration: const InputDecoration(labelText: 'Turno'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), ElevatedButton(onPressed: _isLoadingForm ? null : () async { setStateDialog(() => _isLoadingForm = true); try { await Supabase.instance.client.functions.invoke('crear-operador', body: {'usuario': _usuarioController.text.trim(), 'password': _passwordController.text.trim(), 'nombreCompleto': _nombreController.text.trim(), 'turno': _turnoSeleccionado, 'maquinas': _maquinaSeleccionada}); Navigator.pop(context); _mostrarSnackBar('Operador Registrado', Colors.green); } catch (e) { _mostrarSnackBar('Error: $e', Colors.red); } finally { setStateDialog(() => _isLoadingForm = false); } }, child: _isLoadingForm ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Registrar'))])));
  }

  void _mostrarSnackBar(String msg, Color color) {
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de Administración', style: TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1E2265), actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: () async { await Supabase.instance.client.auth.signOut(); if(mounted) Navigator.pushReplacementNamed(context, '/'); })]),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(children: [Expanded(child: ElevatedButton.icon(onPressed: _mostrarDialogoAlta, icon: const Icon(Icons.person_add), label: const Text('Nuevo Operador'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2265), foregroundColor: Colors.white, padding: const EdgeInsets.all(16)))), const SizedBox(width: 16), Expanded(child: ElevatedButton.icon(onPressed: _mostrarDialogoAjustes, icon: const Icon(Icons.settings), label: const Text('Ajustes (Meta)'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A99D), foregroundColor: Colors.white, padding: const EdgeInsets.all(16))))]),
            const SizedBox(height: 24),
            
            // FILTROS AVANZADOS
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _tipoFiltro,
                          items: ['Operador', 'Fecha', 'Rango'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setState(() => _tipoFiltro = v!),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _tipoFiltro == 'Rango' 
                            ? Row(children: [
                                Expanded(child: TextField(controller: _fechaInicioController, decoration: const InputDecoration(hintText: 'Inicio (YYYY-MM-DD)'))),
                                const SizedBox(width: 5),
                                Expanded(child: TextField(controller: _fechaFinController, decoration: const InputDecoration(hintText: 'Fin (YYYY-MM-DD)'))),
                              ])
                            : TextField(controller: _busquedaController, decoration: InputDecoration(hintText: 'Buscar por $_tipoFiltro...')),
                        ),
                        IconButton(icon: const Icon(Icons.search), onPressed: _aplicarFiltro)
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _copiarAExcel, icon: const Icon(Icons.copy), label: const Text('Copiar a Excel'))),
            
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingDashboard ? const Center(child: CircularProgressIndicator()) : ListView.builder(
                itemCount: _registrosFiltrados.length,
                itemBuilder: (context, index) {
                  final reg = _registrosFiltrados[index];
                  final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
                  final total = (reg['t1_metros']??0) + (reg['t2_metros']??0) + (reg['t3_metros']??0) + (reg['t4_metros']??0);
                  return Card(child: ListTile(title: Text('$nombre • ${reg['fecha']}', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('T1:${reg['t1_metros']} T2:${reg['t2_metros']} T3:${reg['t3_metros']} T4:${reg['t4_metros']}\nNotas: ${reg['notas']}'), trailing: Text('${total.toInt()}m', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E2265)))));
                },
              )
            )
          ],
        ),
      ),
    );
  }
}