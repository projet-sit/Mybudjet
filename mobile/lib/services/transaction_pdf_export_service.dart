import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/money.dart';
import '../models/transaction.dart';
import '../services/cache_service.dart';
import '../services/currency_service.dart';
import '../services/data_repository.dart';
import '../services/outbox.dart';

/// Palette strictement noir & blanc (+ un gris très clair pour alterner les lignes).
const _kBlack = PdfColor(0, 0, 0);
const _kDarkGrey = PdfColor(0.35, 0.35, 0.35); // texte secondaire
const _kRowGrey = PdfColor(0.94, 0.94, 0.94); // lignes alternées uniquement
const _kHairline = PdfColor(0, 0, 0); // filets fins noirs

/// Export PDF du relevé des opérations - noir et blanc strict, A4 portrait.
///
/// - en-tête : nom de l'application, titre « Relevé des opérations »,
///   date/heure de génération, devise utilisée, période couverte ;
/// - résumé : total des revenus, total des dépenses, solde ;
/// - tableau : Date | Type | Catégorie | Montant
///   (filets fins noirs, en-tête en gras répété à chaque page, montants
///   alignés à droite avec « + » ou « - ») ;
/// - pied de page : « Page X / Y » ;
/// - nom du fichier : operations_AAAA-MM-JJ.pdf.
class TransactionPdfExportService {
  TransactionPdfExportService._();

