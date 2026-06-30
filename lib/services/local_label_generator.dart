import 'dart:math';

import 'package:intl/intl.dart';

class LocalLabelGenerator {
  static const Map<int, String> _vodafoneMonthLetters = <int, String>{
    1: 'E',
    2: 'F',
    3: 'M',
    4: 'A',
    5: 'Y',
    6: 'J',
    7: 'L',
    8: 'A',
    9: 'S',
    10: 'O',
    11: 'N',
    12: 'D',
  };

  static const int _defaultPadding = 5;

  static List<String> generate({
    required String operatorName,
    required DateTime productionDate,
    required int totalUnits,
    required String? article,
    required String? sapClient,
    required String? codeLetter,
    required int startSequence,
  }) {
    if (totalUnits <= 0) return const <String>[];
    final normalized = operatorName.trim().toLowerCase();
    if (normalized.contains('orange')) {
      final descriptor = _preferredDescriptor(article, sapClient, codeLetter, fallback: 'OR');
      return _buildOrangeLabels(
        productionDate: productionDate,
        descriptor: descriptor,
        totalUnits: totalUnits,
        startSequence: startSequence,
      );
    }
    // Use Vodafone (SAP-based) format when sapClient is set, regardless of operator name.
    // This handles cases where the operator name doesn't contain "vodafone" exactly.
    final sap = (sapClient ?? '').trim();
    if (normalized.contains('vodafone') || sap.isNotEmpty) {
      if (sap.isEmpty) {
        throw StateError('El tipo seleccionado no tiene SAP asociado.');
      }
      return _buildVodafoneLabels(
        productionDate: productionDate,
        sapClient: sap,
        totalUnits: totalUnits,
        startSequence: startSequence,
      );
    }
    final displayArticle = _preferredDescriptor(article, sapClient, codeLetter);
    return _buildGenericLabels(
      productionDate: productionDate,
      descriptor: displayArticle,
      totalUnits: totalUnits,
      startSequence: startSequence,
    );
  }

  static List<String> _buildOrangeLabels({
    required DateTime productionDate,
    required String descriptor,
    required int totalUnits,
    required int startSequence,
  }) {
    final dateSegment = DateFormat('yyyyMMdd').format(productionDate);
    final padding = _sequencePadding(totalUnits, startSequence);
    return List<String>.generate(totalUnits, (index) {
      final seq = startSequence + index;
      final seqText = seq.toString().padLeft(padding, '0');
      return '$dateSegment$descriptor$seqText';
    });
  }

  static List<String> _buildVodafoneLabels({
    required DateTime productionDate,
    required String sapClient,
    required int totalUnits,
    required int startSequence,
  }) {
    final yearDigit = productionDate.year % 10;
    final monthLetter = _vodafoneMonthLetters[productionDate.month] ?? 'X';
    final dayText = productionDate.day.toString().padLeft(2, '0');
    final prefix = '$sapClient$yearDigit$monthLetter$dayText';
    final padding = _sequencePadding(totalUnits, startSequence);
    return List<String>.generate(totalUnits, (index) {
      final seq = startSequence + index;
      final seqText = seq.toString().padLeft(padding, '0');
      return '$prefix$seqText';
    });
  }

  static List<String> _buildGenericLabels({
    required DateTime productionDate,
    required String descriptor,
    required int totalUnits,
    required int startSequence,
  }) {
    final dateSegment = DateFormat('yyyyMMdd').format(productionDate);
    final padding = _sequencePadding(totalUnits, startSequence);
    return List<String>.generate(totalUnits, (index) {
      final seq = startSequence + index;
      final seqText = seq.toString().padLeft(padding, '0');
      return '$dateSegment$descriptor$seqText';
    });
  }

  static int _sequencePadding(int totalUnits, int startSequence) {
    final maxValue = startSequence + totalUnits - 1;
    final calculated = max(_defaultPadding, maxValue.toString().length);
    return calculated;
  }

  static String _preferredDescriptor(String? article, String? sapClient, String? codeLetter, {String fallback = 'TIPO'}) {
    final letter = _sanitizeDescriptor(codeLetter);
    if (letter.isNotEmpty) return letter;
    final trimmedArticle = _sanitizeDescriptor(article);
    if (trimmedArticle.isNotEmpty) return trimmedArticle;
    final trimmedSap = _sanitizeDescriptor(sapClient);
    if (trimmedSap.isNotEmpty) return trimmedSap;
    return fallback;
  }

  static String _sanitizeDescriptor(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return '';
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return sanitized;
  }
}
