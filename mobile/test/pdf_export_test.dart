import 'package:flutter_test/flutter_test.dart';
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  test('buildPdfBytes génère un PDF valide avec du contenu réel', () async {
    final bytes = await TransactionPdfExportService.buildPdfBytes(
      walletName: 'Mon budget',
      displayName: 'E2E Testeur',
      transactions: [
        _tx(id: '1', type: 'expense', description: 'Courses'),
        _tx(id: '2', type: 'income', category: 'Salaire', description: 'Virement'),
        _tx(id: '3', type: 'savings_deposit', category: 'Épargne'),
      ],
    );

    expect(bytes.length, greaterThan(1500), reason: 'un PDF avec contenu doit dépasser la taille d’en-tête');

    // Signature PDF (le contenu est compressé FlateDecode, on vérifie l’en-tête)
    final header = String.fromCharCodes(bytes.take(5));
    expect(header, '%PDF-');
  });

  test('buildPdfBytes génère un PDF valide même sans transaction', () async {
    final bytes = await TransactionPdfExportService.buildPdfBytes(
      walletName: 'Mon budget',
      transactions: const [],
    );
    final header = String.fromCharCodes(bytes.take(5));
    expect(header, '%PDF-');
    expect(bytes.length, greaterThan(800));
  });
}
