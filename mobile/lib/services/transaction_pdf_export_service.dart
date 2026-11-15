import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/money.dart';
import '../models/transaction.dart';
import '../services/data_repository.dart';

class TransactionPdfExportService {
  TransactionPdfExportService._();

  static Future<String> export({
    required String walletId,
    required String walletName,
    required int initialAmount,
    String? displayName,
  }) async {
    final transactions = <Transaction>[];
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
      transactions.addAll(result.transactions);
      if (page >= result.pages || result.transactions.isEmpty) break;
      page++;
    }

    final bytes = await buildPdfBytes(
      walletName: walletName,
      initialAmount: initialAmount,
      transactions: transactions,
      displayName: displayName,
    );
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File('${directory.path}/mybudget-transactions-$timestamp.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<List<int>> buildPdfBytes({
    required String walletName,
    required int initialAmount,
    required List<Transaction> transactions,
    String? displayName,
  }) async {
    // Palette de marque (valeurs 0..1 pour éviter toute ambiguïté de conversion).
    const deepGreen = pw.PdfColor(0.043, 0.365, 0.231); // #0B5D3B
    const deepGreenDark = pw.PdfColor(0.027, 0.239, 0.149); // #074026
    const mintSoft = pw.PdfColor(0.918, 0.965, 0.937); // #EAF6EF — fond doux
    const rowAlt = pw.PdfColor(0.965, 0.980, 0.969); // #F6FAF7 — lignes alternées
    const ink = pw.PdfColor(0.122, 0.141, 0.188); // #1F2430 — texte
    const muted = pw.PdfColor(0.40, 0.43, 0.46); // #676E75 — gris texte
    const border = pw.PdfColor(0.816, 0.843, 0.824); // #D0D7D2 — bordures
    const incomeGreen = pw.PdfColor(0.122, 0.616, 0.388); // #1F9D63 — revenus
    const expenseRed = pw.PdfColor(0.753, 0.224, 0.169); // #C0392B — dépenses
    const offWhite = pw.PdfColor(0.984, 0.984, 0.973); // #FBFBF8 — fond de page

    final document = pw.Document();
    final expenses = transactions
        .where((transaction) => transaction.isExpense)
        .fold<int>(0, (sum, transaction) => sum + transaction.amount);
    final incomes = transactions
        .where((transaction) => transaction.isIncome)
        .fold<int>(0, (sum, transaction) => sum + transaction.amount);
    final generatedAt = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(DateTime.now());

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 34),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            'MYBUDGET  |  Historique des opérations',
            style: const pw.TextStyle(color: pw.PdfColor(0.40, 0.43, 0.46), fontSize: 8),
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(color: pw.PdfColor(0.40, 0.43, 0.46), fontSize: 8),
          ),
        ),
        build: (context) => [
          // Bandeau de marque : vert profond, titre en blanc.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(24, 18, 24, 18),
            decoration: pw.BoxDecoration(
              color: deepGreen,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 46,
                  height: 46,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: pw.PdfColor(1, 1, 1, 0.18),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Text(
                    'M',
                    style: pw.TextStyle(
                      color: const pw.PdfColor(1, 1, 1),
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Historique des transactions',
                        style: pw.TextStyle(
                          color: const pw.PdfColor(1, 1, 1),
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Portefeuille : $walletName',
                        style: const pw.TextStyle(
                          color: pw.PdfColor(0.91, 0.96, 0.92),
                          fontSize: 11,
                        ),
                      ),
                      if (displayName != null && displayName.trim().isNotEmpty)
                        pw.Text(
                          'Compte : ${displayName.trim()}',
                          style: const pw.TextStyle(
                            color: pw.PdfColor(0.91, 0.96, 0.92),
                            fontSize: 9,
                          ),
                        ),
                      pw.Text(
                        'Généré le $generatedAt',
                        style: const pw.TextStyle(
                          color: pw.PdfColor(0.75, 0.86, 0.78),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          // Cartes de synthèse sur fond mint.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: mintSoft,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              border: pw.Border.all(color: border, width: 0.6),
            ),
            child: pw.Row(
              children: [
                _summaryCard('Transactions', '${transactions.length}', deepGreen, ink, offWhite),
                pw.SizedBox(width: 10),
                _summaryCard('Revenus', formatXof(incomes), incomeGreen, ink, offWhite),
                pw.SizedBox(width: 10),
                _summaryCard('Dépenses', formatXof(expenses), expenseRed, ink, offWhite),
                pw.SizedBox(width: 10),
                _summaryCard('Solde initial', formatXof(initialAmount), deepGreenDark, ink, offWhite),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          if (transactions.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Center(
                child: pw.Text(
                  'Aucune transaction enregistrée.',
                  style: const pw.TextStyle(color: muted, fontSize: 12),
                ),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Heure', 'Type', 'Catégorie', 'Description', 'Paiement', 'Montant'],
              data: transactions.map((transaction) {
                final isIncome = transaction.isIncome;
                final isSavings = transaction.isSavings;
                final sign = isSavings ? '' : (isIncome ? '+ ' : '- ');
                final typeLabel = isSavings
                    ? 'Épargne'
                    : (isIncome ? 'Revenu' : 'Dépense');
                return [
                  formatDateFr(transaction.date),
                  transaction.time,
                  typeLabel,
                  transaction.category,
                  transaction.description?.trim().isNotEmpty == true
                      ? transaction.description!.trim()
                      : '—',
                  transaction.paymentMethod ?? '—',
                  '$sign${formatXof(transaction.amount)}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                color: const pw.PdfColor(1, 1, 1),
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8, color: ink),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              headerDecoration: const pw.BoxDecoration(color: deepGreen),
              oddRowDecoration: const pw.BoxDecoration(color: rowAlt),
              border: pw.TableBorder.all(color: border, width: 0.4),
              columnWidths: const {
                0: pw.FixedColumnWidth(62),
                1: pw.FixedColumnWidth(42),
                2: pw.FixedColumnWidth(58),
                3: pw.FixedColumnWidth(78),
                4: pw.FlexColumnWidth(3),
                5: pw.FixedColumnWidth(92),
                6: pw.FixedColumnWidth(86),
              },
            ),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _summaryCard(String label, String value, pw.PdfColor accent, pw.PdfColor ink, pw.PdfColor cardBg) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: cardBg,
            border: pw.Border.all(color: accent, width: 1.2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(color: accent, fontSize: 7, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(color: ink, fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
      );
}
