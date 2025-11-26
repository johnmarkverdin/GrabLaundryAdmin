import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 👈 ADD
import '../supabase_config.dart';
import '../pages/admin_home_page.dart';

class AdminAuthPage extends StatefulWidget {
  const AdminAuthPage({super.key});

  @override
  State<AdminAuthPage> createState() => _AdminAuthPageState();
}

class _AdminAuthPageState extends State<AdminAuthPage> {
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();

  bool _isSignUp = false;
  bool _loading = false;
  bool _showPassword = false;

  // 👇 ADD: remember me flag
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedAdmin(); // 👈 ADD
  }

  // 👇 ADD: load saved preference + email, optionally auto-continue
  Future<void> _loadRememberedAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('admin_remember_me') ?? false;
    final email = prefs.getString('admin_email');

    if (!mounted) return;

    setState(() {
      _rememberMe = remember;
      if (remember && email != null) {
        _emailCtl.text = email;
      }
    });

    if (remember) {
      final session = supabase.auth.currentSession;
      if (session != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    _nameCtl.dispose();
    _phoneCtl.dispose();
    super.dispose();
  }

  Future<void> _auth() async {
    final email = _emailCtl.text.trim();
    final pass = _passwordCtl.text.trim();
    final name = _nameCtl.text.trim();
    final phone = _phoneCtl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _snack('Email & password required');
      return;
    }
    if (_isSignUp && (name.isEmpty || phone.isEmpty)) {
      _snack('Name & phone required');
      return;
    }

    setState(() => _loading = true);

    try {
      if (_isSignUp) {
        final res = await supabase.auth.signUp(
          email: email,
          password: pass,
          data: {
            'full_name': name,
            'phone': phone,
            'role': 'admin',
          },
        );

        if (res.user != null) {
          _snack('Admin created! Confirm email, then sign in.');
          setState(() => _isSignUp = false);
        }
      } else {
        final res = await supabase.auth.signInWithPassword(
          email: email,
          password: pass,
        );

        if (res.session != null) {
          // 👇 ADD: save / clear remember-me preference
          final prefs = await SharedPreferences.getInstance();
          if (_rememberMe) {
            await prefs.setBool('admin_remember_me', true);
            await prefs.setString('admin_email', email);
          } else {
            await prefs.remove('admin_remember_me');
            await prefs.remove('admin_email');
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminHomePage()),
          );
        } else {
          _snack('Login failed.');
        }
      }
    } on AuthException catch (e) {
      _snack('Auth error: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSignUp ? 'Admin Sign Up' : 'Admin Sign In';

    return Scaffold(
      // keep app bar but make it nicer
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF4F46E5),
                Color(0xFF6366F1),
                Color(0xFF0EA5E9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      backgroundColor: const Color(0xFFE5E7EB),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFE5E7EB),
              Color(0xFFE0F2FE),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top icon + title
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 32,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Laundry Admin Portal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSignUp
                            ? 'Create an admin account to manage orders.'
                            : 'Sign in to manage customers, riders, and orders.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // FORM
                      if (_isSignUp) ...[
                        TextField(
                          controller: _nameCtl,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person_outline),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _phoneCtl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _emailCtl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordCtl,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() => _showPassword = !_showPassword);
                            },
                          ),
                        ),
                      ),

                      // 👇 ADD: Remember me only on Sign In
                      if (!_isSignUp) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (val) {
                                setState(() {
                                  _rememberMe = val ?? false;
                                });
                              },
                              activeColor: const Color(0xFF4F46E5),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Remember me',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),

                      _loading
                          ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: CircularProgressIndicator(),
                      )
                          : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _auth,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12),
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _isSignUp
                                ? 'Create Admin Account'
                                : 'Sign In',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            setState(() => _isSignUp = !_isSignUp),
                        child: Text(
                          _isSignUp
                              ? 'Already have an account? Sign In'
                              : 'No account yet? Sign Up as Admin',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4F46E5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
