import 'dart:io';

import 'package:intl/date_symbol_data_local.dart';

import 'package:mybudget/models/transaction.dart';
import 'package:mybudget/services/transaction_pdf_export_service.dart';

Transaction _tx({
  required String id,
  required String type,
  int amount = 5000,
  String category = 'Alimentation',
  String? description,
}) =>
    Transaction(
      id: id,
      walletId: 'w1',
      type: type,
      amount: amount,
      category: category,
      description: description,
      date: '2026-11-14',
      time: '12:32',
    );

Future<void> main() async {
  await initializeDateFormatting('fr_FR');
  final bytes = await TransactionPdfExportService.buildPdfBytes(
    walletName: 'Mon budget',
    initialAmount: 100000,
    displayName: 'Ulrich',
    transactions: [
      _tx(id: '1', type: 'expense', description: 'Courses', amount: 15000),
      _tx(id: '2', type: 'income', category: 'Salaire', description: 'Virement', amount: 250000),
      _tx(id: '3', type: 'savings_deposit', category: 'Épargne', amount: 20000),
    ],
  );
  final file = File('C:/Users/Ulrich IDOHOU/AppData/Local/Temp/opencode/sample_blackwhite.pdf');
  await file.writeAsBytes(bytes, flush: true);
  stdout.writeln('saved ${file.path} (${bytes.length} bytes)');
}
