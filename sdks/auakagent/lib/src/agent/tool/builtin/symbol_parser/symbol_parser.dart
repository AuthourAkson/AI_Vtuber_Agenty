/// 代码符号数据模型和解析器抽象基类。
///
/// 定义 [CodeSymbol] 数据类和 [SymbolParser] 抽象接口，
/// 所有语言解析器均需继承 [SymbolParser] 并实现 [parse] 方法。
library;

/// 代码符号
///
/// 表示源代码中的一个符号定义（类、函数、变量、import 等）。
class CodeSymbol {
  /// 符号名称
  final String name;

  /// 符号类型
  ///
  /// 常见值：class, function, method, variable, import, enum, mixin,
  /// extension, typedef, getter, setter, constructor, interface, struct,
  /// trait, namespace, annotation, type, macro, decorator, impl
  final String type;

  /// 起始行号（1-based）
  final int lineStart;

  /// 结束行号（1-based），可为 null（如单行符号或无法确定）
  final int? lineEnd;

  /// 签名文本（声明行的原始文本）
  final String? signature;

  /// 访问修饰符（public, private, protected, internal, package 等）
  final String? accessModifier;

  /// 所属父级名称（如方法所属的类名）
  final String? parentName;

  CodeSymbol({
    required this.name,
    required this.type,
    required this.lineStart,
    this.lineEnd,
    this.signature,
    this.accessModifier,
    this.parentName,
  });

  @override
  String toString() =>
      'CodeSymbol(name: $name, type: $type, line: $lineStart-$lineEnd, '
      'parent: $parentName, access: $accessModifier)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeSymbol &&
          name == other.name &&
          type == other.type &&
          lineStart == other.lineStart &&
          lineEnd == other.lineEnd;

  @override
  int get hashCode => Object.hash(name, type, lineStart, lineEnd);
}

/// 符号解析器抽象基类
///
/// 所有语言解析器均需继承此类并实现 [parse] 方法。
/// 提供 [lines] 和 [content] 便捷访问，以及共享的工具方法。
abstract class SymbolParser {
  final String content;
  final List<String> lines;

  SymbolParser({required this.content, required this.lines});

  /// 解析源代码中的所有符号
  ///
  /// [symbolTypeFilter] 可选的符号类型过滤，仅返回匹配类型的符号。
  /// [namePattern] 可选的符号名称正则过滤。
  List<CodeSymbol> parse({String? symbolTypeFilter, String? namePattern});

  /// 获取行号（从字符偏移量计算，1-based）
  int getLineNumber(int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < content.length; i++) {
      if (content[i] == '\n') line++;
    }
    return line;
  }

  /// 获取行的缩进级别
  int getIndent(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= lines.length) return 0;
    final line = lines[lineIndex];
    return line.length - line.trimLeft().length;
  }

  /// 查找大括号块结束行（1-based），适用于 Dart/JS/TS/Java/C++/Go/Rust 等
  ///
  /// [startLineIndex] 起始行的 0-based 索引。
  /// 返回闭合大括号所在行的行号（1-based），如果未找到返回 null。
  int? findBraceBlockEnd(int startLineIndex) {
    var braceCount = 0;
    var foundOpen = false;
    var inString = false;
    var stringChar = '';
    var inLineComment = false;
    var inBlockComment = false;

    for (var i = startLineIndex; i < lines.length; i++) {
      final line = lines[i];
      inLineComment = false;

      for (var j = 0; j < line.length; j++) {
        final ch = line[j];
        final nextCh = j + 1 < line.length ? line[j + 1] : '';

        // 处理块注释
        if (inBlockComment) {
          if (ch == '*' && nextCh == '/') {
            inBlockComment = false;
            j++; // skip '/'
          }
          continue;
        }
        if (ch == '/' && nextCh == '*') {
          inBlockComment = true;
          j++; // skip '*'
          continue;
        }

        // 处理行注释
        if (ch == '/' && nextCh == '/') {
          inLineComment = true;
          break;
        }
        if (inLineComment) continue;

        // 处理字符串
        if (inString) {
          if (ch == '\\') {
            j++; // skip escaped char
          } else if (ch == stringChar) {
            inString = false;
          }
          continue;
        }
        if (ch == '"' || ch == "'") {
          inString = true;
          stringChar = ch;
          continue;
        }

        // 处理原始字符串 (Dart/Python r'', R"")
        if ((ch == 'r' || ch == 'R') && (nextCh == '"' || nextCh == "'")) {
          inString = true;
          stringChar = nextCh;
          j++; // skip quote
          continue;
        }

        // 计算大括号
        if (ch == '{') {
          braceCount++;
          foundOpen = true;
        } else if (ch == '}') {
          braceCount--;
        }
      }

      if (foundOpen && braceCount <= 0) {
        return i + 1; // 1-based
      }
    }

    return null;
  }

  /// 查找 Python 缩进块结束行（1-based）
  ///
  /// [startLineIndex] 起始行的 0-based 索引。
  /// 返回块结束后第一行的行号（1-based），如果到文件末尾返回总行数。
  int? findIndentBlockEnd(int startLineIndex) {
    if (startLineIndex >= lines.length) return null;

    final startIndent = getIndent(startLineIndex);

    for (var i = startLineIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final currentIndent = getIndent(i);
      if (currentIndent <= startIndent) {
        return i + 1; // 1-based
      }
    }

    return lines.length;
  }

  /// 查找圆括号闭合位置（在指定行开始搜索）
  ///
  /// 返回闭合括号所在行的 0-based 索引，如果未找到返回 -1。
  int findParenClose(int startLineIndex) {
    var parenCount = 0;
    var foundOpen = false;

    for (var i = startLineIndex; i < lines.length; i++) {
      for (final ch in lines[i].split('')) {
        if (ch == '(') {
          parenCount++;
          foundOpen = true;
        } else if (ch == ')') {
          parenCount--;
        }
      }
      if (foundOpen && parenCount <= 0) {
        return i;
      }
    }

    return -1;
  }

  /// 提取多行签名文本
  ///
  /// 从 [startLineIndex] 开始，提取到 [endLineIndex]（含）的文本，
  /// 用空格连接。
  String extractMultiLineSignature(int startLineIndex, int endLineIndex) {
    if (startLineIndex < 0 || startLineIndex >= lines.length) return '';
    final end = endLineIndex.clamp(0, lines.length - 1);
    return lines
        .sublist(startLineIndex, end + 1)
        .map((l) => l.trim())
        .join(' ');
  }

  /// 检查行是否在注释中（简单启发式）
  bool isLineCommented(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    final trimmed = lines[lineIndex].trim();
    return trimmed.startsWith('//') ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('*') ||
        trimmed.startsWith('/*');
  }

  /// 检查行是否被块注释包裹
  bool isInsideBlockComment(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    // 简单检查：向上查找未闭合的 /*
    var inBlock = false;
    for (var i = 0; i <= lineIndex; i++) {
      final line = lines[i];
      for (var j = 0; j < line.length; j++) {
        final ch = line[j];
        final nextCh = j + 1 < line.length ? line[j + 1] : '';
        if (inBlock) {
          if (ch == '*' && nextCh == '/') {
            inBlock = false;
            j++;
          }
        } else {
          if (ch == '/' && nextCh == '*') {
            inBlock = true;
            j++;
          } else if (ch == '/' && nextCh == '/') {
            break; // 行注释，跳过该行
          }
        }
      }
    }
    return inBlock;
  }
}
