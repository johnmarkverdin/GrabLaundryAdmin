// lib/supabase_config.dart
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://hdfeavzitpkrsoxqmubh.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhkZmVhdnppdHBrcnNveHFtdWJoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE3MTY2MjcsImV4cCI6MjA3NzI5MjYyN30.i7xw9GQHEV6jE8SoSfQmcTHtV8C5SNJ10OeCOMoeHEU';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
}

SupabaseClient get supabase => Supabase.instance.client;
