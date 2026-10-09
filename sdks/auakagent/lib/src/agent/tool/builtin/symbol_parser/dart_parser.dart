/// Dart 语言符号解析器。
///
/// 支持：import/export, library, part/part of, class, abstract class,
/// enum, mixin, extension, typedef, function, method, constructor,
/// getter, setter, variable, annotation。
library;

import 'symbol_parser.dart';

/// Dart 符号解析器
class DartParser extends SymbolParser {
  DartParser({required super.content, required super.lines});

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];

    // 跳过被注释的行
    final commentedLines = _findCommentedLineRanges();

    symbols.addAll(_parseImports(commentedLines));
    symbols.addAll(_parseLibrary(commentedLines));
    symbols.addAll(_parsePartDirectives(commentedLines));
    symbols.addAll(_parseClasses(commentedLines));
    symbols.addAll(_parseEnums(commentedLines));
    symbols.addAll(_parseMixins(commentedLines));
    symbols.addAll(_parseExtensions(commentedLines));
    symbols.addAll(_parseTypedefs(commentedLines));
    symbols.addAll(_parseFunctionsAndMethods(commentedLines));
    symbols.addAll(_parseVariables(commentedLines));

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
  }

  // ─── Import / Export ───────────────────────────────────────────

  List<CodeSymbol> _parseImports(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.startsWith('import ') || line.startsWith('export ')) {
        symbols.add(
          CodeSymbol(
            name: line.replaceAll(RegExp(r';.*$'), ''),
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

  // ─── Library ───────────────────────────────────────────────────

  List<CodeSymbol> _parseLibrary(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^library\s+(\S+)', multiLine: true);
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

  // ─── Part / Part of ───────────────────────────────────────────

  List<CodeSymbol> _parsePartDirectives(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.startsWith('part ') || line.startsWith('part of')) {
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

  // ─── Class ────────────────────────────────────────────────────

  List<CodeSymbol> _parseClasses(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:abstract\s+)?class\s+(\w+)(?:<[^>]*>)?(?:\s+extends\s+\w+(?:<[^>]*>)?)?(?:\s+with\s+[\w,\s<>]+)?(?:\s+implements\s+[\w,\s<>]+)?',
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
    final regex = RegExp(
      r'^enum\s+(\w+)(?:<[^>]*>)?(?:\s+with\s+[\w,\s<>]+)?',
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

  // ─── Mixin ────────────────────────────────────────────────────

  List<CodeSymbol> _parseMixins(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^mixin\s+(\w+)(?:<[^>]*>)?(?:\s+on\s+[\w,\s<>]+)?',
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
          type: 'mixin',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Extension ────────────────────────────────────────────────

  List<CodeSymbol> _parseExtensions(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^extension\s+(?:(\w+)\s+<[^>]*>\s+)?on\s+(\w+)(?:<[^>]*>)?',
      multiLine: true,
    );
    for (final match in regex.allMatches(content)) {
      // 可能是匿名 extension
      final name = match.group(1) ?? 'extension on ${match.group(2)}';
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: name,
          type: 'extension',
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
    final regex = RegExp(r'^typedef\s+(\w+)', multiLine: true);
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

  // ─── Functions, Methods, Getters, Setters, Constructors ──────

  List<CodeSymbol> _parseFunctionsAndMethods(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];

    // 收集所有 class/enum/mixin/extension 的范围，用于判断 method vs function
    final typeRanges = _collectTypeRanges();

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 跳过 import/export/library/part/class/enum/mixin/extension/typedef 行
      if (trimmed.startsWith('import ') ||
          trimmed.startsWith('export ') ||
          trimmed.startsWith('library ') ||
          trimmed.startsWith('part ') ||
          trimmed.startsWith(RegExp(r'(?:abstract\s+)?class\s')) ||
          trimmed.startsWith('enum ') ||
          trimmed.startsWith('mixin ') ||
          trimmed.startsWith('extension ') ||
          trimmed.startsWith('typedef ')) {
        continue;
      }

      final parentInfo = _findParent(typeRanges, i);

      // Getter
      final getterMatch = RegExp(
        r'^\s*(?:static\s+)?(?:external\s+)?[\w<>\[\]?]+\s+get\s+(\w+)',
      ).firstMatch(line);
      if (getterMatch != null) {
        final name = getterMatch.group(1)!;
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'getter',
            lineStart: i + 1,
            lineEnd: _findFunctionEnd(i),
            signature: trimmed.length > 100
                ? '${trimmed.substring(0, 100)}...'
                : trimmed,
            parentName: parentInfo?.$1,
          ),
        );
        continue;
      }

      // Setter
      final setterMatch = RegExp(
        r'^\s*(?:static\s+)?(?:external\s+)?set\s+(\w+)\s*\(',
      ).firstMatch(line);
      if (setterMatch != null) {
        final name = setterMatch.group(1)!;
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'setter',
            lineStart: i + 1,
            lineEnd: _findFunctionEnd(i),
            signature: trimmed.length > 100
                ? '${trimmed.substring(0, 100)}...'
                : trimmed,
            parentName: parentInfo?.$1,
          ),
        );
        continue;
      }

      // Constructor (ClassName() or ClassName.named())
      if (parentInfo != null) {
        final className = parentInfo.$1;
        final ctorRegex = RegExp(
          r'(?:factory\s+)?' +
              RegExp.escape(className) +
              r'\s*(?:\.\s*(\w+)\s*)?\(',
        );
        final ctorMatch = ctorRegex.firstMatch(line);
        if (ctorMatch != null) {
          final ctorName = ctorMatch.group(1) != null
              ? '$className.${ctorMatch.group(1)}'
              : className;
          symbols.add(
            CodeSymbol(
              name: ctorName,
              type: 'constructor',
              lineStart: i + 1,
              lineEnd: _findFunctionEnd(i),
              signature: trimmed.length > 100
                  ? '${trimmed.substring(0, 100)}...'
                  : trimmed,
              parentName: parentInfo.$1,
            ),
          );
          continue;
        }
      }

      // Function / Method
      // 匹配模式：[modifiers] ReturnType name(
      // 支持多行签名：如果 ( 不在同一行闭合，继续扫描
      final funcMatch = RegExp(
        r'^\s*(?:static\s+)?(?:external\s+)?(?:async\s+)?(?:[\w<>\[\]?]+\s+)+(\w+)\s*\(',
      ).firstMatch(line);
      if (funcMatch != null) {
        final name = funcMatch.group(1)!;

        // 排除关键字误匹配
        if (_isDartKeyword(name)) continue;

        final type = parentInfo != null ? 'method' : 'function';
        final endLine = _findFunctionEnd(i);

        // 提取多行签名
        final parenCloseLine = findParenClose(i);
        final sigEnd = parenCloseLine >= 0 ? parenCloseLine : i;
        final signature = extractMultiLineSignature(i, sigEnd);

        symbols.add(
          CodeSymbol(
            name: name,
            type: type,
            lineStart: i + 1,
            lineEnd: endLine,
            signature: signature.length > 100
                ? '${signature.substring(0, 100)}...'
                : signature,
            parentName: parentInfo?.$1,
          ),
        );
        continue;
      }

      // Operator overload (operator ==, operator +, etc.)
      final opMatch = RegExp(
        r'^\s*(?:static\s+)?[\w<>\[\]?]+\s+operator\s+([\+\-\*/\%\=\!\<\>\&\|\^\~]+|\[\]|\[\]=)',
      ).firstMatch(line);
      if (opMatch != null) {
        final name = 'operator ${opMatch.group(1)}';
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'method',
            lineStart: i + 1,
            lineEnd: _findFunctionEnd(i),
            signature: trimmed.length > 100
                ? '${trimmed.substring(0, 100)}...'
                : trimmed,
            parentName: parentInfo?.$1,
          ),
        );
        continue;
      }
    }

    return symbols;
  }

  // ─── Variables ────────────────────────────────────────────────

  List<CodeSymbol> _parseVariables(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 匹配变量声明（含赋值）
      // final Type name = ... / const Type name = ... / late final Type name = ...
      // Type name = ... / var name = ...
      final varMatch = RegExp(
        r'^\s*(?:final\s+|const\s+|late\s+)*(?:static\s+)?(?:covariant\s+)?(?:[\w<>\[\]?]+\s+)+(\w+)\s*=',
      ).firstMatch(line);
      if (varMatch != null) {
        final name = varMatch.group(1)!;
        if (_isDartKeyword(name)) continue;
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'variable',
            lineStart: i + 1,
            lineEnd: i + 1,
            signature: trimmed.length > 100
                ? '${trimmed.substring(0, 100)}...'
                : trimmed,
          ),
        );
        continue;
      }

      // 无赋值的字段声明：final Type name; / late final Type name;
      final fieldMatch = RegExp(
        r'^\s*(?:final\s+|const\s+|late\s+)*(?:static\s+)?(?:covariant\s+)?(?:[\w<>\[\]?]+\s+)+(\w+)\s*;',
      ).firstMatch(line);
      if (fieldMatch != null) {
        final name = fieldMatch.group(1)!;
        if (_isDartKeyword(name)) continue;
        symbols.add(
          CodeSymbol(
            name: name,
            type: 'variable',
            lineStart: i + 1,
            lineEnd: i + 1,
            signature: trimmed.length > 100
                ? '${trimmed.substring(0, 100)}...'
                : trimmed,
          ),
        );
      }
    }

    return symbols;
  }

  // ─── Helper Methods ───────────────────────────────────────────

  /// 查找函数/方法结束行（1-based）
  int? _findFunctionEnd(int lineIndex) {
    final line = lines[lineIndex].trim();

    // 箭头函数 => expression; 单行结束
    if (line.contains('=>') && !line.contains('{')) {
      return lineIndex + 1;
    }

    // 同步生成器 * 或 异步生成器 async*
    if (line.contains('=>')) {
      // 可能是 => expression; 也可能是 => { ... }
      if (!line.contains('{')) {
        return lineIndex + 1;
      }
    }

    // 有大括号体
    if (line.contains('{')) {
      return findBraceBlockEnd(lineIndex);
    }

    // 多行签名，查找括号闭合后的大括号
    final parenCloseLine = findParenClose(lineIndex);
    if (parenCloseLine >= 0) {
      // 检查括号闭合行是否有 =>
      final closeLine = lines[parenCloseLine].trim();
      if (closeLine.contains('=>') && !closeLine.contains('{')) {
        return parenCloseLine + 1;
      }
      // 查找大括号
      return findBraceBlockEnd(parenCloseLine);
    }

    return null;
  }

  /// 收集所有类型定义（class/enum/mixin/extension）的范围
  List<({String name, int start, int? end})> _collectTypeRanges() {
    final ranges = <({String name, int start, int? end})>[];

    // Classes
    final classRegex = RegExp(
      r'^(?:abstract\s+)?class\s+(\w+)',
      multiLine: true,
    );
    for (final match in classRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
      ));
    }

    // Enums
    final enumRegex = RegExp(r'^enum\s+(\w+)', multiLine: true);
    for (final match in enumRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
      ));
    }

    // Mixins
    final mixinRegex = RegExp(r'^mixin\s+(\w+)', multiLine: true);
    for (final match in mixinRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
      ));
    }

    // Extensions
    final extRegex = RegExp(r'^extension\s+(\w+)', multiLine: true);
    for (final match in extRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
      ));
    }

    return ranges;
  }

  /// 查找给定行所属的父类型
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

  /// 查找被注释的行索引集合
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

      // 如果块注释开始但未在同一行结束，标记后续行
      if (inBlockComment && !commented.contains(i)) {
        commented.add(i);
      }
    }

    return commented;
  }

  /// 检查是否是 Dart 关键字
  bool _isDartKeyword(String name) {
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
      'finally',
      'throw',
      'new',
      'is',
      'in',
      'as',
      'when',
      'assert',
      'class',
      'enum',
      'mixin',
      'extension',
      'typedef',
      'import',
      'export',
      'library',
      'part',
      'show',
      'hide',
      'on',
      'with',
      'implements',
      'extends',
      'get',
      'set',
      'operator',
      'factory',
      'static',
      'const',
      'final',
      'late',
      'var',
      'void',
      'dynamic',
      'covariant',
      'required',
      'super',
      'this',
      'abstract',
      'sealed',
      'base',
      'interface',
      'external',
      'sync',
      'async',
      'await',
      'yield',
    };
    return keywords.contains(name);
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
