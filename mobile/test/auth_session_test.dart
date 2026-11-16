import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/models/user.dart';

void main() {
  Map<String, dynamic> userJson() => {
        'id': 'u1',
        'displayName': 'Awa',
        'email': 'awa@example.com',
        'phone': '+22997000000',
        'currency': 'XOF',
      };

  test('AuthSession lit les jetons imbriqués renvoyés par le backend', () {
    final session = AuthSession.fromJson({
      'user': userJson(),
      'tokens': {'accessToken': 'access-1', 'refreshToken': 'refresh-1'},
    });

    expect(session.user.email, 'awa@example.com');
    expect(session.user.phone, '+22997000000');
    expect(session.user.identifier, '+22997000000');
    expect(session.accessToken, 'access-1');
    expect(session.refreshToken, 'refresh-1');
  });

  test('AuthSession lit aussi la forme plate stockée localement', () {
    final session = AuthSession.fromJson({
      'user': userJson(),
      'accessToken': 'access-2',
      'refreshToken': 'refresh-2',
    });

    expect(session.accessToken, 'access-2');
    expect(session.refreshToken, 'refresh-2');
  });

  test('AuthSession refuse une réponse sans jetons', () {
    expect(
      () => AuthSession.fromJson({'user': userJson()}),
      throwsFormatException,
    );
  });

  test('La sérialisation locale reste relisible', () {
    final original = AuthSession.fromJson({
      'user': userJson(),
      'tokens': {'accessToken': 'a', 'refreshToken': 'r'},
    });
    final restored = AuthSession.fromJson(original.toJson());

    expect(restored.user.id, 'u1');
    expect(restored.accessToken, 'a');
    expect(restored.refreshToken, 'r');
  });
}
