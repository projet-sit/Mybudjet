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
    // Palette noir & blanc (impression contrastée, valeurs 0..1).
    const black = PdfColor(0, 0, 0); // texte principal, bandeau, en-tête de tableau
    const darkGrey = PdfColor(0.35, 0.35, 0.35); // texte secondaire
    const lightGrey = PdfColor(0.93, 0.93, 0.93); // lignes alternées / fonds doux
    const border = PdfColor(0.72, 0.72, 0.72); // bordures grises

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
            style: const pw.TextStyle(color: PdfColor(0.4, 0.4, 0.4), fontSize: 8),
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(color: PdfColor(0.4, 0.4, 0.4), fontSize: 8),
          ),
        ),
        build: (context) => [
          // Bandeau noir, titre blanc — noir et blanc strict.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(24, 18, 24, 18),
            decoration: pw.BoxDecoration(
              color: black,
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
                    color: PdfColor(1, 1, 1, 0.18),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Text(
                    'M',
                    style: pw.TextStyle(
                      color: const PdfColor(1, 1, 1),
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
                          color: const PdfColor(1, 1, 1),
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Portefeuille : $walletName',
                        style: const pw.TextStyle(
                          color: PdfColor(0.82, 0.82, 0.82),
                          fontSize: 11,
                        ),
                      ),
                      if (displayName != null && displayName.trim().isNotEmpty)
                        pw.Text(
                          'Compte : ${displayName.trim()}',
                          style: const pw.TextStyle(
                            color: PdfColor(0.82, 0.82, 0.82),
                            fontSize: 9,
                          ),
                        ),
                      pw.Text(
                        'Généré le $generatedAt',
                        style: const pw.TextStyle(
                          color: PdfColor(0.7, 0.7, 0.7),
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
          // Cartes de synthèse sur fond gris très clair.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: lightGrey,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              border: pw.Border.all(color: border, width: 0.6),
            ),
            child: pw.Row(
              children: [
                _summaryCard('Transactions', '${transactions.length}'),
                pw.SizedBox(width: 10),
                _summaryCard('Revenus', formatXof(incomes)),
                pw.SizedBox(width: 10),
                _summaryCard('Dépenses', formatXof(expenses)),
                pw.SizedBox(width: 10),
                _summaryCard('Solde initial', formatXof(initialAmount)),
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
                  style: const pw.TextStyle(color: darkGrey, fontSize: 12),
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
                      : '-',
                  transaction.paymentMethod ?? '-',
                  '$sign${formatXof(transaction.amount)}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                color: const PdfColor(1, 1, 1),
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8, color: black),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              headerDecoration: const pw.BoxDecoration(color: black),
              oddRowDecoration: const pw.BoxDecoration(color: lightGrey),
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

  static pw.Widget _summaryCard(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: const PdfColor(1, 1, 1),
            border: pw.Border.all(color: const PdfColor(0, 0, 0), width: 1.2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label.toUpperCase(),
                style: const pw.TextStyle(
                  color: PdfColor(0.35, 0.35, 0.35),
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: const pw.TextStyle(
                  color: PdfColor(0, 0, 0),
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
}
