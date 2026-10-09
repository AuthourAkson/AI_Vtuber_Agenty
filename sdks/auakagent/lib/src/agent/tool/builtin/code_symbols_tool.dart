import 'dart:io';

import '../agent_tool.dart';
import 'symbol_parser/symbol_parser.dart';
import 'symbol_parser/language_detector.dart';
import 'symbol_parser/dart_parser.dart';
import 'symbol_parser/python_parser.dart';
import 'symbol_parser/js_ts_parser.dart';
import 'symbol_parser/java_parser.dart';
import 'symbol_parser/c_cpp_parser.dart';
import 'symbol_parser/go_parser.dart';
import 'symbol_parser/rust_parser.dart';
import 'symbol_parser/generic_parser.dart';

/// 代码符号工具
///
/// 解析代码文件中的类、函数、变量、import 等符号定义。
/// 基于正则匹配，支持 Dart、Python、JavaScript、TypeScript、Java、
/// C/C++、Go、Rust 等主流语言。
class CodeSymbolsTool extends AgentTool {
  @override
  String get name => 'code_symbols';

  @override
  String get description =>
      '解析源代码文件中的代码符号（类、函数、方法、变量、import 等）。'
      '支持 Dart、Python、JavaScript、TypeScript、Java、C/C++、Go、Rust。\n\n'
      '返回符号名称、类型、行号范围和签名。\n\n'
      '用途：\n'
      '- 在编辑前了解文件结构\n'
      '- 查找特定函数或类定义\n'
      '- 不读取完整文件即可了解概览\n\n'
      '支持的语言：dart, python, javascript, typescript, java, c, c++, go, rust\n'
      '支持的符号类型：class, function, method, variable, import, enum, mixin, '
      'extension, typedef, getter, setter, constructor, interface, struct, trait, '
      'namespace, annotation, type, macro, decorator, impl';

  @override
  Map<String, dynamic> get inputJsonSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': '源代码文件的绝对路径。'},
      'symbol_type': {
        'type': 'string',
        'enum': allSymbolTypes,
        'description': '按符号类型过滤。默认："all"。',
      },
      'name_pattern': {
        'type': 'string',
        'description': '用于过滤符号名称的正则表达式，仅返回匹配的符号。',
      },
    },
    'required': ['path'],
  };

  @override
  bool get requiresPermission => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path'] as String?;
    if (path == null || path.isEmpty) {
      return ToolResult.error('path is required');
    }

    final symbolType = arguments['symbol_type'] as String? ?? 'all';
    final namePattern = arguments['name_pattern'] as String?;

    final file = File(path);
    if (!await file.exists()) {
      return ToolResult.error('File not found: $path');
    }

    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      return ToolResult.error('Failed to read file: $e');
    }

    if (content.isEmpty) {
      return ToolResult.success('File is empty: $path');
    }

    // 检测语言
    final language = detectLanguage(path);
    final lines = content.split('\n');

    // 创建对应的解析器
    final parser = _createParser(language, content, lines);
    final symbols = parser.parse(
      symbolTypeFilter: symbolType,
      namePattern: namePattern,
    );

    if (symbols.isEmpty) {
      return ToolResult.success('No symbols found matching filters in $path');
    }

    // 格式化输出
    final displayName = languageDisplayName(language);
    final buffer = StringBuffer(
      '## Symbols in ${path.split(Platform.pathSeparator).last}\n',
    );
    buffer.writeln('Language: $displayName | Total: ${symbols.length}\n');

    for (final s in symbols) {
      final parent = s.parentName != null ? ' [${s.parentName}]' : '';
      final access = s.accessModifier != null ? ' (${s.accessModifier})' : '';
      buffer.writeln(
        '  [${s.type}] ${s.name}$parent$access (line ${s.lineStart}-${s.lineEnd ?? "?"})',
      );
      if (s.signature != null && s.signature!.isNotEmpty) {
        buffer.writeln('    ${s.signature}');
      }
    }

    return ToolResult.success(buffer.toString().trim());
  }

  /// 根据语言创建对应的解析器
  SymbolParser _createParser(
    Language language,
    String content,
    List<String> lines,
  ) {
    switch (language) {
      case Language.dart:
        return DartParser(content: content, lines: lines);
      case Language.python:
        return PythonParser(content: content, lines: lines);
      case Language.javascript:
        return JsTsParser(content: content, lines: lines, isTypeScript: false);
      case Language.typescript:
        return JsTsParser(content: content, lines: lines, isTypeScript: true);
      case Language.java:
        return JavaParser(content: content, lines: lines);
      case Language.cpp:
      case Language.c:
        return CCppParser(content: content, lines: lines);
      case Language.go:
        return GoParser(content: content, lines: lines);
      case Language.rust:
        return RustParser(content: content, lines: lines);
      case Language.kotlin:
      case Language.swift:
      case Language.unknown:
        return GenericParser(content: content, lines: lines);
    }
  }
}
