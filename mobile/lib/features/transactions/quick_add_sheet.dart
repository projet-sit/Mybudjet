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
  bool _savingCategory = false;
  final _customNameController = TextEditingController();
  final _customFocus = FocusNode();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final tx = widget.editing;
    if (tx != null) {
      _mode = tx.type == 'income' ? 'income' : 'expense';
      _amount = _editableAmount(tx.amount);
      _category = tx.category;
      _categoryId = tx.categoryId;
      _noteController.text = tx.description ?? '';
    }
  }

  /// Montant (XOF en base) reconverti pour le champ de saisie dans la devise active.
  String _editableAmount(int xof) {
    final code = CurrencyService.instance.current;
    if (code == 'XOF') return '$xof';
    final value = CurrencyService.convertFromXof(xof, code);
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _customFocus.dispose();
    _noteController.dispose();
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

  /// Garantit que `_category`/`_categoryId` reflètent le champ « Autres » :
  /// si l'utilisateur a tapé un nom sans appuyer sur « Valider », la catégorie
  /// est créée (ou retrouvée) ici avant l'enregistrement.
  /// Renvoie un message de succès, une chaîne vide si rien à faire, ou null
  /// si le nom est invalide (l'enregistrement est alors abandonné).
  Future<String?> _ensureCustomCategory() async {
    if (!_addingCustom) return ''; // catégorie déjà sélectionnée : rien à faire
    final input = _customNameController.text;
    final check = validateCategoryName(input);
    if (!check.ok) {
      _snack(check.error ?? 'Nom de catégorie obligatoire');
      return null;
    }
    final all = ref.read(_mode == 'expense' ? expenseCategoriesProvider : incomeCategoriesProvider);
    final exists = _findCategory(all, check.value);
    if (exists != null) {
      setState(() {
        _category = exists.name;
        _categoryId = exists.id;
        _addingCustom = false;
        _customNameController.clear();
      });
      return 'Cette catégorie existe déjà, elle est sélectionnée';
    }
    setState(() => _savingCategory = true);
    try {
      final wallet = ref.read(walletControllerProvider).value;
      final created = await Outbox.instance.createCategoryOfflineAware(
        type: _mode,
        name: check.value,
        walletId: wallet?.id,
      );
      ref.invalidate(categoriesProvider);
      if (!mounted) return null;
      setState(() {
        _category = created.name;
        _categoryId = created.id;
        _addingCustom = false;
        _customNameController.clear();
      });
      return 'Catégorie « ${created.name} » créée';
    } catch (e) {
      if (!mounted) return null;
      _snack(TransactionsController.messageFrom(e));
      return null;
    } finally {
      if (mounted) setState(() => _savingCategory = false);
    }
  }

  /// Valide le nom saisi dans le champ « Autres » (bouton « Valider »).
  Future<void> _createCustomCategory() async {
    final message = await _ensureCustomCategory();
    if (message == null || !mounted) return;
    if (message.startsWith('Catégorie «')) {
      await showSuccessDialog(
        context,
        title: 'Catégorie créée !',
        message: 'Votre catégorie personnalisée a été enregistrée.',
      );
    } else {
      showInfoSnackBar(context, message);
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
    // Si l'utilisateur a saisi une catégorie libre sans valider, on la crée/retrouve ici.
    final customMessage = await _ensureCustomCategory();
    if (customMessage == null) return;

    setState(() => _saving = true);
    try {      final tx = Transaction(
        id: widget.editing?.id ?? '',
        walletId: wallet.id,
        type: _mode,
        amount: amount,
        category: _category,
        categoryId: _categoryId ?? widget.editing?.categoryId,
        description: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
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
        // Opération non encore confirmée par le serveur : feedback distinct.
        showInfoSnackBar(
          context,
          'Enregistrée hors-ligne — synchronisation dès le retour du réseau',
          icon: Icons.cloud_off_outlined,
        );
        Navigator.of(context).pop();
        return;
      }
      // La boîte de succès s'affiche au-dessus de la feuille, puis on ferme la feuille.
      await showSuccessDialog(
        context,
        title: widget.editing == null ? 'Opération enregistrée !' : 'Opération modifiée !',
        message: widget.editing == null
            ? 'Votre opération a été enregistrée avec succès.'
            : 'Vos informations ont été mises à jour avec succès.',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
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
              const SizedBox(height: 12),
              // Champ libre « dans quoi as-tu dépensé ? » (note de l'opération).
              // Utile quand aucune catégorie ne correspond exactement. Reste
              // facultatif ; s'affiche dans la liste pour la retrouver vite.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: fieldBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outline),
                ),
                child: TextField(
                  controller: _noteController,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    counterText: '',
                    hintText: _mode == 'expense'
                        ? 'Dans quoi as-tu dépensé ? (facultatif)'
                        : 'D’où vient cet argent ? (facultatif)',
                    prefixIcon: Icon(Icons.edit_note_outlined, size: 18, color: scheme.onSurfaceVariant),
                    prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nom de la catégorie',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customNameController,
                              focusNode: _customFocus,
                              maxLength: 30,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: 'Ex. Coiffure',
                                counterText: '',
                              ),
                              onSubmitted: (_) => _savingCategory ? null : _createCustomCategory(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 38,
                            child: FilledButton(
                              onPressed: _savingCategory ? null : _createCustomCategory,
                              child: _savingCategory
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Valider'),
                            ),
                          ),
                        ],
                      ),
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
