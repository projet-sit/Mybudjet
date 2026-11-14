import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  static const String _envDefine = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_envDefine.isNotEmpty) return _envDefine;
    return dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000/api/v1';
  }
}
