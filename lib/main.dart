import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database/neon_helper.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  const compiled = String.fromEnvironment('NEON_CONNECTION_STRING', defaultValue: '');

  if (compiled.isNotEmpty) await prefs.setString('neon_connection_string', compiled);

  final connStr = prefs.getString('neon_connection_string') ?? compiled;
  if (connStr.isNotEmpty) NeonHelper.initialize(connStr);

  runApp(const MarcaoFinancasApp());
}

class MarcaoFinancasApp extends StatelessWidget {
  const MarcaoFinancasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marcão Finanças',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B873F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B873F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}
