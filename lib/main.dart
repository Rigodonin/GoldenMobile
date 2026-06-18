import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/operador_screen.dart';
import 'screens/historial_screen.dart';
import 'screens/perfil_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://dczxzkvlomzuqnbmmect.supabase.co',
    publishableKey: 'sb_publishable_XCE3n1G-dLBmTPFLVlgsQQ_JscHgiuj',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoldenMobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1E2265),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SessionGate(),
        '/login': (context) => LoginScreen(),
        '/admin': (context) => AdminScreen(),
        '/operador': (context) => OperadorScreen(),
        '/historial': (context) => HistorialScreen(),
        '/perfil': (context) => PerfilScreen(),
      },
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirigirSegunSesion();
    });
  }

  Future<void> _redirigirSegunSesion() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    String ruta = '/login';

    if (user != null) {
      try {
        final datosUsuario = await client
            .from('perfiles')
            .select('rol')
            .eq('id', user.id)
            .single()
            .timeout(const Duration(seconds: 8));

        final String rol = datosUsuario['rol'] ?? 'operador';
        ruta = rol.trim().toLowerCase() == 'admin' ? '/admin' : '/operador';
      } catch (e) {
        debugPrint('No se pudo restaurar la sesion: $e');
        await client.auth.signOut();
      }
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, ruta);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF1E2265))),
    );
  }
}
// est solo es un comentrio para un ejemplo de commit otra vez
//creo que ahora si