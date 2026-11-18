/// Constantes applicatives — ce fichier est le SEUL endroit où figure le
/// numéro du support (jamais dans l'UI : texte, tooltip ou dialogue).
abstract final class AppConstants {
  AppConstants._();

  /// Numéro du support WhatsApp (format international sans le « + »).
  /// Uniquement utilisé pour construire le lien wa.me — jamais affiché.
  static const whatsappContactNumber = '22992098752';

  /// Message pré-rempli à l'ouverture de WhatsApp depuis « Nous contacter ».
  static const whatsappContactMessage =
      'Bonjour, j’ai une question concernant l’application.';

  /// Lien WhatsApp complet (message encodé).
  static Uri get whatsappContactUri => Uri.parse(
        'https://wa.me/$whatsappContactNumber?text=${Uri.encodeComponent(whatsappContactMessage)}',
      );
}
