import 'package:flutter/material.dart';
import 'features/auth/screens/sign_in_screen.dart';

void main() {
  runApp(const PairdApp());
}

class PairdApp extends StatelessWidget {
  const PairdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paird',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const SignInScreen(),
    );
  }
}