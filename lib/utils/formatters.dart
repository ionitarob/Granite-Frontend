import 'package:intl/intl.dart';

class NumberFormatters {
  static final NumberFormat _decimalFormat = NumberFormat.decimalPattern('es_ES');
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 2,
  );
  static final NumberFormat _integerFormat = NumberFormat.decimalPattern('es_ES');

  /// Formats a number with dots for thousands and commas for decimals if they exist.
  /// If [decimals] is 0, it behaves like an integer format.
  static String format(num value, {int? decimals}) {
    if (decimals == 0) {
      return _integerFormat.format(value.toInt());
    }
    if (decimals != null) {
      final customFormat = NumberFormat.decimalPattern('es_ES');
      customFormat.minimumFractionDigits = decimals;
      customFormat.maximumFractionDigits = decimals;
      return customFormat.format(value);
    }
    return _decimalFormat.format(value);
  }

  /// Formats a number as a currency (e.g. 1.234,56 €)
  static String formatCurrency(num value) {
    return _currencyFormat.format(value);
  }
}

extension NumberFormattingExtension on num {
  /// Returns the number formatted in Spanish style (e.g. 1.234,5)
  String get formatted => NumberFormatters.format(this);

  /// Returns the number formatted in Spanish style with no decimals (e.g. 1.234)
  String get formattedInt => NumberFormatters.format(this, decimals: 0);

  /// Returns the number formatted as currency in Spanish style (e.g. 1.234,56 €)
  String get asCurrency => NumberFormatters.formatCurrency(this);
}
