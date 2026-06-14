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

  // VARIABLES PARA FILTROS
  String _tipoFiltro = 'Operador';
  final _busquedaController = TextEditingController();
  final _fechaInicioController = TextEditingController();
  final _fechaFinController = TextEditingController();

  // Variables para los Dropdowns dinámicos
  List<String> _listaOperadores = [];
  String? _operadorSeleccionadoFiltro;
  final Set<String> _turnosSeleccionadosFiltro = {'A'};

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    }
  }

  Future<void> _seleccionarFecha(
    BuildContext context,
    TextEditingController controlador,
  ) async {
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
        controlador.text =
            "${seleccion.year}-${seleccion.month.toString().padLeft(2, '0')}-${seleccion.day.toString().padLeft(2, '0')}";
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
          return _turnosSeleccionadosFiltro.contains(turno);
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
          final turno = reg['perfiles']?['turno_laboral'] ?? '';
          return f.compareTo(inicio) >= 0 &&
              f.compareTo(fin) <= 0 &&
              _turnosSeleccionadosFiltro.contains(turno);
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
      _operadorSeleccionadoFiltro = _listaOperadores.isNotEmpty
          ? _listaOperadores.first
          : null;
      _turnosSeleccionadosFiltro
        ..clear()
        ..add('A');
      _registrosFiltrados = _todosLosRegistros;
    });
  }

  String _limpiarCeldaExcel(dynamic valor) {
    return (valor ?? '')
        .toString()
        .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
        .trim();
  }

  double _totalRegistro(dynamic reg) {
    return ((reg['t1_metros'] ?? 0) +
            (reg['t2_metros'] ?? 0) +
            (reg['t3_metros'] ?? 0) +
            (reg['t4_metros'] ?? 0))
        .toDouble();
  }

  DateTime? _fechaRegistro(dynamic reg) {
    final fecha = reg['fecha']?.toString();
    if (fecha == null || fecha.isEmpty) return null;
    return DateTime.tryParse(fecha);
  }

  double _calcularMetaPeriodo(String turno, DateTime inicio, DateTime fin) {
    double meta = 0;
    DateTime dia = DateTime(inicio.year, inicio.month, inicio.day);
    final ultimoDia = DateTime(fin.year, fin.month, fin.day);

    while (!dia.isAfter(ultimoDia)) {
      meta += CalculadoraProduccion.calcularMetaDiariaMetros(turno, dia);
      dia = dia.add(const Duration(days: 1));
    }

    return meta;
  }

  List<Map<String, dynamic>> _rankingOperadores() {
    final agrupado = <String, Map<String, dynamic>>{};

    for (final reg in _registrosFiltrados) {
      final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
      final turno = reg['perfiles']?['turno_laboral'] ?? '-';
      final fecha = _fechaRegistro(reg);

      final item = agrupado.putIfAbsent(
        nombre,
        () => {
          'nombre': nombre,
          'turno': turno,
          'total': 0.0,
          'inicio': fecha,
          'fin': fecha,
        },
      );

      item['total'] = (item['total'] as double) + _totalRegistro(reg);
      if (fecha != null) {
        final inicioActual = item['inicio'] as DateTime?;
        final finActual = item['fin'] as DateTime?;
        if (inicioActual == null || fecha.isBefore(inicioActual)) {
          item['inicio'] = fecha;
        }
        if (finActual == null || fecha.isAfter(finActual)) {
          item['fin'] = fecha;
        }
      }
    }

    final inicioFiltro = _tipoFiltro == 'Rango'
        ? DateTime.tryParse(_fechaInicioController.text)
        : null;
    final finFiltro = _tipoFiltro == 'Rango'
        ? DateTime.tryParse(_fechaFinController.text)
        : null;

    for (final item in agrupado.values) {
      final inicio = inicioFiltro ?? (item['inicio'] as DateTime?);
      final fin = finFiltro ?? (item['fin'] as DateTime?);
      final turno = item['turno']?.toString() ?? '-';
      final total = item['total'] as double;
      final meta = inicio == null || fin == null
          ? 0.0
          : _calcularMetaPeriodo(turno, inicio, fin);

      item['meta'] = meta;
      item['porcentaje'] = meta <= 0 ? 0.0 : (total / meta) * 100;
    }

    final ranking = agrupado.values.toList();
    ranking.sort(
      (a, b) => (b['total'] as double).compareTo(a['total'] as double),
    );
    return ranking;
  }

  Widget _buildSelectorTurnos() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['A', 'B', 'C'].map((turno) {
        final seleccionado = _turnosSeleccionadosFiltro.contains(turno);
        return FilterChip(
          label: Text('Turno $turno'),
          selected: seleccionado,
          onSelected: (valor) {
            setState(() {
              if (valor) {
                _turnosSeleccionadosFiltro.add(turno);
              } else if (_turnosSeleccionadosFiltro.length > 1) {
                _turnosSeleccionadosFiltro.remove(turno);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildRankingOperadores() {
    final ranking = _rankingOperadores();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ranking',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (ranking.isEmpty)
              const Text(
                'Sin registros filtrados.',
                style: TextStyle(color: Colors.black54),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowHeight: 34,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 46,
                    columnSpacing: 14,
                    columns: const [
                      DataColumn(label: Text('Operador')),
                      DataColumn(label: Text('Mts')),
                      DataColumn(label: Text('%')),
                    ],
                    rows: ranking.map((item) {
                      final nombre = item['nombre']?.toString() ?? 'N/A';
                      final turno = item['turno']?.toString() ?? '-';
                      final total = item['total'] as double;
                      final porcentaje = item['porcentaje'] as double;

                      return DataRow(
                        cells: [
                          DataCell(Text('$nombre\nT$turno')),
                          DataCell(Text(total.toStringAsFixed(0))),
                          DataCell(Text('${porcentaje.toStringAsFixed(1)}%')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistrosConRanking() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ListView.builder(
            itemCount: _registrosFiltrados.length,
            itemBuilder: (context, index) {
              final reg = _registrosFiltrados[index];
              final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
              final turno = reg['perfiles']?['turno_laboral'] ?? '-';
              final total = _totalRegistro(reg);

              return Card(
                child: ListTile(
                  title: Text(
                    '$nombre (Turno $turno) - ${reg['fecha']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'T1:${reg['t1_metros']} T2:${reg['t2_metros']} T3:${reg['t3_metros']} T4:${reg['t4_metros']}\nNotas: ${reg['notas']}',
                  ),
                  trailing: Text(
                    '${total.toInt()}m',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E2265),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 360, child: _buildRankingOperadores()),
      ],
    );
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
      SnackBar(
        content: Text(
          '${_registrosFiltrados.length} registros copiados para Excel',
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Future<void> _mostrarDialogoNuevoOperador() async {
    final nombreCtrl = TextEditingController();
    final usuarioCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String turnoSel = 'A';
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final double keyboardPadding = MediaQuery.of(
              context,
            ).viewInsets.bottom;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  top: 20,
                  left: 20,
                  right: 20,
                  bottom: 20 + keyboardPadding,
                ),
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dar de Alta Operador',
                        style: TextStyle(
                          color: Color(0xFF1E2265),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: usuarioCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Usuario / Nómina',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña temporal (mín. 6)',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: turnoSel,
                        decoration: const InputDecoration(
                          labelText: 'Turno',
                          border: OutlineInputBorder(),
                        ),
                        items: ['A', 'B', 'C']
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text('Turno $t'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setStateDialog(() => turnoSel = val!),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () => Navigator.pop(ctx),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    if (nombreCtrl.text.trim().isEmpty ||
                                        usuarioCtrl.text.trim().isEmpty ||
                                        passCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Por favor llena todos los campos',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }
                                    if (passCtrl.text.trim().length < 6) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'La contraseña debe tener al menos 6 caracteres',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    setStateDialog(() => isLoading = true);
                                    try {
                                      final correoGenerado =
                                          '${usuarioCtrl.text.trim().toLowerCase()}@gs.com';

                                      // Registro limpio utilizando la instancia global inicializada
                                      final res = await Supabase
                                          .instance
                                          .client
                                          .auth
                                          .signUp(
                                            email: correoGenerado,
                                            password: passCtrl.text.trim(),
                                          );

                                      if (res.user != null) {
                                        // Inserción o actualización en cascada del perfil creado
                                        await Supabase.instance.client
                                            .from('perfiles')
                                            .upsert({
                                              'id': res.user!.id,
                                              'nombre_completo': nombreCtrl.text
                                                  .trim(),
                                              'turno_laboral': turnoSel,
                                              'rol': 'operador',
                                            });
                                      }

                                      if (mounted) {
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Operador creado con éxito',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        _cargarDashboard();
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error: ${e.toString().replaceAll("AuthApiError:", "")}',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    } finally {
                                      if (mounted)
                                        setStateDialog(() => isLoading = false);
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E2265),
                              foregroundColor: Colors.white,
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFiltroDinamico() {
    if (_tipoFiltro == 'Operador') {
      return DropdownButtonFormField<String>(
        value: _operadorSeleccionadoFiltro,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: _listaOperadores
            .map((op) => DropdownMenuItem(value: op, child: Text(op)))
            .toList(),
        onChanged: (val) => setState(() => _operadorSeleccionadoFiltro = val),
      );
    } else if (_tipoFiltro == 'Turno') {
      return _buildSelectorTurnos();
    } else if (_tipoFiltro == 'Fecha') {
      return TextField(
        controller: _busquedaController,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Seleccionar Fecha',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_month),
        ),
        onTap: () => _seleccionarFecha(context, _busquedaController),
      );
    } else if (_tipoFiltro == 'Rango') {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _fechaInicioController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Inicio',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_month),
              ),
              onTap: () => _seleccionarFecha(context, _fechaInicioController),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _fechaFinController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Fin',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_month),
              ),
              onTap: () => _seleccionarFecha(context, _fechaFinController),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildSelectorTurnos()),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Panel de Administrador',
          style: TextStyle(color: Colors.white),
        ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _tipoFiltro,
                          items: ['Operador', 'Fecha', 'Rango', 'Turno']
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
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
                          icon: const Icon(
                            Icons.search,
                            color: Color(0xFF1E2265),
                            size: 30,
                          ),
                          onPressed: _aplicarFiltro,
                        ),
                        IconButton(
                          tooltip: 'Borrar filtros',
                          icon: const Icon(
                            Icons.filter_alt_off,
                            color: Colors.redAccent,
                            size: 28,
                          ),
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
              child: Wrap(
                spacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _mostrarDialogoNuevoOperador,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Nuevo Operador'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _copiarAExcel,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar a Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E2265),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingDashboard
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1E2265),
                      ),
                    )
                  : _buildRegistrosConRanking(),
            ),
          ],
        ),
      ),
    );
  }
}
