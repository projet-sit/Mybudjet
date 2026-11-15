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
        margin: const pw.EdgeInsets.fromLTRB(30, 34, 30, 34),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            'MYBUDGET  |  Historique des transactions',
            style: pw.TextStyle(color: PdfColors.grey700, fontSize: 8),
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 8),
          ),
        ),
        build: (context) => [
          pw.Text(
            'Export des transactions',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text('Portefeuille : $walletName', style: const pw.TextStyle(fontSize: 11)),
          if (displayName != null && displayName.trim().isNotEmpty)
            pw.Text('Compte : ${displayName.trim()}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Généré le $generatedAt', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 16),
          pw.Row(
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
          pw.SizedBox(height: 18),
          if (transactions.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Text('Aucune transaction enregistrée.'),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Heure', 'Type', 'Catégorie', 'Description', 'Mode de paiement', 'Montant'],
              data: transactions.map((transaction) {
                final sign = transaction.isSavings
                    ? ''
                    : (transaction.isExpense ? '- ' : '+ ');
                final typeLabel = transaction.isSavings
                    ? 'Épargne'
                    : (transaction.isExpense ? 'Dépense' : 'Revenu');
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
                color: PdfColors.white,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0B5D3B)),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F5F3)),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
              columnWidths: {
                0: const pw.FixedColumnWidth(62),
                1: const pw.FixedColumnWidth(42),
                2: const pw.FixedColumnWidth(55),
                3: const pw.FixedColumnWidth(78),
                4: const pw.FlexColumnWidth(3),
                5: const pw.FixedColumnWidth(92),
                6: const pw.FixedColumnWidth(86),
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
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      );
}
