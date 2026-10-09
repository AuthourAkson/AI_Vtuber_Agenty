/// JavaScript / TypeScript 语言符号解析器。
///
/// 支持：import/require, class, function, arrow function, method,
/// variable, interface (TS), enum (TS), type alias (TS),
/// namespace (TS), decorator (TS), async/await。
library;

import 'symbol_parser.dart';

/// JavaScript/TypeScript 符号解析器
class JsTsParser extends SymbolParser {
  /// 是否为 TypeScript 文件
  final bool isTypeScript;

  JsTsParser({
    required super.content,
    required super.lines,
    this.isTypeScript = false,
  });

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];
    final commentedLines = _findCommentedLineRanges();

    symbols.addAll(_parseImports(commentedLines));

    if (isTypeScript) {
      symbols.addAll(_parseInterfaces(commentedLines));
      symbols.addAll(_parseTypeAliases(commentedLines));
      symbols.addAll(_parseTsEnums(commentedLines));
      symbols.addAll(_parseNamespaces(commentedLines));
    }

    symbols.addAll(_parseClasses(commentedLines));
    symbols.addAll(_parseFunctions(commentedLines));
    symbols.addAll(_parseArrowFunctions(commentedLines));
    symbols.addAll(_parseVariables(commentedLines));

    if (isTypeScript) {
      symbols.addAll(_parseDecorators(commentedLines));
    }

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
  }

  // ─── Import ───────────────────────────────────────────────────

  List<CodeSymbol> _parseImports(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('import ') ||
          line.startsWith('require(') ||
          line.startsWith('export ')) {
        // 区分 export 和 import
        if (line.startsWith('export ') && !line.startsWith('export default')) {
          // export function, export class, export const 等
          // 这些会在对应的解析器中处理
          continue;
        }
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

  // ─── Interface (TS) ───────────────────────────────────────────

  List<CodeSymbol> _parseInterfaces(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:export\s+)?interface\s+(\w+)(?:<[^>]*>)?(?:\s+extends\s+[\w,\s<>]+)?',
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
          type: 'interface',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Type Alias (TS) ──────────────────────────────────────────

  List<CodeSymbol> _parseTypeAliases(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^(?:export\s+)?type\s+(\w+)\s*=', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'type',
          lineStart: line,
          lineEnd: line,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Enum (TS) ────────────────────────────────────────────────

  List<CodeSymbol> _parseTsEnums(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:export\s+)?(?:const\s+)?enum\s+(\w+)',
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
        ),
      );
    }
    return symbols;
  }

  // ─── Namespace (TS) ───────────────────────────────────────────

  List<CodeSymbol> _parseNamespaces(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^(?:export\s+)?namespace\s+(\w+)', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'namespace',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Class ────────────────────────────────────────────────────

  List<CodeSymbol> _parseClasses(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+(\w+)(?:<[^>]*>)?(?:\s+extends\s+[\w<>]+)?(?:\s+implements\s+[\w,\s<>]+)?',
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
          type: 'class',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Function ─────────────────────────────────────────────────

  List<CodeSymbol> _parseFunctions(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*(?:\*)?\s+(\w+)\s*\(',
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
          type: 'function',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Arrow Functions ──────────────────────────────────────────

  List<CodeSymbol> _parseArrowFunctions(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[\w]+)\s*=>',
      multiLine: true,
    );
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'function',
          lineStart: line,
          lineEnd: line,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Variables ────────────────────────────────────────────────

  List<CodeSymbol> _parseVariables(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*:',
      multiLine: true,
    );
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;

      // 排除箭头函数
      final lineText = lines[line - 1].trim();
      if (lineText.contains('=>')) continue;

      symbols.add(
        CodeSymbol(
          name: name,
          type: 'variable',
          lineStart: line,
          lineEnd: line,
          signature: lineText.length > 100
              ? '${lineText.substring(0, 100)}...'
              : lineText,
        ),
      );
    }
    return symbols;
  }

  // ─── Decorators (TS) ──────────────────────────────────────────

  List<CodeSymbol> _parseDecorators(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^@(\w+)(?:\(|$)', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      symbols.add(
        CodeSymbol(
          name: '@$name',
          type: 'decorator',
          lineStart: line,
          lineEnd: line,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Helpers ──────────────────────────────────────────────────

  /// 查找被注释的行
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

  /// 应用过滤
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
