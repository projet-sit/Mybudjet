import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/category_names.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_feedback.dart';
import '../../models/categories.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/category_provider.dart';
import '../../providers/currency_provider.dart';
import '../../services/currency_service.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/outbox.dart';
import '../../services/category_repository.dart';

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
  String? _categoryId;
  bool _saving = false;
  bool _addingCustom = false;
  final _customNameController = TextEditingController();
  final _customFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final tx = widget.editing;
    if (tx != null) {
      _mode = tx.type == 'income' ? 'income' : 'expense';
      _amount = _editableAmount(tx.amount);
      _category = tx.category;
      _categoryId = tx.categoryId;
    }
    // Aperçu en direct des champs (aperçu « Essence · 2 000 FCFA », bouton, etc.).
    _customNameController.addListener(_customNameRebuildListener);
  }

  void _customNameRebuildListener() {
    if (mounted) setState(() {});
  }

  /// Texte tapé dans le champ « Autres » (espaces doublons réduits).
  String get _typedCustom =>
      _customNameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Montant (XOF en base) reconverti pour le champ de saisie dans la devise active.
  String _editableAmount(int xof) {
    final code = CurrencyService.instance.current;
    if (code == 'XOF') return '$xof';
    final value = CurrencyService.convertFromXof(xof, code);
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _customNameController.removeListener(_customNameRebuildListener);
    _customNameController.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  /// Catégories pour le mode actif : défauts (sans « Autres ») → personnalisées → « Autres ».
  List<String> get _categoryNames {
    final all = ref.watch(_mode == 'expense' ? expenseCategoriesProvider : incomeCategoriesProvider);
    if (all.isEmpty) {
      return _mode == 'expense'
          ? ExpenseCategories.list.map((e) => e.$1).toList()
          : IncomeCategories.list;
    }
    return all.map((c) => c.name).toList();
  }

  Category? _findCategory(List<Category> all, String name) {
    final norm = normalizeCategoryName(name);
    for (final c in all) {
      if (c.type == _mode && c.normalized == norm) return c;
    }
    return null;
  }

  void _setMode(String mode) {
    setState(() {
      _mode = mode;
      _category = _categoryNames.isNotEmpty ? _categoryNames.first : 'Alimentation';
      _categoryId = null;
      _addingCustom = false;
      _customNameController.clear();
    });
  }

  void _selectCategory(String name) {
    final all = ref.read(_mode == 'expense' ? expenseCategoriesProvider : incomeCategoriesProvider);
    final found = _findCategory(all, name);
    setState(() {
      _category = name;
      _categoryId = found?.id;
      _addingCustom = name == 'Autres';
      if (name != 'Autres') _customNameController.clear();
    });
    if (name == 'Autres') {
      // Laisse le temps au champ de s'afficher, puis donne le focus.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _customFocus.requestFocus();
      });
    }
  }

  /// Prépare la catégorie personnalisée typée dans « Autres » — appelée UNIQUEMENT
  /// à la validation de l'opération (jamais pendant la frappe) : la catégorie
  /// n'est ajoutée à la liste qu'une fois l'opération validée.
  ///
  /// Renvoie un objet `(name, categoryId, createdId, errorMessage)`:
  /// - `createdId` renseigné = catégorie CRÉÉE dans ce flux (à purger si l'opération échoue)
  /// - `errorMessage` renseigné = saisie invalide / échec de création (l'opération n'est pas envoyée).
  Future<({String name, String? categoryId, String? createdId, String? errorMessage})>
      _prepareCustomCategory() async {
    if (!_addingCustom) {
      return (name: _category, categoryId: _categoryId, createdId: null, errorMessage: null);
    }
    final input = _customNameController.text;
    final check = validateCategoryName(input);
    if (!check.ok) {
      return (
        name: '',
        categoryId: null,
        createdId: null,
        errorMessage: check.error ?? 'Nom de catégorie obligatoire',
      );
    }
    // Réutilise la catégorie existante (insensible casse/accents) — aucune création.
    final all = ref.read(_mode == 'expense' ? expenseCategoriesProvider : incomeCategoriesProvider);
    final exists = _findCategory(all, check.value);
    if (exists != null) {
      return (name: exists.name, categoryId: exists.id, createdId: null, errorMessage: null);
    }
    // Création de la catégorie à la validation (l'utilisateur a touché Enregistrer).
    try {
      final wallet = ref.read(walletControllerProvider).value;
      final created = await Outbox.instance.createCategoryOfflineAware(
        type: _mode,
        name: check.value,
        walletId: wallet?.id,
      );
      ref.invalidate(categoriesProvider);
      return (name: created.name, categoryId: created.id, createdId: created.id, errorMessage: null);
    } catch (e) {
      return (
        name: '',
        categoryId: null,
        createdId: null,
        errorMessage: TransactionsController.messageFrom(e),
      );
    }
  }

  void _key(String key) {
    HapticFeedback.selectionClick();
    final code = CurrencyService.instance.current;
    final decimalsAllowed = code != 'XOF';
    setState(() {
      if (key == '⌫') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
        return;
      }
      if (key == ',') {
        if (!decimalsAllowed || _amount.contains(',')) return;
        if (_amount.isEmpty) _amount = '0';
        _amount += ',';
        return;
      }
      if (key == '000') {
        if (decimalsAllowed) return;
        final integerPart = _amount.split(',').first;
        if (_amount.isNotEmpty && integerPart.length + 3 <= 9) {
          _amount += '000';
        }
        return;
      }
      // Chiffre simple.
      final commaIndex = _amount.indexOf(',');
      if (commaIndex != -1 && _amount.length - commaIndex - 1 >= 2) {
        return; // 2 décimales max
      }
      if (commaIndex == -1) {
        final integerPart = _amount;
        if (integerPart.replaceAll(' ', '').length + 1 > (decimalsAllowed ? 7 : 9)) return;
      }
      if (_amount == '0') _amount = '';
      _amount += key;
      if (commaIndex == -1) _amount = _amount.replaceFirst(RegExp(r'^0+'), '');
    });
  }

  Future<void> _save() async {
    final code = CurrencyService.instance.current;
    final amount = enteredToXof(_amount, code);
    if (amount == null || amount <= 0) {
      _snack('Entre un montant');
      return;
    }
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) {
      _snack("Aucun portefeuille — crée-le d'abord");
      return;
    }

    // Contrôle du budget côté UI (miroir du contrôle serveur) : une dépense ne
    // doit jamais dépasser le reste du « Budget du mois ».
    if (_mode == 'expense') {
      final dashboard = ref.read(dashboardControllerProvider).value;
      if (dashboard != null) {
        final oldAmount = (widget.editing != null && widget.editing!.isExpense) ? widget.editing!.amount : 0;
        final remaining = budgetRemainingXof(
          initialAmount: dashboard.initialAmount,
          totalIncomes: dashboard.totalIncomes,
          totalExpenses: dashboard.totalExpenses - oldAmount,
          savingsAmount: wallet.savingsAmount,
        );
        if (remaining != null && amount > remaining) {
          _snack('Montant supérieur au budget restant (${formatMoneyCurrent(remaining)})');
          return;
        }
      }
    }

    // Catégorie personnalisée « Autres » : préparée à la validation uniquement
    // (création à la validation de l'opération, jamais pendant la frappe).
    final custom = await _prepareCustomCategory();
    if (custom.errorMessage != null) {
      _snack(custom.errorMessage!);
      return;
    }

    setState(() => _saving = true);
    var createdCategoryId = custom.createdId;
    try {
      final tx = Transaction(
        id: widget.editing?.id ?? '',
        walletId: wallet.id,
        type: _mode,
        amount: amount,
        category: custom.name,
        categoryId: custom.categoryId ?? widget.editing?.categoryId,
        date: widget.editing?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        time: widget.editing?.time ?? DateFormat('HH:mm').format(DateTime.now()),
        paymentMethod: _mode == 'expense' ? (widget.editing?.paymentMethod ?? 'Espèces') : null,
      );
      WriteResult result;
      if (widget.editing == null) {
        result = await Outbox.instance.createTransaction(wallet.id, tx);
      } else {
        result = await Outbox.instance.updateTransaction(wallet.id, tx);
      }
      if (!result.queued) {
        await ref.read(transactionsProvider.notifier).refreshAll();
      } else {
        ref.invalidate(dashboardControllerProvider);
        ref.invalidate(walletControllerProvider);
        ref.invalidate(transactionsProvider);
        await ref.read(syncInfoProvider.notifier).refresh();
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (result.queued) {
        // Opération non encore confirmée par le serveur : feedback distinct (pas de faux succès).
        showInfoSnackBar(
          context,
          'Enregistrée hors-ligne — synchronisation dès le retour du réseau',
          icon: Icons.cloud_off_outlined,
        );
        Navigator.of(context).pop();
        return;
      }
      // Boîte de succès affichée au-dessus de la feuille, puis on ferme la feuille.
      await showSuccessDialog(context);
      if (mounted) Navigator.of(context).pop();
      createdCategoryId = null; // succès : on garde la catégorie créée
    } catch (e) {
      // L'opération a échoué : on retire la catégorie créée dans ce flux pour
      // ne pas laisser une catégorie partielle dans la liste.
      if (createdCategoryId != null) {
        try {
          await CategoryRepository.instance.delete(createdCategoryId);
          ref.invalidate(categoriesProvider);
        } catch (_) {
          // Mieux vaut laisser la catégorie que l'opération perdue.
        }
      }
      if (!mounted) return;
      _snack(TransactionsController.messageFrom(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    // Cohérence des messages d'erreur — même présentation partout.
    showErrorSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? AppColors.darkBg : AppColors.offWhite;
    final currency = ref.watch(currencyControllerProvider).code;
    final symbol = currencySymbol(currency);
    final label = _amount.isEmpty ? '0' : groupEnteredInput(_amount);

    // Reste du « Budget du mois » — même formule que le contrôle serveur
    // (devise de référence XOF, entiers). Pour une modification, l'ancien montant
    // de l'opération n'est pas compté comme dépense (reste réinclus).
    final dashboard = ref.watch(dashboardControllerProvider).value;
    final wallet = ref.watch(walletControllerProvider).value;
    final parsedAmount = enteredToXof(_amount, currency);
    final oldAmount = (widget.editing != null && widget.editing!.isExpense) ? widget.editing!.amount : 0;
    int? budgetRemaining;
    if (_mode == 'expense' && wallet != null && dashboard != null) {
      budgetRemaining = budgetRemainingXof(
        initialAmount: dashboard.initialAmount,
        totalIncomes: dashboard.totalIncomes,
        totalExpenses: dashboard.totalExpenses - oldAmount,
        savingsAmount: wallet.savingsAmount,
      );
    }
    final exceedsBudget = _mode == 'expense' &&
        budgetRemaining != null &&
        parsedAmount != null &&
        parsedAmount > budgetRemaining;

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
                      text: ' $symbol',
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
              const SizedBox(height: 4),
              if (exceedsBudget)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Montant supérieur au budget restant (${formatMoneyCurrent(budgetRemaining)})',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categoryNames.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final name = _categoryNames[i];
                    final selected = name == _category;
                    return GestureDetector(
                      onTap: () => _selectCategory(name),
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
              if (_addingCustom) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nom de la catégorie',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 6),
                      // Le texte est contrasté sur le fond, curseur visible, taille lisible.
                      TextField(
                        controller: _customNameController,
                        focusNode: _customFocus,
                        maxLength: 30,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        cursorColor: scheme.primary,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          counterText: '',
                          hintText: 'Ex. Essence',
                          hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.65)),
                        ),
                      ),
                      // Aperçu en direct : « Essence » · 2 000 FCFA
                      if (_typedCustom.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.sell_outlined, size: 15, color: scheme.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _typedCustom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '·',
                              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatMoneyCurrent(parsedAmount ?? 0),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final row in (currency == 'XOF'
                      ? const [
                          ['1', '2', '3'],
                          ['4', '5', '6'],
                          ['7', '8', '9'],
                          ['000', '0', '⌫'],
                        ]
                      : const [
                          ['1', '2', '3'],
                          ['4', '5', '6'],
                          ['7', '8', '9'],
                          [',', '0', '⌫'],
                        ]))
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
              // Bouton désactivé pendant l'enregistrement ou si le montant dépasse
              // le reste du budget (message affiché juste au-dessus).
              Opacity(
                opacity: (_saving || exceedsBudget) ? 0.55 : 1.0,
                child: Container(
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
                      onTap: (_saving || exceedsBudget) ? null : _save,
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
