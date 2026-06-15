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
  final List<TextEditingController> _telarControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );

  String _nombreOperador = 'Cargando...';
  String _turnoLaboral = 'A';

  double _metrosTotalesQuincena = 0.0;
  double _metaQuincenaTotal = 0.0;
  double _metaRitmoActual = 0.0;

  DateTime _fechaSeleccionada = DateTime.now();
  String? _idRegistroEditando;
  List<dynamic> _historialQuincena = [];
  List<Map<String, dynamic>> _rankingQuincena = [];
  bool _isLoading = true;
  bool _isLoadingRanking = false;
  String _turnoFiltroRanking = 'Todos';

  int? _diasLVManuales;
  int? _diasSabadoManuales;

  @override
  void initState() {
    super.initState();
    _cargarDatosOperador();
  }

  @override
  void dispose() {
    _notasController.dispose();
    for (final controller in _telarControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatosOperador() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final perfil = await Supabase.instance.client
          .from('perfiles')
          .select('nombre_completo, turno_laboral')
          .eq('id', user.id)
          .single();

      if (!mounted) return;
      setState(() {
        _nombreOperador = perfil['nombre_completo'] ?? 'Operador';
        _turnoLaboral = perfil['turno_laboral'] ?? 'A';
      });

      await _archivarQuincenaAnteriorSiHaceFalta(user.id);
      await _cargarHistorial();
      await _cargarRankingQuincena();
    } catch (e) {
      debugPrint("Error cargando operador: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cargarHistorial() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final rangos = CalculadoraProduccion.obtenerRangoQuincenaActual();
    final inicio =
        "${rangos['inicio']!.year}-${rangos['inicio']!.month.toString().padLeft(2, '0')}-${rangos['inicio']!.day.toString().padLeft(2, '0')}";
    final fin =
        "${rangos['fin']!.year}-${rangos['fin']!.month.toString().padLeft(2, '0')}-${rangos['fin']!.day.toString().padLeft(2, '0')}";

    final response = await Supabase.instance.client
        .from('registros_produccion')
        .select()
        .eq('operador_id', user.id)
        .gte('fecha', inicio)
        .lte('fecha', fin)
        .order('fecha', ascending: false);

    double sumatoria = 0;
    for (var r in response) {
      sumatoria +=
          (r['t1_metros'] ?? 0) +
          (r['t2_metros'] ?? 0) +
          (r['t3_metros'] ?? 0) +
          (r['t4_metros'] ?? 0);
    }

    if (!mounted) return;
    setState(() {
      _historialQuincena = response;
      _metrosTotalesQuincena = sumatoria;
      _calcularMetas();
    });
  }

  double _totalRegistro(dynamic reg) {
    return ((reg['t1_metros'] ?? 0) +
            (reg['t2_metros'] ?? 0) +
            (reg['t3_metros'] ?? 0) +
            (reg['t4_metros'] ?? 0))
        .toDouble();
  }

  double _calcularMetaRitmoQuincena(String turno) {
    final rango = CalculadoraProduccion.obtenerRangoQuincenaActual();
    final inicio = rango['inicio']!;
    final fin = rango['fin']!;
    final hoy = DateTime.now();
    final limite = hoy.isAfter(fin) ? fin : hoy;

    double meta = 0;
    DateTime dia = DateTime(inicio.year, inicio.month, inicio.day);
    final ultimoDia = DateTime(limite.year, limite.month, limite.day);

    while (!dia.isAfter(ultimoDia)) {
      meta += CalculadoraProduccion.calcularMetaDiariaMetros(turno, dia);
      dia = dia.add(const Duration(days: 1));
    }

    return meta;
  }

  Future<void> _cargarRankingQuincena() async {
    setState(() => _isLoadingRanking = true);
    try {
      final rangos = CalculadoraProduccion.obtenerRangoQuincenaActual();
      final inicio = _formatearFecha(rangos['inicio']!);
      final fin = _formatearFecha(rangos['fin']!);

      final response = await Supabase.instance.client
          .from('registros_produccion')
          .select('*, perfiles(nombre_completo, turno_laboral)')
          .gte('fecha', inicio)
          .lte('fecha', fin);

      final agrupado = <String, Map<String, dynamic>>{};
      for (final reg in response) {
        final perfil = reg['perfiles'];
        final nombre = perfil?['nombre_completo'] ?? 'N/A';
        final turno = perfil?['turno_laboral'] ?? '-';
        final item = agrupado.putIfAbsent(
          nombre,
          () => {'nombre': nombre, 'turno': turno, 'total': 0.0},
        );

        item['total'] = (item['total'] as double) + _totalRegistro(reg);
      }

      final ranking = agrupado.values.map((item) {
        final turno = item['turno']?.toString() ?? '-';
        final total = item['total'] as double;
        final metaRitmo = _calcularMetaRitmoQuincena(turno);
        return {
          ...item,
          'metaRitmo': metaRitmo,
          'porcentajeRitmo': metaRitmo <= 0 ? 0.0 : (total / metaRitmo) * 100,
        };
      }).toList();

      ranking.sort(
        (a, b) => (b['total'] as double).compareTo(a['total'] as double),
      );

      if (!mounted) return;
      setState(() => _rankingQuincena = ranking);
    } catch (e) {
      debugPrint("Error cargando ranking: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingRanking = false);
      }
    }
  }

  String _formatearFecha(DateTime fecha) {
    return "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";
  }

  Map<String, DateTime> _obtenerRangoQuincenaAnterior() {
    final hoy = DateTime.now();

    if (hoy.day <= 15) {
      final mesAnterior = DateTime(hoy.year, hoy.month, 0);
      return {
        'inicio': DateTime(mesAnterior.year, mesAnterior.month, 16),
        'fin': mesAnterior,
      };
    }

    return {
      'inicio': DateTime(hoy.year, hoy.month, 1),
      'fin': DateTime(hoy.year, hoy.month, 15),
    };
  }

  Future<void> _archivarQuincenaAnteriorSiHaceFalta(String operadorId) async {
    final rango = _obtenerRangoQuincenaAnterior();
    final inicio = _formatearFecha(rango['inicio']!);
    final fin = _formatearFecha(rango['fin']!);
    final periodo = '$inicio al $fin';

    final historialExistente = await Supabase.instance.client
        .from('historial_quincenas')
        .select('id')
        .eq('operador_id', operadorId)
        .eq('periodo', periodo)
        .maybeSingle();

    if (historialExistente != null) return;

    final registros = await Supabase.instance.client
        .from('registros_produccion')
        .select('t1_metros, t2_metros, t3_metros, t4_metros')
        .eq('operador_id', operadorId)
        .gte('fecha', inicio)
        .lte('fecha', fin);

    if (registros.isEmpty) return;

    double totalMetros = 0;
    for (final registro in registros) {
      totalMetros +=
          (registro['t1_metros'] ?? 0) +
          (registro['t2_metros'] ?? 0) +
          (registro['t3_metros'] ?? 0) +
          (registro['t4_metros'] ?? 0);
    }

    double metaMetros = 0;
    DateTime dia = rango['inicio']!;
    while (!dia.isAfter(rango['fin']!)) {
      metaMetros += CalculadoraProduccion.calcularMetaDiariaMetros(
        _turnoLaboral,
        dia,
      );
      dia = dia.add(const Duration(days: 1));
    }
    final porcentajeCumplido = metaMetros <= 0
        ? 0
        : (totalMetros / metaMetros) * 100;

    await Supabase.instance.client.from('historial_quincenas').insert({
      'operador_id': operadorId,
      'fecha_cierre': _formatearFecha(DateTime.now()),
      'periodo': periodo,
      'total_metros': totalMetros,
      'meta_metros': metaMetros,
      'porcentaje_cumplido': porcentajeCumplido,
    });
  }

  void _calcularMetas() {
    double metaRitmo = 0.0;
    for (var r in _historialQuincena) {
      DateTime f = DateTime.parse(r['fecha']);
      metaRitmo += CalculadoraProduccion.calcularMetaDiariaMetros(
        _turnoLaboral,
        f,
      );
    }

    double metaTotal = CalculadoraProduccion.calcularMetaQuincenalMetros(
      _turnoLaboral,
      diasAsuetoLV: _diasLVManuales,
      diasAsuetoSabado: _diasSabadoManuales,
    );
    setState(() {
      _metaRitmoActual = metaRitmo;
      _metaQuincenaTotal = metaTotal;
    });
  }

  double _calcularPorcentaje(double avance, double meta) {
    if (meta <= 0) return 0;
    return (avance / meta).clamp(0.0, 1.0);
  }

  String _metrosEnteros(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor?.toString() ?? '') ?? 0;
    return numero.round().toString();
  }

  Widget _buildBarraProgreso({
    required String titulo,
    required double avance,
    required double meta,
    required Color color,
  }) {
    final porcentaje = _calcularPorcentaje(avance, meta);
    final porcentajeTexto = (porcentaje * 100).round().toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '$porcentajeTexto%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: porcentaje,
            minHeight: 10,
            backgroundColor: Colors.white,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_metrosEnteros(avance)}m / ${_metrosEnteros(meta)}m',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  String _fechaSeleccionadaTexto() {
    return "${_fechaSeleccionada.year}-${_fechaSeleccionada.month.toString().padLeft(2, '0')}-${_fechaSeleccionada.day.toString().padLeft(2, '0')}";
  }

  Map<String, dynamic> _datosRegistroActual(String operadorId, String fecha) {
    return {
      'operador_id': operadorId,
      'fecha': fecha,
      't1_metros': double.tryParse(_telarControllers[0].text) ?? 0,
      't2_metros': double.tryParse(_telarControllers[1].text) ?? 0,
      't3_metros': double.tryParse(_telarControllers[2].text) ?? 0,
      't4_metros': double.tryParse(_telarControllers[3].text) ?? 0,
      'notas': _notasController.text, // Mantenido fiel a tu columna de Supabase
    };
  }

  Future<void> _guardarRegistro() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final fecha = _fechaSeleccionadaTexto();
    final datos = _datosRegistroActual(user.id, fecha);

    try {
      final response = await Supabase.instance.client
          .from('registros_produccion')
          .select()
          .eq('operador_id', user.id)
          .eq('fecha', fecha);

      final registroExistente = response.isEmpty ? null : response.first;
      final idExistente = registroExistente?['id']?.toString();
      final esElMismoRegistro =
          _idRegistroEditando != null && idExistente == _idRegistroEditando;

      if (registroExistente != null && !esElMismoRegistro) {
        if (!mounted) return;
        final opcion = await _mostrarOpcionesRegistroExistente(fecha);

        if (opcion == 'reemplazar') {
          await Supabase.instance.client
              .from('registros_produccion')
              .update(datos)
              .eq('id', registroExistente['id']);
          _mostrarSnack('Registro reemplazado correctamente');
        } else if (opcion == 'editar_fecha') {
          await _seleccionarFechaUI();
          return;
        } else {
          return;
        }
      } else if (_idRegistroEditando != null) {
        await Supabase.instance.client
            .from('registros_produccion')
            .update(datos)
            .eq('id', _idRegistroEditando!);
        _mostrarSnack('Registro actualizado correctamente');
      } else {
        await Supabase.instance.client
            .from('registros_produccion')
            .insert(datos);
        _mostrarSnack('Registro guardado correctamente');
      }

      _limpiarFormulario();
      await _cargarHistorial();
      await _cargarRankingQuincena();
    } catch (e) {
      _mostrarSnack('Error al guardar: $e');
    }
  }

  void _mostrarSnack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  void _cargarRegistroParaEditar(dynamic r) {
    setState(() {
      _idRegistroEditando = r['id']?.toString();
      _fechaSeleccionada = DateTime.parse(r['fecha']);
      _telarControllers[0].text = _metrosEnteros(r['t1_metros']);
      _telarControllers[1].text = _metrosEnteros(r['t2_metros']);
      _telarControllers[2].text = _metrosEnteros(r['t3_metros']);
      _telarControllers[3].text = _metrosEnteros(r['t4_metros']);
      _notasController.text = r['notas'] ?? '';
    });
    _mostrarSnack('Registro cargado para editar');
  }

  void _limpiarFormulario() {
    setState(() {
      _idRegistroEditando = null;
      _fechaSeleccionada = DateTime.now();
      for (var c in _telarControllers) {
        c.clear();
      }
      _notasController.clear();
    });
  }

  Future<void> _seleccionarFechaUI() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _fechaSeleccionada) {
      setState(() {
        _fechaSeleccionada = picked;
      });
    }
  }

  Future<void> _mostrarConfiguracionMeta() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('DIAS DE ASUETO'),
          content: _buildCamposDiasLaborales(),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Listo'),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _rankingFiltrado() {
    if (_turnoFiltroRanking == 'Todos') return _rankingQuincena;
    return _rankingQuincena
        .where((item) => item['turno']?.toString() == _turnoFiltroRanking)
        .toList();
  }

  Widget _buildFiltroRanking(StateSetter setStateDialog) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['Todos', 'A', 'B', 'C'].map((turno) {
        final seleccionado = _turnoFiltroRanking == turno;
        final label = turno == 'Todos' ? '3 turnos' : 'Turno $turno';

        return ChoiceChip(
          label: Text(label),
          selected: seleccionado,
          selectedColor: const Color(0xFFDBDBF0),
          onSelected: (_) {
            setStateDialog(() => _turnoFiltroRanking = turno);
            setState(() => _turnoFiltroRanking = turno);
          },
        );
      }).toList(),
    );
  }

  Widget _buildItemRanking(Map<String, dynamic> item, int index) {
    final nombre = item['nombre']?.toString() ?? 'N/A';
    final turno = item['turno']?.toString() ?? '-';
    final total = item['total'] as double;
    final porcentaje = item['porcentajeRitmo'] as double;
    final progreso = (porcentaje / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF1E2265),
            foregroundColor: Colors.white,
            child: Text('${index + 1}'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '${_metrosEnteros(total)}m',
                      style: const TextStyle(
                        color: Color(0xFF1E2265),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Turno $turno - Ritmo ${porcentaje.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 9,
                    backgroundColor: const Color(0xFFE8E8F4),
                    color: porcentaje >= 100
                        ? Colors.green
                        : const Color(0xFF1E2265),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarRankingQuincena() async {
    if (_rankingQuincena.isEmpty && !_isLoadingRanking) {
      await _cargarRankingQuincena();
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final ranking = _rankingFiltrado();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBDBF0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.leaderboard,
                              color: Color(0xFF1E2265),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Ranking de quincena',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Actualizar',
                            onPressed: () async {
                              await _cargarRankingQuincena();
                              if (mounted) setStateDialog(() {});
                            },
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildFiltroRanking(setStateDialog),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _isLoadingRanking
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF1E2265),
                                ),
                              )
                            : ranking.isEmpty
                            ? const Center(
                                child: Text(
                                  'Sin registros en la quincena actual.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              )
                            : ListView.separated(
                                itemCount: ranking.length,
                                separatorBuilder: (_, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) =>
                                    _buildItemRanking(ranking[index], index),
                              ),
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

  Widget _buildCamposDiasLaborales() {
    if (_turnoLaboral == 'A' || _turnoLaboral == 'C') {
      return TextFormField(
        initialValue: _diasLVManuales?.toString() ?? '',
        decoration: const InputDecoration(
          labelText: 'Días de asueto totales',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        onChanged: (val) {
          setState(() {
            _diasLVManuales = int.tryParse(val);
            _diasSabadoManuales = 0;
            _calcularMetas();
          });
        },
      );
    } else {
      return Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: _diasLVManuales?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'L-V',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) {
                setState(() {
                  _diasLVManuales = int.tryParse(val);
                  _calcularMetas();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: _diasSabadoManuales?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Sábado',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) {
                setState(() {
                  _diasSabadoManuales = int.tryParse(val);
                  _calcularMetas();
                });
              },
            ),
          ),
        ],
      );
    }
  }

  Future<String?> _mostrarOpcionesRegistroExistente(String fecha) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: const Text('Ya existe un registro'),
                subtitle: Text('Ya tienes produccion guardada para $fecha'),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Reemplazar'),
                subtitle: const Text('Sobrescribir el registro de esa fecha'),
                onTap: () => Navigator.pop(sheetContext, 'reemplazar'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Editar fecha'),
                subtitle: const Text('Elegir otro dia para este registro'),
                onTap: () => Navigator.pop(sheetContext, 'editar_fecha'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancelar'),
                onTap: () => Navigator.pop(sheetContext, 'cancelar'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1E2265)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Hola, $_nombreOperador (Turno $_turnoLaboral)',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1E2265),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Ranking de quincena',
            onPressed: _mostrarRankingQuincena,
            icon: const Icon(Icons.leaderboard),
          ),
          IconButton(
            tooltip: 'Historial de Quincenas',
            onPressed: () => Navigator.pushNamed(context, '/historial'),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Configurar meta',
            onPressed: _mostrarConfiguracionMeta,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: const Color(0xFFDBDBF0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Tu Meta Es De: ${_metaQuincenaTotal.toStringAsFixed(0)}m',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildBarraProgreso(
                      titulo: 'Progreso de quincena',
                      avance: _metrosTotalesQuincena,
                      meta: _metaQuincenaTotal,
                      color: const Color(0xFF1E2265),
                    ),
                    const SizedBox(height: 12),
                    _buildBarraProgreso(
                      titulo: 'Ritmo actual',
                      avance: _metrosTotalesQuincena,
                      meta: _metaRitmoActual,
                      color: Colors.green,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fecha: ${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _seleccionarFechaUI,
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _telarControllers[0],
                    decoration: const InputDecoration(
                      labelText: 'T-01 (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _telarControllers[1],
                    decoration: const InputDecoration(
                      labelText: 'T-02 (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _telarControllers[2],
                    decoration: const InputDecoration(
                      labelText: 'T-03 (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _telarControllers[3],
                    decoration: const InputDecoration(
                      labelText: 'T-04 (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notasController,
              decoration: const InputDecoration(
                labelText: 'Notas / Observaciones',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _guardarRegistro,
                icon: const Icon(Icons.save),
                label: Text(
                  _idRegistroEditando == null
                      ? 'Guardar Producción'
                      : 'Actualizar Registro',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2265),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (_idRegistroEditando != null)
              TextButton(
                onPressed: _limpiarFormulario,
                child: const Text(
                  'Cancelar Edición',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            const Divider(height: 40),
            const Text(
              'Historial Activo (Toca para editar)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _historialQuincena.isEmpty
                ? const Text('Pantalla limpia. Inicia tus registros.')
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _historialQuincena.length,
                    itemBuilder: (ctx, i) {
                      final h = _historialQuincena[i];
                      final total =
                          (h['t1_metros'] ?? 0) +
                          (h['t2_metros'] ?? 0) +
                          (h['t3_metros'] ?? 0) +
                          (h['t4_metros'] ?? 0);
                      final estaEditando =
                          _idRegistroEditando == h['id']?.toString();

                      return Card(
                        color: estaEditando
                            ? Colors.yellow.shade100
                            : Colors.white,
                        child: ListTile(
                          onTap: () => _cargarRegistroParaEditar(h),
                          title: Text(
                            'Fecha: ${h['fecha']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'T1:${_metrosEnteros(h['t1_metros'])} T2:${_metrosEnteros(h['t2_metros'])} T3:${_metrosEnteros(h['t3_metros'])} T4:${_metrosEnteros(h['t4_metros'])}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_metrosEnteros(total)}m',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1E2265),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                estaEditando ? Icons.edit_note : Icons.edit,
                                color: const Color(0xFF1E2265),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
