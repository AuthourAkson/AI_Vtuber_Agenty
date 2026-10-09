/// 通用 fallback 符号解析器。
///
/// 当没有专用解析器时使用，提供基本的符号识别能力。
library;

import 'symbol_parser.dart';

/// 通用符号解析器
///
/// 对未知语言提供基本的 import/class/function 识别。
class GenericParser extends SymbolParser {
  GenericParser({required super.content, required super.lines});

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];

    // 基本行数统计
    symbols.add(
      CodeSymbol(
        name: '${lines.length} lines',
        type: 'variable',
        lineStart: 1,
        lineEnd: lines.length,
      ),
    );

    // 尝试通用 import 匹配
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('import ') ||
          line.startsWith('#include ') ||
          line.startsWith('#import ') ||
          line.startsWith('use ') ||
          line.startsWith('require(') ||
          line.startsWith('from ')) {
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

    // 通用 class 匹配
    final classRegex = RegExp(r'\bclass\s+(\w+)');
    for (final match in classRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'class',
          lineStart: line,
          lineEnd: null,
          signature: lines[line - 1].trim(),
        ),
      );
    }

    // 通用 function 匹配
    final funcRegex = RegExp(r'\bfunction\s+(\w+)\s*\(');
    for (final match in funcRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'function',
          lineStart: line,
          lineEnd: null,
          signature: lines[line - 1].trim(),
        ),
      );
    }

    // 通用 def 匹配 (Python fallback)
    final defRegex = RegExp(r'\bdef\s+(\w+)\s*\(');
    for (final match in defRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'function',
          lineStart: line,
          lineEnd: null,
          signature: lines[line - 1].trim(),
        ),
      );
    }

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
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
