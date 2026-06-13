import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistorialScreen extends StatelessWidget {
  const HistorialScreen({super.key});

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
                child: ListTile(
                  leading: const Icon(Icons.archive_outlined, color: Color(0xFF2E3192)),
                  title: Text('Cerrada el: ${item['fecha_cierre']}'),
                  subtitle: Text('${item['periodo']}'),
                  trailing: Text('${item['total_metros']} mts', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}