/// Rust 语言符号解析器。
///
/// 支持：use/mod, fn (function), struct, enum, trait, impl, method,
/// variable (let/const/static), type alias, macro (macro_rules!)。
library;

import 'symbol_parser.dart';

/// Rust 符号解析器
class RustParser extends SymbolParser {
  RustParser({required super.content, required super.lines});

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];
    final commentedLines = _findCommentedLineRanges();
    final implRanges = _collectImplRanges(commentedLines);

    symbols.addAll(_parseUses(commentedLines));
    symbols.addAll(_parseMods(commentedLines));
    symbols.addAll(_parseTraits(commentedLines));
    symbols.addAll(_parseStructs(commentedLines));
    symbols.addAll(_parseEnums(commentedLines));
    symbols.addAll(_parseImpls(commentedLines));
    symbols.addAll(_parseFunctionsAndMethods(implRanges, commentedLines));
    symbols.addAll(_parseTypeAliases(commentedLines));
    symbols.addAll(_parseMacros(commentedLines));
    symbols.addAll(_parseVariables(commentedLines));

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
  }

  // ─── use ──────────────────────────────────────────────────────

  List<CodeSymbol> _parseUses(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.startsWith('use ')) {
        symbols.add(
          CodeSymbol(
            name: line.length > 80 ? '${line.substring(0, 80)}...' : line,
            type: 'import',
            lineStart: i + 1,
            lineEnd: i + 1,
            signature: line,
          ),
        );
      }
    }
    return symbols;
  }

  // ─── mod ──────────────────────────────────────────────────────

  List<CodeSymbol> _parseMods(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^mod\s+(\w+)', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'import',
          lineStart: line,
          lineEnd: line,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Trait ────────────────────────────────────────────────────

  List<CodeSymbol> _parseTraits(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:pub\s+)?(?:unsafe\s+)?trait\s+(\w+)(?:<[^>]*>)?',
      multiLine: true,
    );
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'trait',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
          accessModifier: lines[line - 1].trim().startsWith('pub')
              ? 'public'
              : null,
        ),
      );
    }
    return symbols;
  }

  // ─── Struct ───────────────────────────────────────────────────

  List<CodeSymbol> _parseStructs(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    // Named struct: struct Name { ... }
    final structRegex = RegExp(
      r'^(?:pub\s+)?struct\s+(\w+)(?:<[^>]*>)?',
      multiLine: true,
    );
    for (final match in structRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;

      // Check if it's a unit struct (no braces on same line)
      final lineText = lines[line - 1].trim();
      if (lineText.endsWith(';')) {
        // Unit struct: struct Name;
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'struct',
            lineStart: line,
            lineEnd: line,
            signature: lineText,
            accessModifier: lineText.startsWith('pub') ? 'public' : null,
          ),
        );
      } else {
        final endLine = findBraceBlockEnd(line - 1);
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'struct',
            lineStart: line,
            lineEnd: endLine,
            signature: lineText,
            accessModifier: lineText.startsWith('pub') ? 'public' : null,
          ),
        );
      }
    }
    return symbols;
  }

  // ─── Enum ─────────────────────────────────────────────────────

  List<CodeSymbol> _parseEnums(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:pub\s+)?enum\s+(\w+)(?:<[^>]*>)?',
      multiLine: true,
    );
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'enum',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
          accessModifier: lines[line - 1].trim().startsWith('pub')
              ? 'public'
              : null,
        ),
      );
    }
    return symbols;
  }

  // ─── Impl ─────────────────────────────────────────────────────

  List<CodeSymbol> _parseImpls(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];

    // impl for trait: impl Trait for Type
    final implForRegex = RegExp(
      r'^(?:pub\s+)?impl(?:<[^>]*>)?\s+(\w+)(?:<[^>]*>)?\s+for\s+(\w+)',
      multiLine: true,
    );
    for (final match in implForRegex.allMatches(content)) {
      final traitName = match.group(1)!;
      final typeName = match.group(2)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: '$traitName for $typeName',
          type: 'impl',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }

    // impl Type (inherent impl)
    final implRegex = RegExp(
      r'^(?:pub\s+)?impl(?:<[^>]*>)?\s+(\w+)(?:<[^>]*>)?\s*\{',
      multiLine: true,
    );
    for (final match in implRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;

      // Skip if already matched as impl for
      final lineText = lines[line - 1].trim();
      if (lineText.contains(' for ')) continue;

      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'impl',
          lineStart: line,
          lineEnd: endLine,
          signature: lineText,
        ),
      );
    }

    return symbols;
  }

  // ─── Functions and Methods ────────────────────────────────────

  List<CodeSymbol> _parseFunctionsAndMethods(
    List<({String name, int start, int? end})> implRanges,
    Set<int> commentedLines,
  ) {
    final symbols = <CodeSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // fn name(
      final funcRegex = RegExp(
        r'^(?:pub\s+)?(?:async\s+)?(?:unsafe\s+)?(?:extern\s+"[^"]*"\s+)?fn\s+(\w+)\s*[<(:]',
      );
      final match = funcRegex.firstMatch(line);
      if (match != null) {
        final name = match.group(1)!;
        if (_isRustKeyword(name)) continue;

        final parentInfo = _findParent(implRanges, i);
        final type = parentInfo != null ? 'method' : 'function';
        final endLine = findBraceBlockEnd(i);

        symbols.add(
          CodeSymbol(
            name: name,
            type: type,
            lineStart: i + 1,
            lineEnd: endLine,
            signature: line.length > 100
                ? '${line.substring(0, 100)}...'
                : line,
            accessModifier: line.startsWith('pub') ? 'public' : null,
            parentName: parentInfo,
          ),
        );
      }
    }

    return symbols;
  }

  // ─── Type Aliases ─────────────────────────────────────────────

  List<CodeSymbol> _parseTypeAliases(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^(?:pub\s+)?type\s+(\w+)\s*=', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'typedef',
          lineStart: line,
          lineEnd: line,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Macros ───────────────────────────────────────────────────

  List<CodeSymbol> _parseMacros(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^macro_rules!\s+(\w+)', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      symbols.add(
        CodeSymbol(
          name: '$name!',
          type: 'macro',
          lineStart: line,
          lineEnd: findBraceBlockEnd(line - 1),
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Variables (let/const/static) ─────────────────────────────

  List<CodeSymbol> _parseVariables(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // static: static NAME: Type = value;
      final staticRegex = RegExp(r'^(?:pub\s+)?static\s+(\w+)\s*:');
      final staticMatch = staticRegex.firstMatch(line);
      if (staticMatch != null) {
        final name = staticMatch.group(1)!;
        if (!_isRustKeyword(name)) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'variable',
              lineStart: i + 1,
              lineEnd: i + 1,
              signature: line.length > 100
                  ? '${line.substring(0, 100)}...'
                  : line,
            ),
          );
        }
        continue;
      }

      // const: const NAME: Type = value;
      final constRegex = RegExp(r'^(?:pub\s+)?const\s+(\w+)\s*:');
      final constMatch = constRegex.firstMatch(line);
      if (constMatch != null) {
        final name = constMatch.group(1)!;
        if (!_isRustKeyword(name)) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'variable',
              lineStart: i + 1,
              lineEnd: i + 1,
              signature: line.length > 100
                  ? '${line.substring(0, 100)}...'
                  : line,
            ),
          );
        }
        continue;
      }

      // let: let name: Type = value; or let mut name = value;
      final letRegex = RegExp(r'^let\s+(?:mut\s+)?(\w+)\s*[:=]');
      final letMatch = letRegex.firstMatch(line);
      if (letMatch != null) {
        final name = letMatch.group(1)!;
        if (!_isRustKeyword(name)) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'variable',
              lineStart: i + 1,
              lineEnd: i + 1,
              signature: line.length > 100
                  ? '${line.substring(0, 100)}...'
                  : line,
            ),
          );
        }
      }
    }

    return symbols;
  }

  // ─── Helpers ──────────────────────────────────────────────────

  List<({String name, int start, int? end})> _collectImplRanges(
    Set<int> commentedLines,
  ) {
    final ranges = <({String name, int start, int? end})>[];

    // impl for trait
    final implForRegex = RegExp(
      r'impl(?:<[^>]*>)?\s+\w+(?:<[^>]*>)?\s+for\s+(\w+)',
      multiLine: true,
    );
    for (final match in implForRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
      ));
    }

    // inherent impl
    final implRegex = RegExp(
      r'impl(?:<[^>]*>)?\s+(\w+)(?:<[^>]*>)?\s*\{',
      multiLine: true,
    );
    for (final match in implRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final lineText = lines[line - 1].trim();
      if (lineText.contains(' for ')) continue;
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
      ));
    }

    return ranges;
  }

  String? _findParent(
    List<({String name, int start, int? end})> implRanges,
    int lineIndex,
  ) {
    for (final range in implRanges) {
      if (lineIndex > range.start &&
          (range.end == null || lineIndex <= range.end!)) {
        return range.name;
      }
    }
    return null;
  }

  bool _isRustKeyword(String name) {
    const keywords = {
      'as',
      'break',
      'const',
      'continue',
      'crate',
      'else',
      'enum',
      'extern',
      'false',
      'fn',
      'for',
      'if',
      'impl',
      'in',
      'let',
      'loop',
      'match',
      'mod',
      'move',
      'mut',
      'pub',
      'ref',
      'return',
      'self',
      'Self',
      'static',
      'struct',
      'super',
      'trait',
      'true',
      'type',
      'unsafe',
      'use',
      'where',
      'while',
      'async',
      'await',
      'dyn',
      'abstract',
      'become',
      'box',
      'do',
      'final',
      'macro',
      'override',
      'priv',
      'try',
      'typeof',
      'unsized',
      'virtual',
      'yield',
    };
    return keywords.contains(name);
  }

  Set<int> _findCommentedLineRanges() {
    final commented = <int>{};
    var inBlockComment = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var j = 0;

      while (j < line.length) {
        if (inBlockComment) {
          if (j + 1 < line.length && line[j] == '*' && line[j + 1] == '/') {
            inBlockComment = false;
            j += 2;
            continue;
          }
          j++;
        } else {
          if (j + 1 < line.length && line[j] == '/' && line[j + 1] == '*') {
            inBlockComment = true;
            commented.add(i);
            j += 2;
            continue;
          }
          if (j + 1 < line.length && line[j] == '/' && line[j + 1] == '/') {
            commented.add(i);
            break;
          }
          j++;
        }
      }

      if (inBlockComment && !commented.contains(i)) {
        commented.add(i);
      }
    }

    return commented;
  }

  List<CodeSymbol> _applyFilters(
    List<CodeSymbol> symbols,
    String? symbolTypeFilter,
    String? namePattern,
  ) {
    return symbols.where((s) {
      if (symbolTypeFilter != null &&
          symbolTypeFilter != 'all' &&
          s.type != symbolTypeFilter) {
        return false;
      }
      if (namePattern != null && namePattern.isNotEmpty) {
        try {
          return RegExp(namePattern).hasMatch(s.name);
        } catch (_) {
          return true;
        }
      }
      return true;
    }).toList();
  }
}
