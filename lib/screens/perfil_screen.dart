import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  String _nombre = 'rigo';
  String _rangoMaquinas = 'Selecciona el rango';
  String _turno = 'A';

  @override
  void initState() {
    super.initState();
    _obtenerConfiguracionesLocales();
  }

  Future<void> _obtenerConfiguracionesLocales() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final perfil = await Supabase.instance.client.from('perfiles').select('nombre_completo, turno_laboral').eq('id', user.id).single();
    final maq = await Supabase.instance.client.from('maquinas_operador').select('rango_maquinas').eq('operador_id', user.id).maybeSingle();

    setState(() {
      _nombre = perfil['nombre_completo'] ?? 'rigo';
      _turno = perfil['turno_laboral'] ?? 'A';
      if (maq != null) _rangoMaquinas = maq['rango_maquinas'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Perfil'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Datos del Operador', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Nombre Completo', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(_nombre, style: const TextStyle(fontSize: 16, color: Colors.black)),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on),
              title: const Text('Rango de Máquinas', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(_rangoMaquinas),
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Turno Laboral', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text('Turno $_turno'),
            ),
            const Divider(),
            const Text('Parámetros de Producción', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
            const ListTile(
              leading: Icon(Icons.speed),
              title: Text('Meta por hora de una máquina (metros)', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text('153.33', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const ListTile(
              leading: Icon(Icons.calendar_month),
              title: Text('Días trabajables (Quincena)', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text('12', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.save),
                label: const Text('GUARDAR CAMBIOS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E90FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}