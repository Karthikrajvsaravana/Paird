import 'package:flutter/material.dart';

import '../core/api/paird_api.dart';
import '../core/auth/auth_controller.dart';
import 'app_scope.dart';
import 'auth_gate.dart';
import 'theme/app_theme.dart';

class PairdApp extends StatelessWidget {
  const PairdApp({super.key, required this.api, required this.auth});

  final PairdApi api;
  final AuthController auth;

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      api: api,
      auth: auth,
      child: MaterialApp(
        title: 'Paird',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: AppTheme.dark,
        home: const AuthGate(),
      ),
    );
  }
}
