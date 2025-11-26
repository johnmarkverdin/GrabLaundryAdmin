import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'pages/auth_admin_page.dart';
import 'pages/admin_home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase(); // your existing init function in supabase_config.dart
  runApp(const AdminApp());
}

class AdminApp extends StatefulWidget {
  const AdminApp({Key? key}) : super(key: key);

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  bool _checkingSession = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();

    // listen to login / logout
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      setState(() {
        _loggedIn = event.session != null;
      });
    });
  }

  void _checkSession() {
    final session = Supabase.instance.client.auth.currentSession;
    setState(() {
      _loggedIn = session != null;
      _checkingSession = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'GrabLaundry Admin',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: _loggedIn ? const AdminHomePage() : const AdminAuthPage(),
    );
  }
}
