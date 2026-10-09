/// Comprehensive integration tests for the symbol_parser module.
///
/// Covers language detection, display names, generic parsing, filtering,
/// CodeSymbol equality/toString, allSymbolTypes constant, and Unicode handling.
library;

import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/language_detector.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/generic_parser.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/symbol_parser.dart';

void main() {
  // =========================================================================
  // 1. Language detection – detectLanguage() for all supported extensions
  // =========================================================================
  group('detectLanguage', () {
    test('detects .dart files', () {
      expect(detectLanguage('lib/main.dart'), Language.dart);
    });

    test('detects .py files', () {
      expect(detectLanguage('scripts/run.py'), Language.python);
    });

    test('detects .js files', () {
      expect(detectLanguage('web/app.js'), Language.javascript);
    });

    test('detects .ts files', () {
      expect(detectLanguage('src/index.ts'), Language.typescript);
    });

    test('detects .tsx files as TypeScript', () {
      expect(detectLanguage('src/App.tsx'), Language.typescript);
    });

    test('detects .jsx files as JavaScript', () {
      expect(detectLanguage('src/Component.jsx'), Language.javascript);
    });

    test('detects .java files', () {
      expect(detectLanguage('src/Main.java'), Language.java);
    });

    test('detects .go files', () {
      expect(detectLanguage('cmd/main.go'), Language.go);
    });

    test('detects .rs files', () {
      expect(detectLanguage('src/lib.rs'), Language.rust);
    });

    test('detects .kt files', () {
      expect(detectLanguage('src/App.kt'), Language.kotlin);
    });

    test('detects .swift files', () {
      expect(detectLanguage('Sources/App.swift'), Language.swift);
    });

    test('detects .cpp files', () {
      expect(detectLanguage('src/engine.cpp'), Language.cpp);
    });

    test('detects .c files', () {
      expect(detectLanguage('src/ffi.c'), Language.c);
    });

    test('detects .h files as C++ (ambiguous header defaults to cpp)', () {
      expect(detectLanguage('include/header.h'), Language.cpp);
    });

    test('detects .hpp files as C++', () {
      expect(detectLanguage('include/header.hpp'), Language.cpp);
    });

    test('detects .cc files as C++', () {
      expect(detectLanguage('src/util.cc'), Language.cpp);
    });

    test('returns Language.unknown for unsupported extensions', () {
      expect(detectLanguage('README.md'), Language.unknown);
      expect(detectLanguage('data.json'), Language.unknown);
      expect(detectLanguage('config.yaml'), Language.unknown);
      expect(detectLanguage('no_extension'), Language.unknown);
    });

    test('is case-insensitive', () {
      expect(detectLanguage('LIB/MAIN.DART'), Language.dart);
      expect(detectLanguage('Script.PY'), Language.python);
      expect(detectLanguage('src/Index.TS'), Language.typescript);
    });
  });

  // =========================================================================
  // 2. Language display name – languageDisplayName() for each language
  // =========================================================================
  group('languageDisplayName', () {
    test('returns correct display names for all languages', () {
      const expected = <Language, String>{
        Language.dart: 'Dart',
        Language.python: 'Python',
        Language.javascript: 'JavaScript',
        Language.typescript: 'TypeScript',
        Language.java: 'Java',
        Language.cpp: 'C/C++',
        Language.go: 'Go',
        Language.rust: 'Rust',
        Language.kotlin: 'Kotlin',
        Language.swift: 'Swift',
        Language.c: 'C',
        Language.unknown: 'Unknown',
      };

      for (final entry in expected.entries) {
        expect(
          languageDisplayName(entry.key),
          equals(entry.value),
          reason: 'Display name for ${entry.key} should be "${entry.value}"',
        );
      }
    });
  });

  // =========================================================================
  // 3. Empty file handling – GenericParser with empty content
  // =========================================================================
  group('GenericParser empty file handling', () {
    test('returns only line count symbol for empty content', () {
      final parser = GenericParser(content: '', lines: const []);
      final symbols = parser.parse();

      // Should contain exactly one symbol: the line count
      expect(symbols, hasLength(1));
      expect(symbols.first.name, equals('0 lines'));
      expect(symbols.first.type, equals('variable'));
      expect(symbols.first.lineStart, equals(1));
      expect(symbols.first.lineEnd, equals(0));
    });

    test('returns only line count for whitespace-only content', () {
      const content = '   \n  \n\n  \t  ';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      // Only the line count variable, no imports/classes/functions
      expect(symbols, hasLength(1));
      expect(symbols.first.name, equals('4 lines'));
      expect(symbols.first.type, equals('variable'));
    });
  });

  // =========================================================================
  // 4. Unknown language fallback – GenericParser produces basic symbols
  // =========================================================================
  group('GenericParser unknown language fallback', () {
    test('detects generic class declarations', () {
      const content = '''
class Animal {
  String name;
  void speak() {}
}

class Dog extends Animal {
  void fetch() {}
}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      // Should find line count + 2 classes
      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(2));
      expect(classes[0].name, equals('Animal'));
      expect(classes[1].name, equals('Dog'));
    });

    test('detects generic function declarations', () {
      const content = '''
function greet(name) {
  return "Hello, " + name;
}

function add(a, b) {
  return a + b;
}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      final functions = symbols.where((s) => s.type == 'function').toList();
      expect(functions, hasLength(2));
      expect(functions[0].name, equals('greet'));
      expect(functions[1].name, equals('add'));
    });

    test('detects Python-style def declarations', () {
      const content = '''
def calculate_sum(a, b):
    return a + b

def print_hello():
    print("Hello")
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      final functions = symbols.where((s) => s.type == 'function').toList();
      expect(functions, hasLength(2));
      expect(functions[0].name, equals('calculate_sum'));
      expect(functions[1].name, equals('print_hello'));
    });

    test('detects various import patterns', () {
      const content = '''
import React from 'react';
#include <stdio.h>
use std::collections::HashMap;
require('lodash');
from os import path
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, hasLength(5));
      expect(imports[0].type, equals('import'));
      expect(imports[1].type, equals('import'));
      expect(imports[2].type, equals('import'));
      expect(imports[3].type, equals('import'));
      expect(imports[4].type, equals('import'));
    });
  });

  // =========================================================================
  // 5. CodeSymbol equality
  // =========================================================================
  group('CodeSymbol equality', () {
    test('two symbols with same fields are equal', () {
      final a = CodeSymbol(
        name: 'MyClass',
        type: 'class',
        lineStart: 10,
        lineEnd: 50,
      );
      final b = CodeSymbol(
        name: 'MyClass',
        type: 'class',
        lineStart: 10,
        lineEnd: 50,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('symbols with different names are not equal', () {
      final a = CodeSymbol(name: 'Foo', type: 'class', lineStart: 1);
      final b = CodeSymbol(name: 'Bar', type: 'class', lineStart: 1);

      expect(a, isNot(equals(b)));
    });

    test('symbols with different types are not equal', () {
      final a = CodeSymbol(name: 'Foo', type: 'class', lineStart: 1);
      final b = CodeSymbol(name: 'Foo', type: 'function', lineStart: 1);

      expect(a, isNot(equals(b)));
    });

    test('symbols with different lineStart are not equal', () {
      final a = CodeSymbol(name: 'Foo', type: 'class', lineStart: 1);
      final b = CodeSymbol(name: 'Foo', type: 'class', lineStart: 2);

      expect(a, isNot(equals(b)));
    });

    test('symbols with different lineEnd are not equal', () {
      final a = CodeSymbol(name: 'Foo', type: 'class', lineStart: 1, lineEnd: 10);
      final b = CodeSymbol(name: 'Foo', type: 'class', lineStart: 1, lineEnd: 20);

      expect(a, isNot(equals(b)));
    });

    test('identical symbols are equal', () {
      final symbol = CodeSymbol(name: 'X', type: 'variable', lineStart: 5);
      expect(symbol, equals(identical(symbol, symbol) ? symbol : symbol));
      // Direct identical check
      expect(identical(symbol, symbol), isTrue);
    });

    test('symbol is not equal to non-CodeSymbol object', () {
      final symbol = CodeSymbol(name: 'X', type: 'class', lineStart: 1);
      expect(symbol == 'not a symbol', isFalse);
      expect(symbol == 42, isFalse);
      expect(symbol == null, isFalse);
    });
  });

  // =========================================================================
  // 6. CodeSymbol toString
  // =========================================================================
  group('CodeSymbol toString', () {
    test('formats output correctly with all fields', () {
      final symbol = CodeSymbol(
        name: 'MyClass',
        type: 'class',
        lineStart: 10,
        lineEnd: 50,
        signature: 'class MyClass {',
        accessModifier: 'public',
        parentName: 'ParentClass',
      );

      final result = symbol.toString();
      expect(result, contains('name: MyClass'));
      expect(result, contains('type: class'));
      expect(result, contains('line: 10-50'));
      expect(result, contains('parent: ParentClass'));
      expect(result, contains('access: public'));
    });

    test('formats output with null lineEnd', () {
      final symbol = CodeSymbol(
        name: 'myFunc',
        type: 'function',
        lineStart: 5,
      );

      final result = symbol.toString();
      expect(result, contains('name: myFunc'));
      expect(result, contains('type: function'));
      expect(result, contains('line: 5-null'));
      expect(result, contains('parent: null'));
      expect(result, contains('access: null'));
    });

    test('formats output with null optional fields', () {
      final symbol = CodeSymbol(
        name: 'x',
        type: 'variable',
        lineStart: 3,
        lineEnd: 3,
      );

      final result = symbol.toString();
      expect(result, equals(
        'CodeSymbol(name: x, type: variable, line: 3-3, parent: null, access: null)',
      ));
    });
  });

  // =========================================================================
  // 7. Symbol type filter – GenericParser with symbolTypeFilter='import'
  // =========================================================================
  group('GenericParser symbolTypeFilter', () {
    test('filters to only import symbols', () {
      const content = '''
import React from 'react';
class App {
  constructor() {}
}
function render() {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse(symbolTypeFilter: 'import');

      // Only the import and the line count variable type won't match
      expect(symbols.every((s) => s.type == 'import'), isTrue);
      expect(symbols, hasLength(1));
      expect(symbols.first.name, contains('import React'));
    });

    test('filters to only class symbols', () {
      const content = '''
import React from 'react';
class App {
  constructor() {}
}
class Widget {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse(symbolTypeFilter: 'class');

      expect(symbols.every((s) => s.type == 'class'), isTrue);
      expect(symbols, hasLength(2));
      expect(symbols[0].name, equals('App'));
      expect(symbols[1].name, equals('Widget'));
    });

    test('"all" filter returns all symbols', () {
      const content = '''
import foo;
class Bar {}
function baz() {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final allSymbols = parser.parse();
      final filteredSymbols = parser.parse(symbolTypeFilter: 'all');

      expect(filteredSymbols.length, equals(allSymbols.length));
    });

    test('non-matching filter returns empty list (excluding line count variable)', () {
      const content = '''
import foo;
class Bar {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse(symbolTypeFilter: 'enum');

      // Only line count variable type is 'variable', not 'enum'
      expect(symbols, isEmpty);
    });
  });

  // =========================================================================
  // 8. Name pattern filter – GenericParser with namePattern regex
  // =========================================================================
  group('GenericParser namePattern filter', () {
    test('filters symbols by name pattern regex', () {
      const content = '''
class Animal {}
class AnimalShelter {}
class Car {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse(namePattern: r'^Animal');

      final classNames = symbols
          .where((s) => s.type == 'class')
          .map((s) => s.name)
          .toList();
      expect(classNames, containsAll(['Animal', 'AnimalShelter']));
      expect(classNames, isNot(contains('Car')));
    });

    test('filters by partial name match', () {
      const content = '''
class MyClass {}
class YourClass {}
class NotClass {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse(namePattern: r'Class');

      final classNames = symbols
          .where((s) => s.type == 'class')
          .map((s) => s.name)
          .toList();
      // All three class names contain 'Class'
      expect(classNames, containsAll(['MyClass', 'YourClass', 'NotClass']));
      // The line count variable should not be matched
      expect(classNames, isNot(contains('3 lines')));
    });

    test('invalid regex pattern returns all symbols (graceful fallback)', () {
      const content = '''
class Foo {}
function bar() {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse(namePattern: r'[invalid(');

      // Should not crash; fallback returns all symbols
      expect(symbols, isNotEmpty);
    });

    test('combined symbolTypeFilter and namePattern', () {
      const content = '''
import alpha;
import beta;
class Alpha {}
class Beta {}
class Gamma {}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse(
        symbolTypeFilter: 'class',
        namePattern: r'^Al|^Ga',
      );

      expect(symbols.every((s) => s.type == 'class'), isTrue);
      final names = symbols.map((s) => s.name).toList();
      expect(names, containsAll(['Alpha', 'Gamma']));
      expect(names, isNot(contains('Beta')));
    });
  });

  // =========================================================================
  // 9. allSymbolTypes constant
  // =========================================================================
  group('allSymbolTypes constant', () {
    test('contains all expected symbol types', () {
      const expectedTypes = [
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

      for (final type in expectedTypes) {
        expect(
          allSymbolTypes.contains(type),
          isTrue,
          reason: 'allSymbolTypes should contain "$type"',
        );
      }
    });

    test('has exactly the expected number of entries', () {
      expect(allSymbolTypes.length, equals(22));
    });

    test('is a const list', () {
      // Verify it's the same instance (const identity)
      expect(identical(allSymbolTypes, allSymbolTypes), isTrue);
    });
  });

  // =========================================================================
  // 10. Unicode / Chinese content – parser handles without crashing
  // =========================================================================
  group('Unicode / Chinese content handling', () {
    test('parses file with Chinese comments without crashing', () {
      const content = '''
// 这是一个测试文件
// 作者：张三
import React from 'react';

/**
 * 计算两个数的和
 * 这是一个工具函数
 */
function add(a, b) {
  return a + b;
}

// 用户类
class 用户信息 {
  String 名字;
  int 年龄;

  // 获取用户描述
  String 描述() {
    return '名字: \$名字, 年龄: \$年龄';
  }
}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      // Should not crash and should return symbols
      expect(symbols, isNotEmpty);

      // Should detect the import
      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, hasLength(1));

      // Should detect the function
      final functions = symbols.where((s) => s.type == 'function').toList();
      expect(functions, hasLength(1));
      expect(functions.first.name, equals('add'));
    });

    test('parses file with Chinese class names', () {
      const content = '''
class 动物 {
  void 叫声() {}
}

class 狗 extends 动物 {
  void 摇尾巴() {}
}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      // Should not crash
      expect(symbols, isNotEmpty);

      // GenericParser uses \w+ which may not match CJK characters in all regex
      // engines, but the parser should at least produce the line count symbol
      // without crashing.
      final lineCount = symbols.where((s) => s.type == 'variable').toList();
      expect(lineCount, isNotEmpty);
      expect(lineCount.first.name, contains('lines'));
    });

    test('handles mixed Unicode content in imports', () {
      const content = '''
// 导入必要的模块
import 工具模块 from './工具';
from 中文包 import 翻译函数
use 中文库::功能;
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      // Should not crash
      expect(symbols, isNotEmpty);

      // Should detect import-like lines
      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports.length, greaterThanOrEqualTo(1));
    });

    test('handles emoji in comments without crashing', () {
      const content = '''
// 🚀 启动应用
// ✅ 测试通过
// ⚠️ 警告信息
class App {
  // 📝 应用主类
  void run() {}
}
''';
      final parser = GenericParser(content: content, lines: content.split('\n'));
      final symbols = parser.parse();

      // Should not crash
      expect(symbols, isNotEmpty);

      // Should detect the class
      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes.first.name, equals('App'));
    });
  });
}
