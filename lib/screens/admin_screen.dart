import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<dynamic> _todosLosRegistros = [];
  List<dynamic> _registrosFiltrados = [];
  bool _isLoadingDashboard = true;
  
  // VARIABLES PARA FILTROS
  String _tipoFiltro = 'Operador'; 
  final _busquedaController = TextEditingController();
  final _fechaInicioController = TextEditingController();
  final _fechaFinController = TextEditingController();
  
  // Variables para los Dropdowns dinámicos
  List<String> _listaOperadores = [];
  String? _operadorSeleccionadoFiltro;
  String _turnoSeleccionadoFiltro = 'A';

  @override
  void initState() {
    super.initState();
    _cargarDashboard();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _fechaInicioController.dispose();
    _fechaFinController.dispose();
    super.dispose();
  }

  Future<void> _cargarDashboard() async {
    setState(() => _isLoadingDashboard = true);
    try {
      final response = await Supabase.instance.client
          .from('registros_produccion')
          .select('*, perfiles(nombre_completo, turno_laboral)')
          .order('fecha', ascending: false);
          
      final operadoresResponse = await Supabase.instance.client
          .from('perfiles')
          .select('nombre_completo')
          .eq('rol', 'operador');
          
      final Set<String> opsUnicos = {};
      for (var op in operadoresResponse) {
        if (op['nombre_completo'] != null) {
          opsUnicos.add(op['nombre_completo']);
        }
      }

      setState(() {
        _todosLosRegistros = response;
        _registrosFiltrados = response;
        _listaOperadores = opsUnicos.toList();
        if (_listaOperadores.isNotEmpty) {
          _operadorSeleccionadoFiltro = _listaOperadores.first;
        }
        _isLoadingDashboard = false;
      });
    } catch (e) {
      setState(() => _isLoadingDashboard = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    }
  }

  Future<void> _seleccionarFecha(BuildContext context, TextEditingController controlador) async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E2265),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (seleccion != null) {
      setState(() {
        controlador.text = "${seleccion.year}-${seleccion.month.toString().padLeft(2, '0')}-${seleccion.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _aplicarFiltro() {
    setState(() {
      if (_tipoFiltro == 'Operador') {
        final query = _operadorSeleccionadoFiltro ?? '';
        _registrosFiltrados = _todosLosRegistros.where((reg) {
          final nombre = reg['perfiles']?['nombre_completo'] ?? '';
          return nombre == query;
        }).toList();
      } else if (_tipoFiltro == 'Turno') {
        _registrosFiltrados = _todosLosRegistros.where((reg) {
          final turno = reg['perfiles']?['turno_laboral'] ?? '';
          return turno == _turnoSeleccionadoFiltro;
        }).toList();
      } else if (_tipoFiltro == 'Fecha') {
        final query = _busquedaController.text;
        if (query.isEmpty) {
          _registrosFiltrados = _todosLosRegistros;
          return;
        }
        _registrosFiltrados = _todosLosRegistros.where((reg) {
          return reg['fecha'].toString().contains(query);
        }).toList();
      } else if (_tipoFiltro == 'Rango') {
        final inicio = _fechaInicioController.text;
        final fin = _fechaFinController.text;
        if (inicio.isEmpty || fin.isEmpty) return;
        
        _registrosFiltrados = _todosLosRegistros.where((reg) {
          final f = reg['fecha'].toString();
          return f.compareTo(inicio) >= 0 && f.compareTo(fin) <= 0;
        }).toList();
      }
    });
  }

  void _limpiarFiltros() {
    setState(() {
      _tipoFiltro = 'Operador';
      _busquedaController.clear();
      _fechaInicioController.clear();
      _fechaFinController.clear();
      _operadorSeleccionadoFiltro = _listaOperadores.isNotEmpty ? _listaOperadores.first : null;
      _turnoSeleccionadoFiltro = 'A';
      _registrosFiltrados = _todosLosRegistros;
    });
  }

  String _limpiarCeldaExcel(dynamic valor) {
    return (valor ?? '').toString().replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  }

  Future<void> _copiarAExcel() async {
    if (_registrosFiltrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para copiar')),
      );
      return;
    }

    final filas = <List<String>>[
      ['Fecha', 'Operador', 'Turno', 'T1', 'T2', 'T3', 'T4', 'Total', 'Notas'],
    ];

    for (final reg in _registrosFiltrados) {
      final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
      final turno = reg['perfiles']?['turno_laboral'] ?? '-';
      final t1 = reg['t1_metros'] ?? 0;
      final t2 = reg['t2_metros'] ?? 0;
      final t3 = reg['t3_metros'] ?? 0;
      final t4 = reg['t4_metros'] ?? 0;
      final total = (t1 ?? 0) + (t2 ?? 0) + (t3 ?? 0) + (t4 ?? 0);

      filas.add([
        _limpiarCeldaExcel(reg['fecha']),
        _limpiarCeldaExcel(nombre),
        _limpiarCeldaExcel(turno),
        _limpiarCeldaExcel(t1),
        _limpiarCeldaExcel(t2),
        _limpiarCeldaExcel(t3),
        _limpiarCeldaExcel(t4),
        _limpiarCeldaExcel(total),
        _limpiarCeldaExcel(reg['notas']),
      ]);
    }

    final texto = filas.map((fila) => fila.join('\t')).join('\n');
    await Clipboard.setData(ClipboardData(text: texto));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_registrosFiltrados.length} registros copiados para Excel')),
    );
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Widget _buildFiltroDinamico() {
    if (_tipoFiltro == 'Operador') {
      return DropdownButtonFormField<String>(
        initialValue: _operadorSeleccionadoFiltro,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: _listaOperadores.map((op) => DropdownMenuItem(value: op, child: Text(op))).toList(),
        onChanged: (val) => setState(() => _operadorSeleccionadoFiltro = val),
      );
    } else if (_tipoFiltro == 'Turno') {
      return DropdownButtonFormField<String>(
        initialValue: _turnoSeleccionadoFiltro,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: ['A', 'B', 'C'].map((t) => DropdownMenuItem(value: t, child: Text('Turno $t'))).toList(),
        onChanged: (val) => setState(() => _turnoSeleccionadoFiltro = val!),
      );
    } else if (_tipoFiltro == 'Fecha') {
      return TextField(
        controller: _busquedaController,
        readOnly: true, 
        decoration: const InputDecoration(labelText: 'Seleccionar Fecha', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_month)),
        onTap: () => _seleccionarFecha(context, _busquedaController),
      );
    } else if (_tipoFiltro == 'Rango') {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _fechaInicioController,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Inicio', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_month)),
              onTap: () => _seleccionarFecha(context, _fechaInicioController),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _fechaFinController,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Fin', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_month)),
              onTap: () => _seleccionarFecha(context, _fechaFinController),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administrador', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E2265),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _tipoFiltro,
                          items: ['Operador', 'Fecha', 'Rango', 'Turno']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _tipoFiltro = val!;
                              _busquedaController.clear();
                              _fechaInicioController.clear();
                              _fechaFinController.clear();
                            });
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _buildFiltroDinamico()),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.search, color: Color(0xFF1E2265), size: 30),
                          onPressed: _aplicarFiltro,
                        ),
                        IconButton(
                          tooltip: 'Borrar filtros',
                          icon: const Icon(Icons.filter_alt_off, color: Colors.redAccent, size: 28),
                          onPressed: _limpiarFiltros,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _copiarAExcel,
                icon: const Icon(Icons.copy),
                label: const Text('Copiar a Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2265),
                  foregroundColor: Colors.white,
                ),
              )
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingDashboard 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E2265))) 
                : ListView.builder(
                itemCount: _registrosFiltrados.length,
                itemBuilder: (context, index) {
                  final reg = _registrosFiltrados[index];
                  final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
                  final turno = reg['perfiles']?['turno_laboral'] ?? '-';
                  final total = (reg['t1_metros']??0) + (reg['t2_metros']??0) + (reg['t3_metros']??0) + (reg['t4_metros']??0);
                  
                  return Card(
                    child: ListTile(
                      title: Text('$nombre (Turno $turno) • ${reg['fecha']}', style: const TextStyle(fontWeight: FontWeight.bold)), 
                      subtitle: Text('T1:${reg['t1_metros']} T2:${reg['t2_metros']} T3:${reg['t3_metros']} T4:${reg['t4_metros']}\nNotas: ${reg['notas']}'), 
                      trailing: Text('${total.toInt()}m', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E2265))),
                    )
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
