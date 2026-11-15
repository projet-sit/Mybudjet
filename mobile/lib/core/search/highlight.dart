import 'package:flutter/painting.dart';

/// Surlignage des occurrences d'une recherche dans un texte affiché.
///
/// La correspondance est insensible à la casse et aux accents :
/// chaque lettre de la requête devient une classe de caractères.

const Map<String, String> _accentClasses = {
  'a': '[aàâäáã]',
  'e': '[eéèêë]',
  'i': '[iîïí]',
  'o': '[oôöóõ]',
  'u': '[uùûüú]',
  'c': '[cç]',
  'n': '[nñ]',
  'y': '[yÿ]',
};

/// Construit un motif flexible (accents/casse) à partir d'une requête libre.
String flexiblePattern(String query) {
  final sb = StringBuffer();
  for (final ch in query.trim().toLowerCase().runes) {
    final c = String.fromCharCode(ch);
    if (RegExp(r'[a-z]').hasMatch(c)) {
      sb.write(_accentClasses[c] ?? RegExp.escape(c));
    } else if (c == ' ') {
      sb.write(r'\s+');
    } else {
      sb.write(RegExp.escape(c));
    }
  }
  return sb.toString();
}

/// Découpe [text] en segments simples / surlignés selon [query].
List<TextSpan> highlightMatches(
  String text,
  String query, {
  required TextStyle highlightStyle,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty || text.isEmpty) {
    return [TextSpan(text: text)];
  }
  final pattern = flexiblePattern(trimmed);
  if (pattern.isEmpty) return [TextSpan(text: text)];
  final re = RegExp('($pattern)', caseSensitive: false);
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    spans.add(TextSpan(text: text.substring(m.start, m.end), style: highlightStyle));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last)));
  }
  return spans;
}
