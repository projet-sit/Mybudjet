import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';import '../../providers/auth_provider.dart';
enum AuthMode { login, register }

/// Authentification (maquette « MyBudget ») : en-tête dégradé MyBudget,
/// contrôle Connexion / Inscription, formulaire unique.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.initialMode = AuthMode.login});

  final AuthMode initialMode;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailOptionalController = TextEditingController();
  final _passwordController = TextEditingController();

  late AuthMode _mode = widget.initialMode;
  _Country _country = _defaultCountry;
  bool _obscure = true;
  bool _acceptedCgu = false;
  AuthMode? _errorMode; // mode dans lequel l'erreur courante est survenue

  bool get _isRegister => _mode == AuthMode.register;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailOptionalController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Numéro international complet : `+<indicatif><numéro national>`.
  /// Un « 0 » initial est ignoré (format national, ex. 06… en France → +33 6…).
  String _fullPhone() {
    final national = _phoneController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return '${_country.dialCode}$national';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isRegister && !_acceptedCgu) {
      _snack("J'accepte les conditions d'utilisation");
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _errorMode = _mode);
    if (_isRegister) {
      final email = _emailOptionalController.text.trim();
      await ref.read(authControllerProvider.notifier).register(
            displayName: _nameController.text.trim(),
            phone: _fullPhone(),
            password: _passwordController.text,
            email: email.isEmpty ? null : email,
          );
    } else {
      await ref.read(authControllerProvider.notifier).login(
            phone: _fullPhone(),
            password: _passwordController.text,
          );
    }
    final result = ref.read(authControllerProvider);
    if (!result.hasError && result.hasValue) {
      // Le gestionnaire de mots de passe (Android/iOS) propose d'enregistrer
      // les identifiants — le prochain remplissage sera pré-rempli.
      TextInput.finishAutofillContext(shouldSave: true);
    }
  }

  void _switchMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _errorMode = null; // n'affiche plus l'erreur de l'autre onglet
      _formKey.currentState?.reset();
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\s+'), '');
    if (digits.isEmpty) return 'Numéro de téléphone requis';
    if (!RegExp(r'^[0-9]{8,14}$').hasMatch(digits)) {
      return 'Numéro invalide (8 à 14 chiffres)';
    }
    return null;
  }

  String? _validateOptionalEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null; // facultatif : e-mail uniquement pour la récupération
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'Adresse e-mail invalide';
    }
    return null;
  }

  Future<void> _pickCountry(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<_Country>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'Choisis ton pays',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final country in _francophoneCountries)
              ListTile(
                leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                title: Text(country.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(country.dialCode, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (country.iso == _country.iso) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle, color: scheme.primary),
                    ],
                  ],
                ),
                selected: country.iso == _country.iso,
                onTap: () => Navigator.of(sheetContext).pop(country),
              ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _country = selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final authState = ref.watch(authControllerProvider);
    final loading = authState.isLoading;
    // Chaîne vide = échec de connectivité → on reste silencieux (rien n'est affiché).
    final rawError = authState.hasError && _errorMode == _mode
        ? AuthController.messageFrom(authState.error!)
        : null;
    final error = (rawError == null || rawError.isEmpty) ? null : rawError;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 54),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      child: const AppLogo(size: 56),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MyBudget',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Vos finances, simples et claires.',
                      style: TextStyle(color: Colors.white70, fontSize: 13.5),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      _isRegister ? 'Bienvenue !' : 'Bon retour !',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegister
                          ? 'Crée ton compte et prends le contrôle de tes finances.'
                          : 'Connecte-toi pour retrouver ton budget.',
                      style: const TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.35),
                    ),
                    ],
                  ),
                ),
              Transform.translate(
                offset: const Offset(0, -26),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: scheme.outline),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _segment(scheme, 'Connexion', AuthMode.login),
                            _segment(scheme, 'Inscription', AuthMode.register),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      AutofillGroup(
                        child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (_isRegister) ...[
                              TextFormField(
                                key: const ValueKey('auth_name_field'),
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                autofocus: true,
                                autofillHints: const [AutofillHints.name],
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(fontSize: 15),
                                decoration: const InputDecoration(
                                  hintText: 'Nom complet',
                                  prefixIcon: Icon(Icons.person_outline),
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().length < 2) {
                                    return 'Nom complet requis (2 caractères minimum)';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                            Row(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _pickCountry(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 17),
                                    decoration: BoxDecoration(
                                      color: scheme.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: scheme.outline),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_country.flag, style: const TextStyle(fontSize: 20)),
                                        const SizedBox(width: 6),
                                        Text(
                                          _country.dialCode,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(width: 2),
                                        const Icon(Icons.keyboard_arrow_down, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    key: const ValueKey('auth_phone_field'),
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    autofocus: !_isRegister,
                                    autofillHints: const [AutofillHints.telephoneNumber],
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    autocorrect: false,
                                    style: const TextStyle(fontSize: 15),
                                    decoration: const InputDecoration(
                                      hintText: 'Numéro de téléphone',
                                      prefixIcon: Icon(Icons.phone_outlined),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                                    ),
                                    validator: _validatePhone,
                                  ),
                                ),
                              ],
                            ),
                            if (_isRegister) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _emailOptionalController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                style: const TextStyle(fontSize: 15),
                                decoration: const InputDecoration(
                                  hintText: 'E-mail (facultatif)',
                                  helperText: 'Sert uniquement à récupérer ton mot de passe',
                                  prefixIcon: Icon(Icons.email_outlined),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                                ),
                                validator: _validateOptionalEmail,
                              ),
                            ],
                            const SizedBox(height: 14),
                            TextFormField(
                              key: const ValueKey('auth_password_field'),
                              controller: _passwordController,
                              obscureText: _obscure,
                              enableSuggestions: false,
                              autocorrect: false,
                              autofillHints: _isRegister
                                  ? const [AutofillHints.newPassword]
                                  : const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Mot de passe',
                                prefixIcon: const Icon(Icons.lock_outline),
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Mot de passe requis';
                                if (_isRegister && value.length < 6) return 'Au moins 6 caractères';
                                return null;
                              },
                              onFieldSubmitted: loading ? null : (_) => _submit(),
                            ),
                          ],
                        ),
                      ),
                    ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: scheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            error,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.error, fontSize: 12),
                          ),
                        ),
                      ],
                      if (!_isRegister)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: loading ? null : () => context.go('/forgot-password'),
                            child: const Text('Mot de passe oublié ?'),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _acceptedCgu,
                          onChanged: loading
                              ? null
                              : (value) => setState(() => _acceptedCgu = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            "J'accepte les conditions d'utilisation",
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.deepGreenLight, AppColors.deepGreen],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: loading ? null : _submit,
                            child: Center(
                              child: loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isRegister ? 'Créer mon compte' : 'Se connecter',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isRegister ? 'Déjà un compte ?' : 'Pas encore de compte ?',
                            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            onPressed: loading
                                ? null
                                : () => _switchMode(
                                      _isRegister ? AuthMode.login : AuthMode.register,
                                    ),
                            child: Text(_isRegister ? 'Se connecter' : 'Créer un compte'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(ColorScheme scheme, String label, AuthMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pays proposés pour l'indicatif téléphonique (Afrique francophone + France,
/// plus Belgique / Suisse / Canada pour la diaspora).
class _Country {
  const _Country(this.iso, this.name, this.dialCode, this.flag);

  final String iso;
  final String name;
  final String dialCode;
  final String flag;
}

const _defaultCountry = _Country('BJ', 'Bénin', '+229', '🇧🇯');

const List<_Country> _francophoneCountries = [
  _defaultCountry,
  _Country('BF', 'Burkina Faso', '+226', '🇧🇫'),
  _Country('CM', 'Cameroun', '+237', '🇨🇲'),
  _Country('CF', 'Centrafrique', '+236', '🇨🇫'),
  _Country('CI', "Côte d'Ivoire", '+225', '🇨🇮'),
  _Country('GA', 'Gabon', '+241', '🇬🇦'),
  _Country('GH', 'Ghana', '+233', '🇬🇭'),
  _Country('GN', 'Guinée', '+224', '🇬🇳'),
  _Country('ML', 'Mali', '+223', '🇲🇱'),
  _Country('NE', 'Niger', '+227', '🇳🇪'),
  _Country('NG', 'Nigeria', '+234', '🇳🇬'),
  _Country('CG', 'Congo', '+242', '🇨🇬'),
  _Country('CD', 'RD Congo', '+243', '🇨🇩'),
  _Country('SN', 'Sénégal', '+221', '🇸🇳'),
  _Country('TD', 'Tchad', '+235', '🇹🇩'),
  _Country('TG', 'Togo', '+228', '🇹🇬'),
  _Country('MA', 'Maroc', '+212', '🇲🇦'),
  _Country('DZ', 'Algérie', '+213', '🇩🇿'),
  _Country('TN', 'Tunisie', '+216', '🇹🇳'),
  _Country('FR', 'France', '+33', '🇫🇷'),
  _Country('BE', 'Belgique', '+32', '🇧🇪'),
  _Country('CH', 'Suisse', '+41', '🇨🇭'),
  _Country('CA', 'Canada', '+1', '🇨🇦'),
  _Country('LU', 'Luxembourg', '+352', '🇱🇺'),
];
