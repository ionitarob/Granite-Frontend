import 'package:flutter/services.dart';

/// Formats order numbers into the pattern XX-XXXXX-XX while typing.
/// Keeps only alphanumeric characters and inserts '-' after 2 and after 7 characters.
class OrderInputFormatter extends TextInputFormatter {
  static final _allowed = RegExp(r'[A-Za-z0-9]');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text;
    final buffer = StringBuffer();
    // Keep only allowed characters and uppercase them
    final cleaned = raw.split('').where((c) => _allowed.hasMatch(c)).map((c) => c.toUpperCase()).join();
    if (cleaned.isEmpty) return TextEditingValue.empty;

    // Build with hyphens: 2-5-2
    int idx = 0;
    for (; idx < cleaned.length && idx < 2; idx++) {
      buffer.write(cleaned[idx]);
    }
    if (cleaned.length > 2) buffer.write('-');
    for (; idx < cleaned.length && idx < 7; idx++) {
      buffer.write(cleaned[idx]);
    }
    if (cleaned.length > 7) buffer.write('-');
    for (; idx < cleaned.length && idx < 9; idx++) {
      buffer.write(cleaned[idx]);
    }

    final formatted = buffer.toString();
    // Place caret at end of formatted
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}
