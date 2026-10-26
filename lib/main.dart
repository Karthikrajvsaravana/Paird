import 'package:flutter/material.dart';

import 'app/paird_app.dart';
import 'core/api/api_client.dart';
import 'core/api/paird_api.dart';
import 'core/auth/auth_controller.dart';
import 'core/auth/token_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = PairdApi(ApiClient(tokenStore: SecureTokenStore()));
  final auth = AuthController(api: api)..restore();
  runApp(PairdApp(api: api, auth: auth));
}
