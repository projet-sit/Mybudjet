import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  static const String _envDefine = String.fromEnvironment('API_BASE_URL');
  static const String _googleDefine = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static String get apiBaseUrl {
    if (_envDefine.isNotEmpty) return _envDefine;
    return dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000/api/v1';
  }

  /// Client ID OAuth « Web » de Google Cloud Console, utilisé comme
  /// serverClientId pour que Google renvoie un idToken.
  static String get googleServerClientId {
    if (_googleDefine.isNotEmpty) return _googleDefine;
    return dotenv.env['GOOGLE_SERVER_CLIENT_ID']?.trim() ?? '';
  }
}
