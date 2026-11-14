import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_repository.dart';

/// Mot de passe oublié / réinitialisation.
/// Flux en 2 étapes : 1) saisie de l'e-mail → 2) nouveau mot de passe.
/// En développement, le backend renvoie le token directement (delivery: dev-log).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  int _step = 0; // 0 = demande, 1 = réinitialisation
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() => _error = 'E-mail requis');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final token = await AuthRepository.instance.forgotPassword(
        email: _emailController.text.trim(),
      );
      setState(() {
        _step = 1;
        _tokenController.text = token; // Pré-rempli en développement.
        _info = 'Code de réinitialisation envoyé. Suis les instructions.';
      });
    } catch (e) {
      setState(() => _error = 'Impossible de demander une réinitialisation. Réessaie.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_tokenController.text.trim().isEmpty) {
      setState(() => _error = 'Code de réinitialisation requis');
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _error = 'Nouveau mot de passe : au moins 6 caractères');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthRepository.instance.resetPassword(
        token: _tokenController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe réinitialisé, connecte-toi')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = 'Lien de réinitialisation invalide ou expiré');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.lock_reset_outlined, size: 64, color: AppColors.deepGreen),
              const SizedBox(height: 16),
              Text(
                _step == 0 ? 'Récupère ton accès' : 'Nouveau mot de passe',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                _step == 0
                    ? 'Entre ton e-mail pour recevoir un code de réinitialisation.'
                    : 'Choisis un nouveau mot de passe (6 caractères minimum).',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              if (_step == 0)
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                )
              else ...[
                TextFormField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    hintText: 'Code de réinitialisation',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: 'Nouveau mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
              if (_info != null) ...[
                const SizedBox(height: 16),
                Text(_info!, style: const TextStyle(color: AppColors.incomeGreen), textAlign: TextAlign.center),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: AppColors.expenseRed), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : (_step == 0 ? _requestReset : _reset),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(_step == 0 ? 'Envoyer le code' : 'Réinitialiser le mot de passe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
