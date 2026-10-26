import 'package:flutter/widgets.dart';

import '../core/api/paird_api.dart';
import '../core/auth/auth_controller.dart';

/// Makes app-wide services available to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.api, required this.auth, required super.child});

  final PairdApi api;
  final AuthController auth;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  static AppScope read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => api != oldWidget.api || auth != oldWidget.auth;
}
