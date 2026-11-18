import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_feedback.dart';
import '../../providers/currency_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/currency_service.dart';

/// Mon épargne : l'argent reste dans le même compte, en réserve.
/// Disponible = solde − épargne. Aucun compte supplémentaire.
/// Le montant mis de côté est saisi en valeur absolue (comme avant).
class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key});

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen> {
  final _amountController = TextEditingController();
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int? _parseAmount() {
    final code = CurrencyService.instance.current;
    final raw = _amountController.text.trim();
    if (raw.isEmpty) return 0; // Champ vide = 0 (permet « Tout récupérer »).
    return enteredToXof(raw, code);
  }

  void _setAmount(int amountXof) {
    final code = CurrencyService.instance.current;
    final String text;
    if (code == 'XOF') {
      text = amountXof == 0 ? '' : formatMoneyCurrent(amountXof, withCurrency: false);
    } else {
      final value = CurrencyService.convertFromXof(amountXof, code);
      text = amountXof == 0 ? '' : value.toStringAsFixed(2).replaceAll('.', ',');
    }
    _amountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  Future<void> _save(int amount) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    if (amount < 0 || amount > wallet.balance) {
      _snack('Montant invalide : entre 0 et ${formatMoneyCurrent(wallet.balance)}');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(walletControllerProvider.notifier).setSavings(amount);
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      _snack(WalletController.messageFrom(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _withdrawAll() async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    if (wallet.savingsAmount <= 0) {
      _snack('Ton épargne est déjà vide');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tout récupérer ?'),
        content: Text(
          'Les ${formatMoneyCurrent(wallet.savingsAmount)} épargnés reviennent dans ton Reste.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tout récupérer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _save(0);
  }

  void _snack(String message) {
    showErrorSnackBar(context, message);
  }

  /// Suggestions de montants ronds, exprimées en XOF (base), selon la devise active.
  List<int> _quickAmounts(String code) {
    switch (code) {
      case 'EUR':
        return const [10, 25, 50, 100].map(enteredEurToXof).toList();
      case 'USD':
        return const [10, 25, 50, 100].map(enteredUsdToXof).toList();
      case 'XOF':
      default:
        return const [5000, 10000, 25000, 50000];
    }
  }

  /// 10 € → XOF via la parité fixe (arrondi).
  static int enteredEurToXof(num eur) => (eur * 655.957).round();

  /// 10 $ → XOF via le taux du jour (ou de secours) (arrondi).
  static int enteredUsdToXof(num usd) => CurrencyService.convertToXof(usd, 'USD');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet != null && !_initialized) {
      _initialized = true;
      _setAmount(wallet.savingsAmount);
    }

    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon épargne')),
        body: const Center(child: Text('Crée d’abord ton budget.')),
      );
    }

    final balance = wallet.balance;
    final savings = wallet.savingsAmount;
    final reste = wallet.available;
    final pending = _parseAmount();
    final invalid = pending == null || pending > balance;
    final after = pending == null || pending > balance
        ? reste
        : (balance - pending).clamp(0, balance);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon épargne')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(walletControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.deepGreenLight, AppColors.deepGreen, AppColors.deepGreenDark],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Épargne totale',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMoneyCurrent(savings),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Reste à dépenser : ${formatMoneyCurrent(reste)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Solde total : ${formatMoneyCurrent(balance)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Montant à mettre de côté',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: ref.watch(currencyControllerProvider).code == 'XOF'
                  ? const TextInputType.numberWithOptions(decimal: false)
                  : const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
              inputFormatters: [
                ref.watch(currencyControllerProvider).code == 'XOF'
                    ? FilteringTextInputFormatter.allow(RegExp(r'[\d\s]'))
                    : FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]')),
              ],
              onChanged: (value) {
                final code = ref.read(currencyControllerProvider).code;
                if (code == 'XOF') {
                  // Regroupement des milliers en direct (entiers uniquement).
                  final digits = value.replaceAll(RegExp(r'\s'), '');
                  if (digits.isEmpty) {
                    setState(() {});
                    return;
                  }
                  final parsed = int.tryParse(digits);
                  if (parsed != null) {
                    final formatted = formatMoneyCurrent(parsed, withCurrency: false);
                    if (formatted != value) {
                      _amountController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  }
                }
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: '0',
                suffixText: currencySymbol(ref.watch(currencyControllerProvider).code),
                suffixStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // Suggestions en devise active : montants ronds (les XOF sont
                  // reconvertis proprement).
                  for (final amount in _quickAmounts(ref.watch(currencyControllerProvider).code))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: scheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _saving ? null : () => _setAmount(amount),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Text(
                              formatMoneyCurrent(amount, withCurrency: false),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              pending == null
                  ? 'Montant invalide'
                  : invalid
                      ? 'Montant trop élevé — tu as ${formatMoneyCurrent(balance)}'
                      : 'Reste après épargne : ${formatMoneyCurrent(after)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: invalid ? scheme.error : scheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving || pending == null || invalid ? null : () => _save(pending),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Enregistrer l’épargne'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _withdrawAll,
                    child: const Text('Tout récupérer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _setAmount(balance),
                    child: const Text('Tout épargner'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}
