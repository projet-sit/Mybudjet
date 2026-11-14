import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../models/categories.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/cache_service.dart';
import '../../services/data_repository.dart';

/// Saisie rapide (maquette) : Dépense/Revenu, montant, catégories, pavé numérique.
/// Sert aussi à modifier une opération existante.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.editing});

  final Transaction? editing;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  String _mode = 'expense';
  String _amount = '';
  String _category = 'Alimentation';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final tx = widget.editing;
    if (tx != null) {
      _mode = tx.type == 'income' ? 'income' : 'expense';
      _amount = '${tx.amount}';
      _category = tx.category;
    }
  }

  List<String> get _categories => _mode == 'expense'
      ? ExpenseCategories.list.map((e) => e.$1).toList()
      : IncomeCategories.list;

  void _setMode(String mode) {
    setState(() {
      _mode = mode;
      _category = _categories.first;
    });
  }

  void _key(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == '⌫') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
      } else if (key == '000') {
        if (_amount.isNotEmpty && _amount.length + 3 <= 9) {
          _amount += '000';
        }
      } else {
        if (_amount == '0') _amount = '';
        if (_amount.length + 1 <= 9) _amount += key;
      }
      _amount = _amount.replaceFirst(RegExp(r'^0+'), '');
    });
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.isEmpty ? '0' : _amount) ?? 0;
    if (amount <= 0) {
      _snack('Entre un montant');
      return;
    }
    if (ref.read(offlineProvider)) {
      _snack('Connexion Internet requise pour enregistrer.');
      return;
    }
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) {
      _snack("Aucun portefeuille — crée-le d'abord");
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tx = Transaction(
        id: widget.editing?.id ?? '',
        walletId: wallet.id,
        type: _mode,
        amount: amount,
        category: _category,
        description: widget.editing?.description,
        date: widget.editing?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        time: widget.editing?.time ?? DateFormat('HH:mm').format(DateTime.now()),
        paymentMethod: _mode == 'expense' ? (widget.editing?.paymentMethod ?? 'Espèces') : null,
      );
      if (widget.editing == null) {
        await TransactionRepository.instance.create(wallet.id, tx);
      } else {
        await TransactionRepository.instance.update(wallet.id, tx.id, tx);
      }
      await ref.read(transactionsProvider.notifier).refreshAll();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(widget.editing == null ? 'Opération enregistrée' : 'Opération modifiée')),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(TransactionsController.messageFrom(e));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? AppColors.darkBg : AppColors.offWhite;
    final label = _amount.isEmpty ? '0' : formatXof(int.parse(_amount), withCurrency: false);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: fieldBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _segment('Dépense', 'expense', scheme, fieldBg),
                    _segment('Revenu', 'income', scheme, fieldBg),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    TextSpan(
                      text: ' FCFA',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final name = _categories[i];
                    final selected = name == _category;
                    return GestureDetector(
                      onTap: () => setState(() => _category = name),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : scheme.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: selected ? scheme.primary : scheme.outline),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['000', '0', '⌫'],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      for (final key in row)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: key == row.last ? 0 : 6,
                            ),
                            child: Material(
                              color: fieldBg,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _key(key),
                                onLongPress: key == '⌫'
                                    ? () {
                                        HapticFeedback.mediumImpact();
                                        setState(() => _amount = '');
                                      }
                                    : null,
                                child: SizedBox(
                                  height: 48,
                                  child: Center(
                                    child: Text(
                                      key,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onSurface,
                                      ),
                                    ),
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
              Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.deepGreenLight, AppColors.deepGreen],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _saving ? null : _save,
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(
                              widget.editing == null ? 'Enregistrer' : 'Mettre à jour',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(String label, String mode, ColorScheme scheme, Color fieldBg) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