  static Future<String> export({
    required String walletId,
    required String walletName,
    String? displayName,
  }) async {
    final transactions = await _loadAllTransactions(walletId);

    final bytes = await buildPdfBytes(
      walletName: walletName,
      transactions: transactions,
      displayName: displayName,
    );

    final directory = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final path = '${directory.path}/operations_$stamp.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Toutes les opérations, en ligne si possible, sinon repli sur le cache
  /// local (le PDF reste générable hors connexion).
  static Future<List<Transaction>> _loadAllTransactions(String walletId) async {
    try {
      final out = <Transaction>[];
      var page = 1;
      while (true) {
        final result = await TransactionRepository.instance.list(
          walletId,
          query: {
            'all': '1',
            'page': '$page',
            'limit': '100',
            'sortBy': 'date',
            'sortDir': 'asc',
          },
        );
        out.addAll(result.transactions);
        if (page >= result.pages || result.transactions.isEmpty) break;
        page++;
        if (page > 200) break; // garde-fou
      }
      return Outbox.instance.applyOverlay(out);
    } catch (_) {
      var ledger = await CacheService.instance.loadTransactions(walletId);
      ledger = await Outbox.instance.applyOverlay(ledger);
      final sorted = [...ledger]..sort((a, b) => a.date.compareTo(b.date));
      return sorted;
    }
  }

  static Future<List<int>> buildPdfBytes({
    required String walletName,
    required List<Transaction> transactions,
    String? displayName,
    String? currency,
  }) async {
    final code = currency ?? CurrencyService.instance.current;

    final expenses = transactions
        .where((t) => t.isExpense)
        .fold<int>(0, (sum, t) => sum + t.amount);
    final incomes = transactions
        .where((t) => t.isIncome)
        .fold<int>(0, (sum, t) => sum + t.amount);
    final balance = incomes - expenses;

    final generatedAt = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(DateTime.now());
    final currencyLabel = switch (code) {
      'EUR' => 'Euro (€)',
      'USD' => 'Dollar américain (\$)',
      _ => 'Franc CFA (FCFA)',
    };
    final period = _periodLabel(transactions);

    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 44),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _kBlack, width: 1)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'MYBUDGET',
                style: pw.TextStyle(color: _kBlack, fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Relevé des opérations',
                style: pw.TextStyle(color: _kDarkGrey, fontSize: 8),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _kBlack, width: 1)),
          ),
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(color: _kBlack, fontSize: 8),
          ),
        ),
        build: (context) => [
          // ---------- En-tête du relevé ----------
          pw.SizedBox(height: 4),
          pw.Text(
            'MYBUDGET',
            style: pw.TextStyle(
              color: _kBlack,
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Relevé des opérations',
            style: pw.TextStyle(color: _kBlack, fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Container(height: 1.6, color: _kBlack),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _metaLine('Généré le', generatedAt),
                    _metaLine('Portefeuille', walletName),
                    if (displayName != null && displayName.trim().isNotEmpty)
                      _metaLine('Compte', displayName.trim()),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _metaLine('Devise', currencyLabel),
                    _metaLine('Période', period),
                    _metaLine('Opérations', '${transactions.length}'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ---------- Synthèse ----------
          pw.Text(
            'Synthèse',
            style: pw.TextStyle(color: _kBlack, fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _summaryCell('Total des revenus', formatMoney(incomes, currency: code)),
              pw.SizedBox(width: 10),
              _summaryCell('Total des dépenses', formatMoney(expenses, currency: code)),
              pw.SizedBox(width: 10),
              _summaryCell('Solde', formatMoney(balance, currency: code)),
            ],
          ),
          pw.SizedBox(height: 16),

          // ---------- Tableau des opérations ----------
          pw.Text(
            'Détail des opérations',
            style: pw.TextStyle(color: _kBlack, fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (transactions.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 28),
              child: pw.Center(
                child: pw.Text(
                  'Aucune opération enregistrée.',
                  style: const pw.TextStyle(color: _kDarkGrey, fontSize: 12),
                ),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: _kHairline, width: 0.4),
              columnWidths: const {
                0: pw.FixedColumnWidth(78), // Date
                1: pw.FixedColumnWidth(66), // Type
                2: pw.FlexColumnWidth(2), // Catégorie
                3: pw.FixedColumnWidth(110), // Montant
              },
              children: [
                pw.TableRow(
                  repeat: true, // en-tête répété à chaque page
                  children: [
                    _headerCell('Date'),
                    _headerCell('Type'),
                    _headerCell('Catégorie'),
                    _headerCell('Montant', alignRight: true),
                  ],
                ),
                for (var i = 0; i < transactions.length; i++)
                  _dataRow(transactions[i], code, i.isOdd ? _kRowGrey : null),
              ],
            ),
        ],
      ),
    );

    return document.save();
  }

  static String _periodLabel(List<Transaction> transactions) {
    if (transactions.isEmpty) return 'Toutes les opérations';
    final dates = transactions.map((t) => t.date).where((d) => d.length >= 10).toList()..sort();
    if (dates.isEmpty) return 'Toutes les opérations';
    return '${_formatDate(dates.first)} au ${_formatDate(dates.last)}';
  }

  static pw.Widget _metaLine(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 74,
              child: pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(color: _kDarkGrey, fontSize: 6.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(color: _kBlack, fontSize: 8.5),
              ),
            ),
          ],
        ),
      );

  static pw.Widget _summaryCell(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _kBlack, width: 0.8),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(color: _kDarkGrey, fontSize: 6.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                value,
                style: pw.TextStyle(color: _kBlack, fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
      );

  static pw.Widget _headerCell(String text, {bool alignRight = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: pw.Text(
          text,
          textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(color: _kBlack, fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.TableRow _dataRow(Transaction t, String code, PdfColor? fill) {
    final isIncome = t.isIncome;
    final isSavings = t.isSavings;
    final sign = isSavings
        ? (t.isSavingsWithdrawal ? '+' : '-')
        : (isIncome ? '+' : '-');
    final typeLabel = isSavings ? 'Épargne' : (isIncome ? 'Revenu' : 'Dépense');
    final cellStyle = const pw.TextStyle(color: _kBlack, fontSize: 8);

    pw.Widget cell(String text, {bool alignRight = false}) => pw.Container(
          color: fill,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(
            text,
            textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
            style: cellStyle,
          ),
        );

    return pw.TableRow(
      children: [
        cell(_formatDate(t.date)),
        cell(typeLabel),
        cell(t.category),
        cell('$sign ${formatMoney(t.amount, currency: code)}', alignRight: true),
      ],
    );
  }

  static String _formatDate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('dd/MM/yyyy', 'fr_FR').format(d);
  }
}
