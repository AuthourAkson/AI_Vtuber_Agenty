/// Go 语言符号解析器。
///
/// 支持：package, import, func (function/method), type (struct/interface),
/// var/const, type alias, iota enum pattern。
library;

import 'symbol_parser.dart';

/// Go 符号解析器
class GoParser extends SymbolParser {
  GoParser({required super.content, required super.lines});

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];
    final commentedLines = _findCommentedLineRanges();
    final typeRanges = _collectTypeRanges(commentedLines);

    symbols.addAll(_parsePackage(commentedLines));
    symbols.addAll(_parseImports(commentedLines));
    symbols.addAll(_parseTypes(commentedLines));
    symbols.addAll(_parseVarsAndConsts(commentedLines));
    symbols.addAll(_parseFunctionsAndMethods(typeRanges, commentedLines));

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
  }

  // ─── Package ──────────────────────────────────────────────────

  List<CodeSymbol> _parsePackage(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^package\s+(\w+)', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      symbols.add(
        CodeSymbol(
          name: match.group(1)!,
          type: 'import',
          lineStart: line,
          lineEnd: line,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Import ───────────────────────────────────────────────────

  List<CodeSymbol> _parseImports(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    var inImportBlock = false;

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();

      if (line == 'import (') {
        inImportBlock = true;
        continue;
      }
      if (inImportBlock && line == ')') {
        inImportBlock = false;
        continue;
      }
      if (inImportBlock && line.isNotEmpty) {
        symbols.add(
          CodeSymbol(
            name: line,
            type: 'import',
            lineStart: i + 1,
            lineEnd: i + 1,
            signature: line,
          ),
        );
      } else if (line.startsWith('import ') && !line.contains('(')) {
        symbols.add(
          CodeSymbol(
            name: line,
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

  // ─── Types (struct, interface, type alias) ────────────────────

  List<CodeSymbol> _parseTypes(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];

    // struct: type Name struct {
    final structRegex = RegExp(r'^type\s+(\w+)\s+struct\b', multiLine: true);
    for (final match in structRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'struct',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }

    // interface: type Name interface {
    final ifaceRegex = RegExp(r'^type\s+(\w+)\s+interface\b', multiLine: true);
    for (final match in ifaceRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'interface',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }

    // type alias: type Alias = OriginalType
    final aliasRegex = RegExp(r'^type\s+(\w+)\s*=', multiLine: true);
    for (final match in aliasRegex.allMatches(content)) {
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

    // iota enum pattern: type Name int/byte/string + const block with iota
    // This is detected by looking for type Name baseType followed by const block with iota
    final iotaTypeRegex = RegExp(
      r'^type\s+(\w+)\s+(int|byte|string|rune)\b',
      multiLine: true,
    );
    for (final match in iotaTypeRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;

      // Check if next non-empty line is a const block with iota
      var hasIota = false;
      for (var j = line; j < lines.length; j++) {
        final l = lines[j].trim();
        if (l.isEmpty) continue;
        if (l.startsWith('const (')) {
          // Check if any line in the block has iota
          for (var k = j + 1; k < lines.length; k++) {
            if (lines[k].trim() == ')') break;
            if (lines[k].contains('iota')) {
              hasIota = true;
              break;
            }
          }
        }
        break;
      }

      if (hasIota) {
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'enum',
            lineStart: line,
            lineEnd: line,
            signature: lines[line - 1].trim(),
          ),
        );
      }
    }

    return symbols;
  }

  // ─── Variables and Constants ──────────────────────────────────

  List<CodeSymbol> _parseVarsAndConsts(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    var inVarBlock = false;
    var inConstBlock = false;

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();

      if (line.startsWith('var (')) {
        inVarBlock = true;
        continue;
      }
      if (line.startsWith('const (')) {
        inConstBlock = true;
        continue;
      }
      if ((inVarBlock || inConstBlock) && line == ')') {
        inVarBlock = false;
        inConstBlock = false;
        continue;
      }

      if (inVarBlock || inConstBlock) {
        // Parse individual declarations in block
        // name Type = value or name = value
        final blockVarRegex = RegExp(r'^(\w+)\s*(?:[\w\[\]*]+\s*)?(?:=|$)');
        final match = blockVarRegex.firstMatch(line);
        if (match != null) {
          final name = match.group(1)!;
          if (!_isGoKeyword(name)) {
            symbols.add(
              CodeSymbol(
                name: name,
                type: 'variable',
                lineStart: i + 1,
                lineEnd: i + 1,
                signature: line,
              ),
            );
          }
        }
        continue;
      }

      // Single var declaration: var name Type = value
      final singleVarRegex = RegExp(r'^var\s+(\w+)');
      final singleMatch = singleVarRegex.firstMatch(line);
      if (singleMatch != null) {
        final name = singleMatch.group(1)!;
        if (!_isGoKeyword(name)) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'variable',
              lineStart: i + 1,
              lineEnd: i + 1,
              signature: line,
            ),
          );
        }
        continue;
      }

      // Single const declaration: const name = value
      final singleConstRegex = RegExp(r'^const\s+(\w+)');
      final singleConstMatch = singleConstRegex.firstMatch(line);
      if (singleConstMatch != null) {
        final name = singleConstMatch.group(1)!;
        if (!_isGoKeyword(name)) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'variable',
              lineStart: i + 1,
              lineEnd: i + 1,
              signature: line,
            ),
          );
        }
      }
    }
    return symbols;
  }

  // ─── Functions and Methods ────────────────────────────────────

  List<CodeSymbol> _parseFunctionsAndMethods(
    List<({String name, int start, int? end, String type})> typeRanges,
    Set<int> commentedLines,
  ) {
    final symbols = <CodeSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // func (receiver) Name( -> method
      final methodRegex = RegExp(r'^func\s+\([^)]+\)\s*(\w+)\s*\(');
      final methodMatch = methodRegex.firstMatch(line);
      if (methodMatch != null) {
        final name = methodMatch.group(1)!;
        if (_isGoKeyword(name)) continue;

        // Extract receiver type
        final receiverRegex = RegExp(r'^func\s+\(\w+\s+\*?(\w+)\)');
        final receiverMatch = receiverRegex.firstMatch(line);
        final parentName = receiverMatch?.group(1);

        symbols.add(
          CodeSymbol(
            name: name,
            type: 'method',
            lineStart: i + 1,
            lineEnd: findBraceBlockEnd(i),
            signature: line.length > 100
                ? '${line.substring(0, 100)}...'
                : line,
            parentName: parentName,
          ),
        );
        continue;
      }

      // func Name( -> function
      final funcRegex = RegExp(r'^func\s+(\w+)\s*\(');
      final funcMatch = funcRegex.firstMatch(line);
      if (funcMatch != null) {
        final name = funcMatch.group(1)!;
        if (_isGoKeyword(name)) continue;

        symbols.add(
          CodeSymbol(
            name: name,
            type: 'function',
            lineStart: i + 1,
            lineEnd: findBraceBlockEnd(i),
            signature: line.length > 100
                ? '${line.substring(0, 100)}...'
                : line,
          ),
        );
      }
    }

    return symbols;
  }

  // ─── Helpers ──────────────────────────────────────────────────

  List<({String name, int start, int? end, String type})> _collectTypeRanges(
    Set<int> commentedLines,
  ) {
    final ranges = <({String name, int start, int? end, String type})>[];

    final structRegex = RegExp(r'^type\s+(\w+)\s+struct\b', multiLine: true);
    for (final match in structRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
        type: 'struct',
      ));
    }

    final ifaceRegex = RegExp(r'^type\s+(\w+)\s+interface\b', multiLine: true);
    for (final match in ifaceRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
        type: 'interface',
      ));
    }

    return ranges;
  }

  bool _isGoKeyword(String name) {
    const keywords = {
      'break',
      'case',
      'chan',
      'const',
      'continue',
      'default',
      'defer',
      'else',
      'fallthrough',
      'for',
      'func',
      'go',
      'goto',
      'if',
      'import',
      'interface',
      'map',
      'package',
      'range',
      'return',
      'select',
      'struct',
      'switch',
      'type',
      'var',
      'true',
      'false',
      'nil',
      'iota',
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
