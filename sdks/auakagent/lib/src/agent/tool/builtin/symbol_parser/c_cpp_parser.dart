/// C/C++ 语言符号解析器。
///
/// 支持：#include, #define, #pragma, class (C++), struct, enum,
/// union, namespace, typedef, using, function, method, constructor,
/// variable, template。
library;

import 'symbol_parser.dart';

/// C/C++ 符号解析器
class CCppParser extends SymbolParser {
  CCppParser({required super.content, required super.lines});

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];
    final commentedLines = _findCommentedLineRanges();
    final classRanges = _collectTypeRanges(commentedLines);

    symbols.addAll(_parseIncludes(commentedLines));
    symbols.addAll(_parseDefines(commentedLines));
    symbols.addAll(_parseNamespaces(commentedLines));
    symbols.addAll(_parseTypedefs(commentedLines));
    symbols.addAll(_parseUsings(commentedLines));
    symbols.addAll(_parseStructs(commentedLines));
    symbols.addAll(_parseClasses(commentedLines));
    symbols.addAll(_parseEnums(commentedLines));
    symbols.addAll(_parseFunctionsAndMethods(classRanges, commentedLines));
    symbols.addAll(_parseVariables(commentedLines));

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
  }

  // ─── #include ─────────────────────────────────────────────────

  List<CodeSymbol> _parseIncludes(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.startsWith('#include')) {
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

  // ─── #define ──────────────────────────────────────────────────

  List<CodeSymbol> _parseDefines(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'#define\s+(\w+)(?:\s*\(|$)');
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
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
    return symbols;
  }

  // ─── Namespace ────────────────────────────────────────────────

  List<CodeSymbol> _parseNamespaces(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^namespace\s+(\w+)', multiLine: true);
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

  // ─── Typedef ──────────────────────────────────────────────────

  List<CodeSymbol> _parseTypedefs(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'typedef\s+.*?(\w+)\s*;', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      if (_isCppKeyword(name)) continue;
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

  // ─── Using (C++11) ────────────────────────────────────────────

  List<CodeSymbol> _parseUsings(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    // using Name = Type;
    final usingAliasRegex = RegExp(r'using\s+(\w+)\s*=', multiLine: true);
    for (final match in usingAliasRegex.allMatches(content)) {
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
    // using namespace std;
    final usingNsRegex = RegExp(r'using\s+namespace\s+(\w+)', multiLine: true);
    for (final match in usingNsRegex.allMatches(content)) {
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

  // ─── Struct ───────────────────────────────────────────────────

  List<CodeSymbol> _parseStructs(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:typedef\s+)?struct\s+(\w+)(?:\s*:\s*(?:public|private|protected)\s+[\w\s,<>]+)?',
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
          type: 'struct',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Class (C++) ──────────────────────────────────────────────

  List<CodeSymbol> _parseClasses(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^class\s+(\w+)(?:\s*:\s*(?:public|private|protected)\s+[\w\s,<>]+)?',
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

  // ─── Enum ─────────────────────────────────────────────────────

  List<CodeSymbol> _parseEnums(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    // C++11 enum class / C enum
    final regex = RegExp(
      r'^(?:typedef\s+)?(?:enum\s+(?:class|struct)\s+)?enum\s+(\w+)',
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

  // ─── Functions and Methods ────────────────────────────────────

  List<CodeSymbol> _parseFunctionsAndMethods(
    List<({String name, int start, int? end})> typeRanges,
    Set<int> commentedLines,
  ) {
    final symbols = <CodeSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 跳过预处理器指令
      if (trimmed.startsWith('#')) continue;

      // 跳过没有 ( 的行
      if (!trimmed.contains('(')) continue;

      final parentInfo = _findParent(typeRanges, i);

      // 构造函数: ClassName::ClassName(
      if (trimmed.contains('::')) {
        final ctorRegex = RegExp(r'(\w+)::(\w+)\s*\(');
        final ctorMatch = ctorRegex.firstMatch(trimmed);
        if (ctorMatch != null) {
          final className = ctorMatch.group(1)!;
          final ctorName = ctorMatch.group(2)!;
          if (className == ctorName) {
            symbols.add(
              CodeSymbol(
                name: ctorName,
                type: 'constructor',
                lineStart: i + 1,
                lineEnd: findBraceBlockEnd(i),
                signature: trimmed.length > 100
                    ? '${trimmed.substring(0, 100)}...'
                    : trimmed,
                parentName: className,
              ),
            );
            continue;
          }
          // 方法: ClassName::methodName(
          symbols.add(
            CodeSymbol(
              name: ctorName,
              type: 'method',
              lineStart: i + 1,
              lineEnd: findBraceBlockEnd(i),
              signature: trimmed.length > 100
                  ? '${trimmed.substring(0, 100)}...'
                  : trimmed,
              parentName: className,
            ),
          );
          continue;
        }
      }

      // 普通函数/方法匹配
      // [modifiers] ReturnType name(
      final funcRegex = RegExp(
        r'^(?:(?:virtual|static|inline|extern|explicit|constexpr|consteval|constinit|friend|template\s*<[^>]*>)\s+)*'
        r'[\w<>\[\]:*&,\s]+\s+' // return type (may include *, &, ::)
        r'(\w+)\s*\(', // function name
      );
      final match = funcRegex.firstMatch(trimmed);
      if (match != null) {
        final name = match.group(1)!;
        if (_isCppKeyword(name)) continue;

        final type = parentInfo != null ? 'method' : 'function';
        symbols.add(
          CodeSymbol(
            name: name,
            type: type,
            lineStart: i + 1,
            lineEnd: findBraceBlockEnd(i),
            signature: trimmed.length > 100
                ? '${trimmed.substring(0, 100)}...'
                : trimmed,
            parentName: parentInfo?.$1,
          ),
        );
      }
    }

    return symbols;
  }

  // ─── Variables ────────────────────────────────────────────────

  List<CodeSymbol> _parseVariables(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      if (line.contains('(')) continue;

      // const / constexpr / static 变量
      final constRegex = RegExp(
        r'^(?:const|constexpr|static|extern|volatile|mutable|register|thread_local)\s+'
        r'[\w<>\[\]:*&,\s]+\s+'
        r'(\w+)\s*[;=]',
      );
      final match = constRegex.firstMatch(line);
      if (match != null) {
        final name = match.group(1)!;
        if (_isCppKeyword(name)) continue;
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

    return symbols;
  }

  // ─── Helpers ──────────────────────────────────────────────────

  List<({String name, int start, int? end})> _collectTypeRanges(
    Set<int> commentedLines,
  ) {
    final ranges = <({String name, int start, int? end})>[];

    // Classes
    final classRegex = RegExp(r'^class\s+(\w+)', multiLine: true);
    for (final match in classRegex.allMatches(content)) {
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

    // Structs
    final structRegex = RegExp(r'^struct\s+(\w+)', multiLine: true);
    for (final match in structRegex.allMatches(content)) {
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

    // Namespaces
    final nsRegex = RegExp(r'^namespace\s+(\w+)', multiLine: true);
    for (final match in nsRegex.allMatches(content)) {
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

    return ranges;
  }

  (String, String)? _findParent(
    List<({String name, int start, int? end})> typeRanges,
    int lineIndex,
  ) {
    for (final range in typeRanges) {
      if (lineIndex > range.start &&
          (range.end == null || lineIndex <= range.end!)) {
        return (range.name, 'class');
      }
    }
    return null;
  }

  bool _isCppKeyword(String name) {
    const keywords = {
      'if',
      'else',
      'for',
      'while',
      'do',
      'switch',
      'case',
      'break',
      'continue',
      'return',
      'try',
      'catch',
      'throw',
      'new',
      'delete',
      'class',
      'struct',
      'enum',
      'union',
      'namespace',
      'typedef',
      'using',
      'template',
      'typename',
      'virtual',
      'override',
      'final',
      'const',
      'constexpr',
      'static',
      'extern',
      'inline',
      'explicit',
      'friend',
      'operator',
      'sizeof',
      'typeof',
      'decltype',
      'public',
      'private',
      'protected',
      'void',
      'bool',
      'char',
      'short',
      'int',
      'long',
      'float',
      'double',
      'unsigned',
      'signed',
      'auto',
      'register',
      'volatile',
      'mutable',
      'nullptr',
      'true',
      'false',
      'noexcept',
      'static_assert',
      'include',
      'define',
      'ifdef',
      'ifndef',
      'endif',
      'pragma',
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
