/// Text rules of the VBO format: which characters count as white space, how
/// numbers are spelled and how bytes decode. Dart's own `trim`, `\s` and
/// `double.tryParse` use different rules, so they are not used on file text.
library;

import 'dart:convert';
import 'dart:typed_data';

/// ASCII white space: space, tab, line feed, vertical tab, form feed, carriage
/// return. Splits whitespace-separated rows and gate lines.
bool isAsciiSpace(int unit) => unit == 0x20 || (unit >= 0x09 && unit <= 0x0d);

/// Unicode white space as the reference implementation defines it: ASCII
/// white space, U+0085, and the space, line and paragraph separators.
/// Trims lines and comma-separated fields.
bool isUnicodeSpace(int unit) {
  if (unit <= 0x7f) return isAsciiSpace(unit);
  return unit == 0x85 ||
      unit == 0xa0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200a) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202f ||
      unit == 0x205f ||
      unit == 0x3000;
}

/// [text] without leading and trailing [isUnicodeSpace] characters.
String trimSpace(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && isUnicodeSpace(text.codeUnitAt(start))) {
    ++start;
  }
  while (end > start && isUnicodeSpace(text.codeUnitAt(end - 1))) {
    --end;
  }
  return start == 0 && end == text.length ? text : text.substring(start, end);
}

final RegExp _decimal = RegExp(r'^[+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$');

/// Parses a plain decimal number: optional sign, ASCII digits with an optional
/// point, optional exponent. Leading and trailing white space is allowed.
/// Returns null for any other spelling, including hexadecimal, `inf`, `nan`
/// and digit-group separators. The result may be infinite on overflow.
double? parseDecimal(String text) {
  final trimmed = trimSpace(text);
  if (!_decimal.hasMatch(trimmed)) return null;
  return double.parse(trimmed);
}

/// Lower-case comparison used where the format is case-insensitive.
bool equalsIgnoreCase(String a, String b) =>
    a.length == b.length && a.toLowerCase() == b.toLowerCase();

bool startsWithIgnoreCase(String text, String prefix) =>
    text.length >= prefix.length &&
    text.substring(0, prefix.length).toLowerCase() == prefix.toLowerCase();

/// Decodes UTF-8. A leading byte-order mark is dropped. Each malformed
/// sequence becomes U+FFFD: one per byte of an incomplete multi-byte prefix,
/// one per stray byte. This matches FlappedEar Overlays, so a damaged file
/// yields the same column names in both apps.
String decodeUtf8(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _decodeUtf8Replacing(bytes);
  }
}

String _decodeUtf8Replacing(Uint8List bytes) {
  final out = StringBuffer();
  var index = 0;
  if (bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
    index = 3;
  }
  const replacement = 0xfffd;
  while (index < bytes.length) {
    final lead = bytes[index];
    if (lead < 0x80) {
      out.writeCharCode(lead);
      ++index;
      continue;
    }
    int length;
    int codePoint;
    int low = 0x80;
    int high = 0xbf;
    if (lead >= 0xc2 && lead <= 0xdf) {
      length = 2;
      codePoint = lead & 0x1f;
    } else if (lead >= 0xe0 && lead <= 0xef) {
      length = 3;
      codePoint = lead & 0x0f;
      if (lead == 0xe0) low = 0xa0;
      if (lead == 0xed) high = 0x9f;
    } else if (lead >= 0xf0 && lead <= 0xf4) {
      length = 4;
      codePoint = lead & 0x07;
      if (lead == 0xf0) low = 0x90;
      if (lead == 0xf4) high = 0x8f;
    } else {
      out.writeCharCode(replacement);
      ++index;
      continue;
    }
    var consumed = 1;
    while (consumed < length) {
      final position = index + consumed;
      if (position >= bytes.length) break;
      final next = bytes[position];
      final lower = consumed == 1 ? low : 0x80;
      final upper = consumed == 1 ? high : 0xbf;
      if (next < lower || next > upper) break;
      codePoint = (codePoint << 6) | (next & 0x3f);
      ++consumed;
    }
    if (consumed == length) {
      out.writeCharCode(codePoint);
    } else {
      for (var i = 0; i < consumed; ++i) {
        out.writeCharCode(replacement);
      }
    }
    index += consumed;
  }
  return out.toString();
}
