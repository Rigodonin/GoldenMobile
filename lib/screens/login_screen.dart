import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _autenticar() async {
    // Hack temporal para pruebas rápidas
    if (_usuarioController.text.trim() == 'rigodonin') {
      Navigator.pushReplacementNamed(context, '/admin');
      return;
    }

    if (_usuarioController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final emailSimulado = '${_usuarioController.text.trim().toLowerCase()}@gs.com';

      // 1. Intentar iniciar sesión
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailSimulado,
        password: _passwordController.text.trim(),
      );

      if (response.user != null) {
        // 2. Consultar perfil con .maybeSingle() para evitar que la app truene
        final perfil = await Supabase.instance.client
            .from('perfiles')
            .select('rol')
            .eq('id', response.user!.id)
            .maybeSingle();

        if (!mounted) return;

        // 3. Si no hay perfil, es un error de configuración de la BD o RLS
        if (perfil == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se encontró perfil. Verifica permisos RLS.'), backgroundColor: Colors.red),
          );
        } else {
          // 4. Redirección según rol
          if (perfil['rol'] == 'admin') {
            Navigator.pushReplacementNamed(context, '/admin');
          } else {
            Navigator.pushReplacementNamed(context, '/operador');
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      print('🚨 ERROR REAL DE SUPABASE: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: Usuario o contraseña incorrectos'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('GS', style: TextStyle(fontSize: 54, fontWeight: FontWeight.bold, color: Color(0xFF1E2265), letterSpacing: 2)),
                const SizedBox(height: 48),
                TextField(controller: _usuarioController, decoration: const InputDecoration(labelText: 'Usuario / Nómina', border: OutlineInputBorder())),
                const SizedBox(height: 20),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder())),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _autenticar,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDBDBF0), foregroundColor: const Color(0xFF1E2265)),
                    child: _isLoading ? const CircularProgressIndicator() : const Text('Ingresar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}