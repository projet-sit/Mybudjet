import 'package:connectivity_plus/connectivity_plus.dart';
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late AuthMode _mode = widget.initialMode;
  bool _obscure = true;
  bool _acceptedCgu = false;
  bool _offline = false;

  bool get _isRegister => _mode == AuthMode.register;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (mounted) setState(() => _offline = offline);
  }
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isRegister && !_acceptedCgu) {
      _snack("J'accepte les conditions d'utilisation");
      return;
    }
    FocusScope.of(context).unfocus();
    if (_isRegister) {
      await ref.read(authControllerProvider.notifier).register(
            displayName: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } else {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailController.text.trim(),
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
      _formKey.currentState?.reset();
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'E-mail requis';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
      return 'Adresse e-mail invalide';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final authState = ref.watch(authControllerProvider);
    final loading = authState.isLoading;
    final error = authState.hasError ? AuthController.messageFrom(authState.error!) : null;

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
                          if (_offline) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _isRegister
                                        ? 'Connectez-vous à internet pour créer votre compte'
                                        : 'Connectez-vous à internet pour vous connecter',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: scheme.error, fontSize: 13),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: _checkConnectivity,
                                    child: const Text('Réessayer'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
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
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autofocus: !_isRegister,
                              autofillHints: _isRegister
                                  ? const [AutofillHints.newUsername]
                                  : const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              style: const TextStyle(fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'E-mail',
                                prefixIcon: Icon(Icons.email_outlined),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              ),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
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
                      OutlinedButton.icon(
                        onPressed: loading ? null : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
                        icon: const Icon(Icons.g_mobiledata),
                        label: const Text('Continuer avec Google'),
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
