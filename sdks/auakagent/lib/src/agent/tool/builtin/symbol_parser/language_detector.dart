/// 语言检测工具。
///
/// 根据文件扩展名检测编程语言。
library;

/// 支持的语言类型
enum Language {
  dart('dart'),
  python('python'),
  javascript('javascript'),
  typescript('typescript'),
  java('java'),
  cpp('cpp'),
  go('go'),
  rust('rust'),
  kotlin('kotlin'),
  swift('swift'),
  c('c'),
  unknown('unknown');

  const Language(this.id);
  final String id;
}

/// 根据文件路径检测编程语言
Language detectLanguage(String path) {
  final lower = path.toLowerCase();

  // Dart
  if (lower.endsWith('.dart')) return Language.dart;

  // Python
  if (lower.endsWith('.py')) return Language.python;

  // TypeScript
  if (lower.endsWith('.ts') || lower.endsWith('.tsx')) {
    return Language.typescript;
  }

  // JavaScript
  if (lower.endsWith('.js') ||
      lower.endsWith('.jsx') ||
      lower.endsWith('.mjs')) {
    return Language.javascript;
  }

  // Java
  if (lower.endsWith('.java')) return Language.java;

  // Kotlin
  if (lower.endsWith('.kt') || lower.endsWith('.kts')) return Language.kotlin;

  // Swift
  if (lower.endsWith('.swift')) return Language.swift;

  // C++
  if (lower.endsWith('.cpp') ||
      lower.endsWith('.hpp') ||
      lower.endsWith('.cc') ||
      lower.endsWith('.cxx') ||
      lower.endsWith('.hxx')) {
    return Language.cpp;
  }

  // C (在 .h 之后检测，因为 .h 也可能是 C++)
  if (lower.endsWith('.c')) {
    return Language.c;
  }

  // Go
  if (lower.endsWith('.go')) return Language.go;

  // Rust
  if (lower.endsWith('.rs')) return Language.rust;

  // C/C++ header (ambiguous, default to cpp)
  if (lower.endsWith('.h')) return Language.cpp;

  return Language.unknown;
}

/// 获取语言的显示名称
String languageDisplayName(Language lang) {
  switch (lang) {
    case Language.dart:
      return 'Dart';
    case Language.python:
      return 'Python';
    case Language.javascript:
      return 'JavaScript';
    case Language.typescript:
      return 'TypeScript';
    case Language.java:
      return 'Java';
    case Language.cpp:
      return 'C/C++';
    case Language.go:
      return 'Go';
    case Language.rust:
      return 'Rust';
    case Language.kotlin:
      return 'Kotlin';
    case Language.swift:
      return 'Swift';
    case Language.c:
      return 'C';
    case Language.unknown:
      return 'Unknown';
  }
}

/// 所有支持的符号类型
const allSymbolTypes = [
  'class',
  'function',
  'method',
  'variable',
  'import',
  'enum',
  'mixin',
  'extension',
  'typedef',
  'getter',
  'setter',
  'constructor',
  'interface',
  'struct',
  'trait',
  'namespace',
  'annotation',
  'type',
  'macro',
  'decorator',
  'impl',
  'all',
];
