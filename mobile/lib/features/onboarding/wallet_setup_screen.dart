import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';import '../../core/utils/money.dart';
import '../../providers/wallet_provider.dart';

/// Onboarding — fidèle à la maquette :
/// « Commençons par ton budget — Combien d'argent as-tu actuellement à disposition ? »
class WalletSetupScreen extends ConsumerStatefulWidget {
  const WalletSetupScreen({super.key});

  @override
  ConsumerState<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _WalletSetupScreenState extends ConsumerState<WalletSetupScreen> {
  final _amountController = TextEditingController();
  final _nameController = TextEditingController(text: 'Mon budget');
  DateTime _startDate = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  int? _parseAmount() {
    final cleaned = _amountController.text.replaceAll(RegExp(r'[\s,]'), '');
    if (cleaned.isEmpty) return 0; // Le portefeuille peut démarrer à 0.
    return int.tryParse(cleaned);
  }

  Future<void> _createWallet() async {
    final amount = _parseAmount();
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Montant invalide — entiers uniquement (ex : 150000)')),
      );
      return;
    }
    await ref.read(walletControllerProvider.notifier).create(
          name: _nameController.text.trim().isEmpty ? 'Mon budget' : _nameController.text.trim(),
          initialAmount: amount,
          startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        );
    if (!mounted) return;
    final result = ref.read(walletControllerProvider);
    // En cas d'échec, le message est affiché sous le formulaire.
    if (result.value != null) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletControllerProvider);
    final loading = walletState.isLoading;
    final error = walletState.hasError ? WalletController.messageFrom(walletState.error!) : null;

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Carte verte supérieure (identité maquette)
              Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.deepGreenLight, AppColors.deepGreen],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const AppLogo(size: 40),                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Commençons par\nton budget',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Combien d'argent as-tu actuellement à disposition ?",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Nom du portefeuille
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Nom du portefeuille (Mon budget)',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Montant initial en grand
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 1),
                textAlign: TextAlign.center,
                inputFormatters: [
                  // Entiers uniquement — les montants FCFA n'ont pas de décimales.
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
                ],
                onChanged: (value) {
                  // Espacement des milliers en direct : 150000 → 150 000
                  final digits = value.replaceAll(RegExp(r'\s'), '');
                  if (digits.isEmpty) return;
                  final parsed = int.tryParse(digits);
                  if (parsed != null) {
                    final formatted = formatXof(parsed, withCurrency: false);
                    if (formatted != value) {
                      _amountController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  }
                },
                decoration: const InputDecoration(
                  hintText: '0',
                  suffixText: 'FCFA',
                  suffixStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Laisse à 0 si tu ne veux pas partir de ce montant.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // Date de début
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, color: AppColors.deepGreen),
                      const SizedBox(width: 12),
                      const Text('Date de début', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        formatDateFr(DateFormat('yyyy-MM-dd').format(_startDate)),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Note verte (maquette)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.incomeGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.incomeGreen),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ton portefeuille commencera avec ce montant. Aucune donnée fictive : tout part de ce que tu saisis.',
                        style: const TextStyle(color: Color(0xFF15803D), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(error, style: const TextStyle(color: AppColors.expenseRed), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: loading ? null : _createWallet,
                child: loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Créer mon portefeuille'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
