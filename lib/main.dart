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
        '/': (context) => LoginScreen(),
        '/admin': (context) => AdminScreen(),
        '/operador': (context) => OperadorScreen(),
        '/historial': (context) => HistorialScreen(),
        '/perfil': (context) => PerfilScreen(),
      },
    );
  }
}
