import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../providers/wallet_provider.dart';

/// Épargne dans le même compte : une réserve interne au solde.
/// Disponible = solde − épargne. Aucun compte supplémentaire.
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
    final cleaned = _amountController.text.replaceAll(RegExp(r'[\s,]'), '');
    if (cleaned.isEmpty) return 0;
    return int.tryParse(cleaned);
  }

  void _setAmount(int amount) {
    final text = amount == 0 ? '' : formatXof(amount, withCurrency: false);
    _amountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _save(int amount) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    if (amount < 0 || amount > wallet.balance) {
      _snack('Montant invalide : entre 0 et ${formatXof(wallet.balance)}');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(walletControllerProvider.notifier).setSavings(amount);
      if (!mounted) return;
      _snack('Épargne enregistrée : ${formatXof(amount)}');
    } catch (e) {
      if (!mounted) return;
      _snack(WalletController.messageFrom(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet != null && !_initialized) {
      _initialized = true;
      _setAmount(mounted ? wallet.savingsAmount : 0);
    }

    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon épargne')),
        body: const Center(child: Text('Crée d’abord ton budget.')),
      );
    }

    final available = wallet.available;
    final pending = _parseAmount();
    final after = pending == null
        ? available
        : (wallet.balance - pending).clamp(0, wallet.balance).toInt();

    return Scaffold(
      appBar: AppBar(title: const Text('Mon épargne')),
      body: ListView(
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
                const Text('Solde total', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatXof(wallet.balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _line('Épargne', wallet.savingsAmount),
                    ),
                    Container(width: 1, height: 34, color: Colors.white24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _line('Disponible', available),
                    ),
                  ],
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
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s]'))],
            onChanged: (value) {
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
              suffixStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final amount in [5000, 10000, 25000, 50000])
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
                            formatXof(amount, withCurrency: false),
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
          const SizedBox(height: 8),
          Text(
            pending == null
                ? 'Montant invalide — entiers uniquement'
                : 'Disponible après épargne : ${formatXof(after)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: pending != null && pending > wallet.balance ? scheme.error : scheme.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving || pending == null ? null : () => _save(pending),
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
                  onPressed: _saving ? null : () => _save(0),
                  child: const Text('Tout récupérer'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(wallet.balance),
                  child: const Text('Tout épargner'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _line(String label, int amount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 3),
        Text(
          formatXof(amount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
