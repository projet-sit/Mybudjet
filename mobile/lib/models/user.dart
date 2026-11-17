class User {
  const User({
    required this.id,
    required this.displayName,
    this.email,
    this.phone,
    this.photoUrl,
    required this.currency,
    this.createdAt,
    this.dataEpoch = 0,
  });

  final String id;
  final String displayName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final String currency;
  final DateTime? createdAt;

  /// Incrémenté à chaque réinitialisation complète du compte (côté serveur).
  /// Les autres appareils détectent le changement et effacent leur cache local.
  final int dataEpoch;

  /// Identifiant principal à afficher (numéro de téléphone, sinon e-mail legacy).
  String get identifier => phone ?? email ?? '';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      displayName: (json['displayName'] ?? '') as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      photoUrl: json['photoUrl'] as String?,
      currency: (json['currency'] ?? 'XOF') as String,
      dataEpoch: ((json['dataEpoch'] ?? json['data_epoch']) as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'currency': currency,
        'dataEpoch': dataEpoch,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };
}

class AuthSession {
  const AuthSession({required this.user, required this.accessToken, required this.refreshToken});

  final User user;
  final String accessToken;
  final String refreshToken;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    // Le backend renvoie { user, tokens: { accessToken, refreshToken } }.
    // On accepte aussi la forme plate (sessions déjà stockées localement).
    final rawTokens = json['tokens'];
    final tokens = rawTokens is Map<String, dynamic> ? rawTokens : const <String, dynamic>{};
    final accessToken = tokens['accessToken'] ?? json['accessToken'];
    final refreshToken = tokens['refreshToken'] ?? json['refreshToken'];
    if (accessToken is! String || refreshToken is! String) {
      throw const FormatException('Réponse d’authentification invalide');
    }
    return AuthSession(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };
}
