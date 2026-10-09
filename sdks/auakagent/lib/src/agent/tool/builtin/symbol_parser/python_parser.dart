/// Python 语言符号解析器。
///
/// 支持：import/from, class, function (def/async def), method,
/// variable, decorator, getter (@property), setter (@name.setter),
/// annotation (@dataclass 等)。
library;

import 'symbol_parser.dart';

/// Python 符号解析器
class PythonParser extends SymbolParser {
  PythonParser({required super.content, required super.lines});

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];
    final decorators = _collectDecorators();
    final classRanges = _collectClassRanges();

    symbols.addAll(_parseImports());
    symbols.addAll(_parseClasses(classRanges));
    symbols.addAll(_parseFunctionsAndMethods(classRanges, decorators));
    symbols.addAll(_parseVariables());

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
  }

  // ─── Import ───────────────────────────────────────────────────

  List<CodeSymbol> _parseImports() {
    final symbols = <CodeSymbol>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      // 跳过注释行
      if (line.startsWith('#')) continue;

      if (line.startsWith('import ') || line.startsWith('from ')) {
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

  // ─── Class ────────────────────────────────────────────────────

  List<CodeSymbol> _parseClasses(
    List<({String name, int start, int? end})> classRanges,
  ) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^class\s+(\w+)', multiLine: true);

    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (_isCommented(line - 1)) continue;

      final endLine = findIndentBlockEnd(line - 1);
      final decorator = _getDecoratorForLine(line - 1);

      symbols.add(
        CodeSymbol(
          name: name,
          type: 'class',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
          parentName: null,
        ),
      );

      // 如果有装饰器，也记录装饰器
      if (decorator != null) {
        symbols.add(
          CodeSymbol(
            name: decorator,
            type: 'decorator',
            lineStart: line - 1,
            lineEnd: line - 1,
            signature: decorator,
            parentName: name,
          ),
        );
      }
    }
    return symbols;
  }

  // ─── Functions and Methods ────────────────────────────────────

  List<CodeSymbol> _parseFunctionsAndMethods(
    List<({String name, int start, int? end})> classRanges,
    Map<int, String> decorators,
  ) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^\s*(async\s+)?def\s+(\w+)\s*\(', multiLine: true);

    for (final match in regex.allMatches(content)) {
      final name = match.group(2)!;
      final line = getLineNumber(match.start);
      if (_isCommented(line - 1)) continue;

      final endLine = findIndentBlockEnd(line - 1);
      final parentInfo = _findParent(classRanges, line - 1);
      final type = parentInfo != null ? 'method' : 'function';

      // 检查是否是 getter (@property)
      // decorators key 是 1-based 行号，line 也是 1-based
      final decorator = decorators[line];
      if (decorator != null) {
        if (decorator.contains('@property')) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'getter',
              lineStart: line,
              lineEnd: endLine,
              signature: lines[line - 1].trim(),
              parentName: parentInfo?.$1,
            ),
          );
          continue;
        }
        if (decorator.contains('.setter')) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'setter',
              lineStart: line,
              lineEnd: endLine,
              signature: lines[line - 1].trim(),
              parentName: parentInfo?.$1,
            ),
          );
          continue;
        }
        if (decorator.contains('@staticmethod') ||
            decorator.contains('@classmethod')) {
          symbols.add(
            CodeSymbol(
              name: name,
              type: 'method',
              lineStart: line,
              lineEnd: endLine,
              signature: lines[line - 1].trim(),
              parentName: parentInfo?.$1,
            ),
          );
          continue;
        }

        // 记录装饰器
        symbols.add(
          CodeSymbol(
            name: decorator,
            type: 'decorator',
            lineStart: line - 1,
            lineEnd: line - 1,
            signature: decorator,
            parentName: name,
          ),
        );
      }

      symbols.add(
        CodeSymbol(
          name: name,
          type: type,
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
          parentName: parentInfo?.$1,
        ),
      );
    }
    return symbols;
  }

  // ─── Variables ────────────────────────────────────────────────

  List<CodeSymbol> _parseVariables() {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^([A-Z_][A-Z_0-9]*)\s*=', multiLine: true);

    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (_isCommented(line - 1)) continue;
      final indent = getIndent(line - 1);
      if (indent == 0) {
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'variable',
            lineStart: line,
            lineEnd: line,
            signature: lines[line - 1].trim(),
          ),
        );
      }
    }
    return symbols;
  }

  // ─── Helpers ──────────────────────────────────────────────────

  /// 收集装饰器映射：行索引(1-based) -> 装饰器文本
  Map<int, String> _collectDecorators() {
    final decorators = <int, String>{};

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('@')) {
        if (_isCommented(i)) continue;
        // 装饰器作用于下一行（key = 下一行的 1-based 行号 = i + 2）
        final nextLine = i + 2; // 1-based line number of the decorated item
        decorators[nextLine] = trimmed;
      }
    }
    return decorators;
  }

  /// 收集所有 class 的范围
  List<({String name, int start, int? end})> _collectClassRanges() {
    final ranges = <({String name, int start, int? end})>[];
    final regex = RegExp(r'^class\s+(\w+)', multiLine: true);

    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      final endLine = findIndentBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
      ));
    }
    return ranges;
  }

  /// 查找给定行所属的父 class
  (String, String)? _findParent(
    List<({String name, int start, int? end})> classRanges,
    int lineIndex,
  ) {
    for (final range in classRanges) {
      if (lineIndex > range.start &&
          (range.end == null || lineIndex <= range.end!)) {
        return (range.name, 'class');
      }
    }
    return null;
  }

  /// 获取行上方最近的装饰器
  String? _getDecoratorForLine(int lineIndex) {
    if (lineIndex <= 0) return null;
    final prevLine = lines[lineIndex - 1].trim();
    if (prevLine.startsWith('@')) {
      return prevLine;
    }
    return null;
  }

  /// 检查行是否被注释
  bool _isCommented(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= lines.length) return true;
    final trimmed = lines[lineIndex].trim();
    return trimmed.startsWith('#');
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
