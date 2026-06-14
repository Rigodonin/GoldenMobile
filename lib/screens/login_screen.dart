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

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _autenticar() async {
    if (_usuarioController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final usuarioTrim = _usuarioController.text.trim().toLowerCase();
      final emailSimulado = '$usuarioTrim@gs.com';

      // Autenticación formal en Supabase
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailSimulado,
        password: _passwordController.text.trim(),
      );

      if (response.user != null) {
        if (!mounted) return;
        
        // 🛠️ CAMBIO: Traemos el rol desde tu tabla 'usuarios' en la base de datos
        final datosUsuario = await Supabase.instance.client
            .from('perfiles') // ⚠️ Asegúrate de que así se llame tu tabla en Supabase
            .select('rol')
            .eq('id', response.user!.id)
            .single();

        final String rol = datosUsuario['rol'] ?? 'operador';
        
        // Direccionamiento seguro según el rol
        if (!mounted) return;
        if (rol.trim().toLowerCase() == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin');
        } else {
          Navigator.pushReplacementNamed(context, '/operador');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de autenticación: $e'), backgroundColor: Colors.red),
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
                TextField(
                  controller: _usuarioController, 
                  decoration: const InputDecoration(labelText: 'Usuario / Nómina', border: OutlineInputBorder())
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _passwordController, 
                  obscureText: true, 
                  decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder())
                ),
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
