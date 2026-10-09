/// Java 语言符号解析器。
///
/// 支持：import (含 static import), package, class, abstract class,
/// interface, enum, annotation (@interface), function (method),
/// constructor, variable (field), getter/setter (Java 风格)。
library;

import 'symbol_parser.dart';

/// Java 符号解析器
class JavaParser extends SymbolParser {
  JavaParser({required super.content, required super.lines});

  @override
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern}) {
    final symbols = <CodeSymbol>[];
    final commentedLines = _findCommentedLineRanges();
    final classRanges = _collectTypeRanges(commentedLines);

    symbols.addAll(_parsePackage(commentedLines));
    symbols.addAll(_parseImports(commentedLines));
    symbols.addAll(_parseAnnotations(commentedLines));
    symbols.addAll(_parseInterfaces(commentedLines));
    symbols.addAll(_parseEnums(commentedLines));
    symbols.addAll(_parseClasses(commentedLines));
    symbols.addAll(_parseMethodsAndConstructors(classRanges, commentedLines));
    symbols.addAll(_parseFields(commentedLines));

    return _applyFilters(symbols, symbolTypeFilter, namePattern);
  }

  // ─── Package ──────────────────────────────────────────────────

  List<CodeSymbol> _parsePackage(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^package\s+([\w.]+)', multiLine: true);
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
    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.startsWith('import ')) {
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

  // ─── Annotation (@interface) ──────────────────────────────────

  List<CodeSymbol> _parseAnnotations(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(r'^(?:public\s+)?@interface\s+(\w+)', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      symbols.add(
        CodeSymbol(
          name: '@$name',
          type: 'annotation',
          lineStart: line,
          lineEnd: endLine,
          signature: lines[line - 1].trim(),
        ),
      );
    }
    return symbols;
  }

  // ─── Interface ────────────────────────────────────────────────

  List<CodeSymbol> _parseInterfaces(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:public\s+)?(?:abstract\s+)?interface\s+(\w+)(?:<[^>]*>)?(?:\s+extends\s+[\w,\s<>]+)?',
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

  // ─── Enum ─────────────────────────────────────────────────────

  List<CodeSymbol> _parseEnums(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:public\s+)?(?:abstract\s+)?enum\s+(\w+)(?:\s+implements\s+[\w,\s<>]+)?',
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

  // ─── Class ────────────────────────────────────────────────────

  List<CodeSymbol> _parseClasses(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'^(?:public\s+)?(?:abstract\s+|final\s+)?class\s+(\w+)(?:<[^>]*>)?(?:\s+extends\s+[\w<>]+)?(?:\s+implements\s+[\w,\s<>]+)?',
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

  // ─── Methods and Constructors ─────────────────────────────────

  List<CodeSymbol> _parseMethodsAndConstructors(
    List<({String name, int start, int? end, String type})> typeRanges,
    Set<int> commentedLines,
  ) {
    final symbols = <CodeSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 跳过非方法行
      if (!trimmed.contains('(')) continue;

      final parentInfo = _findParent(typeRanges, i);

      // Constructor: ClassName(
      if (parentInfo != null) {
        final ctorRegex = RegExp(
          r'(?:public\s+|private\s+|protected\s+)?' +
              RegExp.escape(parentInfo.$1) +
              r'\s*\(',
        );
        if (ctorRegex.hasMatch(trimmed) && !trimmed.contains(' ')) {
          // 简单构造函数（没有返回类型）
          symbols.add(
            CodeSymbol(
              name: parentInfo.$1,
              type: 'constructor',
              lineStart: i + 1,
              lineEnd: findBraceBlockEnd(i),
              signature: trimmed.length > 100
                  ? '${trimmed.substring(0, 100)}...'
                  : trimmed,
              accessModifier: _extractAccessModifier(trimmed),
              parentName: parentInfo.$1,
            ),
          );
          continue;
        }
      }

      // Method: [modifiers] ReturnType name(
      final methodRegex = RegExp(
        r'(?:(?:public|private|protected|static|final|abstract|synchronized|native)\s+)*'
        r'(?:(?:<[^>]*>)\s+)?' // generic return type
        r'[\w<>\[\]?.,\s]+\s+' // return type
        r'(\w+)\s*\(', // method name
      );
      final match = methodRegex.firstMatch(trimmed);
      if (match != null) {
        final name = match.group(1)!;
        if (_isJavaKeyword(name)) continue;

        // 检查是否是 getter (getXxx / isXxx)
        var type = parentInfo != null ? 'method' : 'function';
        if (parentInfo != null) {
          if ((name.startsWith('get') &&
                  name.length > 3 &&
                  name[3].toUpperCase() == name[3]) ||
              (name.startsWith('is') &&
                  name.length > 2 &&
                  name[2].toUpperCase() == name[2])) {
            type = 'getter';
          } else if (name.startsWith('set') &&
              name.length > 3 &&
              name[3].toUpperCase() == name[3]) {
            type = 'setter';
          }
        }

        symbols.add(
          CodeSymbol(
            name: name,
            type: type,
            lineStart: i + 1,
            lineEnd: findBraceBlockEnd(i),
            signature: trimmed.length > 100
                ? '${trimmed.substring(0, 100)}...'
                : trimmed,
            accessModifier: _extractAccessModifier(trimmed),
            parentName: parentInfo?.$1,
          ),
        );
      }
    }

    return symbols;
  }

  // ─── Fields ───────────────────────────────────────────────────

  List<CodeSymbol> _parseFields(Set<int> commentedLines) {
    final symbols = <CodeSymbol>[];
    final regex = RegExp(
      r'(?:(?:public|private|protected|static|final|volatile|transient)\s+)*'
      r'[\w<>\[\]?.,\s]+\s+'
      r'(\w+)\s*[;=]',
    );

    for (var i = 0; i < lines.length; i++) {
      if (commentedLines.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.contains('(')) continue; // 方法行

      final match = regex.firstMatch(line);
      if (match != null) {
        final name = match.group(1)!;
        if (_isJavaKeyword(name)) continue;

        symbols.add(
          CodeSymbol(
            name: name,
            type: 'variable',
            lineStart: i + 1,
            lineEnd: i + 1,
            signature: line.length > 100
                ? '${line.substring(0, 100)}...'
                : line,
            accessModifier: _extractAccessModifier(line),
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

    // Classes
    final classRegex = RegExp(
      r'(?:public\s+)?(?:abstract\s+|final\s+)?class\s+(\w+)',
      multiLine: true,
    );
    for (final match in classRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
        type: 'class',
      ));
    }

    // Interfaces
    final ifaceRegex = RegExp(
      r'(?:public\s+)?interface\s+(\w+)',
      multiLine: true,
    );
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

    // Enums
    final enumRegex = RegExp(r'(?:public\s+)?enum\s+(\w+)', multiLine: true);
    for (final match in enumRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
        type: 'enum',
      ));
    }

    // Annotations
    final annRegex = RegExp(r'@interface\s+(\w+)', multiLine: true);
    for (final match in annRegex.allMatches(content)) {
      final name = match.group(1)!;
      final line = getLineNumber(match.start);
      if (commentedLines.contains(line - 1)) continue;
      final endLine = findBraceBlockEnd(line - 1);
      ranges.add((
        name: name,
        start: line - 1,
        end: endLine != null ? endLine - 1 : null,
        type: 'annotation',
      ));
    }

    return ranges;
  }

  (String, String)? _findParent(
    List<({String name, int start, int? end, String type})> typeRanges,
    int lineIndex,
  ) {
    for (final range in typeRanges) {
      if (lineIndex > range.start &&
          (range.end == null || lineIndex <= range.end!)) {
        return (range.name, range.type);
      }
    }
    return null;
  }

  String? _extractAccessModifier(String line) {
    if (line.contains('public ')) return 'public';
    if (line.contains('private ')) return 'private';
    if (line.contains('protected ')) return 'protected';
    return null;
  }

  bool _isJavaKeyword(String name) {
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
      'instanceof',
      'class',
      'interface',
      'enum',
      'extends',
      'implements',
      'import',
      'package',
      'super',
      'this',
      'void',
      'boolean',
      'byte',
      'char',
      'short',
      'int',
      'long',
      'float',
      'double',
      'null',
      'true',
      'false',
      'assert',
      'synchronized',
      'volatile',
      'transient',
      'native',
      'abstract',
      'final',
      'static',
      'default',
      'public',
      'private',
      'protected',
      'throws',
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
