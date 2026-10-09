import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/js_ts_parser.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/symbol_parser.dart';

/// JavaScript / TypeScript 符号解析器测试
///
/// 覆盖场景：
/// 1. JS import 解析（默认导入、命名导入）
/// 2. JS class 解析（普通类、导出类）
/// 3. JS function 解析（普通函数、导出函数、异步函数）
/// 4. JS 箭头函数解析（普通箭头函数、异步箭头函数）
/// 5. JS 变量解析（带类型注解的 const/let）
/// 6. TS interface 解析（仅 isTypeScript=true）
/// 7. TS type alias 解析（仅 isTypeScript=true）
/// 8. TS enum 解析（仅 isTypeScript=true）
/// 9. TS namespace 解析（仅 isTypeScript=true）
/// 10. TS decorator 解析（仅 isTypeScript=true）
/// 11. symbolTypeFilter 过滤
/// 12. namePattern 正则过滤

void main() {
  // ─── 1. JS import 解析 ───────────────────────────────────────

  group('JS import parsing', () {
    test('parses default import', () {
      const source = "import React from 'react';\n";
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, equals("import React from 'react';"));
      expect(symbols[0].lineStart, equals(1));
      expect(symbols[0].lineEnd, equals(1));
    });

    test('parses named import', () {
      const source = "import { useState, useEffect } from 'react';\n";
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, contains('useState'));
      expect(symbols[0].name, contains('useEffect'));
    });

    test('parses multiple imports', () {
      const source =
          "import A from 'a';\n"
          "import { B } from 'b';\n"
          "import * as C from 'c';\n";
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      expect(symbols, hasLength(3));
      for (final s in symbols) {
        expect(s.type, equals('import'));
      }
      expect(symbols[0].lineStart, equals(1));
      expect(symbols[1].lineStart, equals(2));
      expect(symbols[2].lineStart, equals(3));
    });
  });

  // ─── 2. JS class 解析 ────────────────────────────────────────

  group('JS class parsing', () {
    test('parses a plain class', () {
      const source =
          'class Foo {\n'
          '  constructor() {}\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes[0].name, equals('Foo'));
      expect(classes[0].lineStart, equals(1));
      expect(classes[0].lineEnd, equals(3));
    });

    test('parses an exported class', () {
      const source =
          'export class Bar {\n'
          '  method() {}\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes[0].name, equals('Bar'));
      expect(classes[0].signature, contains('export class Bar'));
    });

    test('parses abstract and generic class', () {
      const source =
          'abstract class Base<T> {\n'
          '  abstract run(): T;\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes[0].name, equals('Base'));
      expect(classes[0].lineStart, equals(1));
      expect(classes[0].lineEnd, equals(3));
    });
  });

  // ─── 3. JS function 解析 ─────────────────────────────────────

  group('JS function parsing', () {
    test('parses a plain function', () {
      const source =
          'function greet(name) {\n'
          '  return "Hello " + name;\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('greet'));
      expect(funcs[0].lineStart, equals(1));
      expect(funcs[0].lineEnd, equals(3));
    });

    test('parses an exported function', () {
      const source =
          'export function add(a, b) {\n'
          '  return a + b;\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('add'));
      expect(funcs[0].signature, contains('export function add'));
    });

    test('parses an async function', () {
      const source =
          'async function fetchData() {\n'
          '  const res = await fetch("/api");\n'
          '  return res.json();\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('fetchData'));
      expect(funcs[0].signature, contains('async'));
    });
  });

  // ─── 4. JS 箭头函数解析 ─────────────────────────────────────

  group('JS arrow function parsing', () {
    test('parses a simple arrow function', () {
      const source = 'const double = (x) => x * 2;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('double'));
      expect(funcs[0].lineStart, equals(1));
    });

    test('parses an async arrow function', () {
      const source = 'const load = async () => await fetch("/data");\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('load'));
      expect(funcs[0].signature, contains('async'));
    });

    test('arrow function is not duplicated with variable', () {
      // Arrow functions should NOT appear as variables
      const source =
          'const x: number = 5;\n'
          'const fn = () => {};\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final funcs = symbols.where((s) => s.type == 'function').toList();
      final vars = symbols.where((s) => s.type == 'variable').toList();

      // Arrow function appears as function, not variable
      expect(funcs.any((s) => s.name == 'fn'), isTrue);
      expect(vars.any((s) => s.name == 'fn'), isFalse);
      // Plain typed variable appears as variable
      expect(vars.any((s) => s.name == 'x'), isTrue);
    });
  });

  // ─── 5. JS 变量解析 ──────────────────────────────────────────

  group('JS variable parsing', () {
    test('parses typed const variable', () {
      const source = 'const count: number = 42;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final vars = symbols.where((s) => s.type == 'variable').toList();
      expect(vars, hasLength(1));
      expect(vars[0].name, equals('count'));
      expect(vars[0].lineStart, equals(1));
    });

    test('parses let and const typed variables', () {
      const source =
          'let name: string = "hello";\n'
          'const PI: number = 3.14;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final vars = symbols.where((s) => s.type == 'variable').toList();
      expect(vars, hasLength(2));
      expect(vars[0].name, equals('name'));
      expect(vars[1].name, equals('PI'));
    });

    test('does not parse untyped variable as typed variable', () {
      // Without type annotation, the regex `(\w+)\s*:` won't match
      const source = 'const greeting = "hello";\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final vars = symbols.where((s) => s.type == 'variable').toList();
      expect(vars, isEmpty);
    });
  });

  // ─── 6. TS interface 解析 ────────────────────────────────────

  group('TS interface parsing', () {
    test('parses a plain interface', () {
      const source =
          'interface User {\n'
          '  name: string;\n'
          '  age: number;\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final ifaces = symbols.where((s) => s.type == 'interface').toList();
      expect(ifaces, hasLength(1));
      expect(ifaces[0].name, equals('User'));
      expect(ifaces[0].lineStart, equals(1));
      expect(ifaces[0].lineEnd, equals(4));
    });

    test('parses an exported generic interface', () {
      const source =
          'export interface Repository<T> {\n'
          '  findById(id: string): Promise<T>;\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final ifaces = symbols.where((s) => s.type == 'interface').toList();
      expect(ifaces, hasLength(1));
      expect(ifaces[0].name, equals('Repository'));
      expect(ifaces[0].signature, contains('export interface Repository'));
    });

    test('does not parse interface when isTypeScript is false', () {
      const source =
          'interface Foo {\n'
          '  bar: string;\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final ifaces = symbols.where((s) => s.type == 'interface').toList();
      expect(ifaces, isEmpty);
    });

    test('parses interface with extends clause', () {
      const source =
          'interface Animal {\n'
          '  name: string;\n'
          '}\n'
          '\n'
          'interface Dog extends Animal {\n'
          '  breed: string;\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final ifaces = symbols.where((s) => s.type == 'interface').toList();
      expect(ifaces, hasLength(2));
      expect(ifaces[0].name, equals('Animal'));
      expect(ifaces[1].name, equals('Dog'));
    });
  });

  // ─── 7. TS type alias 解析 ───────────────────────────────────

  group('TS type alias parsing', () {
    test('parses a type alias', () {
      const source = 'type StringOrNumber = string | number;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final types = symbols.where((s) => s.type == 'type').toList();
      expect(types, hasLength(1));
      expect(types[0].name, equals('StringOrNumber'));
      expect(types[0].lineStart, equals(1));
    });

    test('parses an exported type alias', () {
      const source = 'export type ID = string | number;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final types = symbols.where((s) => s.type == 'type').toList();
      expect(types, hasLength(1));
      expect(types[0].name, equals('ID'));
    });

    test('does not parse type alias when isTypeScript is false', () {
      const source = 'type Foo = string;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final types = symbols.where((s) => s.type == 'type').toList();
      expect(types, isEmpty);
    });
  });

  // ─── 8. TS enum 解析 ─────────────────────────────────────────

  group('TS enum parsing', () {
    test('parses a plain enum', () {
      const source =
          'enum Color {\n'
          '  Red,\n'
          '  Green,\n'
          '  Blue,\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Color'));
      expect(enums[0].lineStart, equals(1));
      expect(enums[0].lineEnd, equals(5));
    });

    test('parses a const enum', () {
      const source =
          'const enum Direction {\n'
          '  Up,\n'
          '  Down,\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Direction'));
    });

    test('does not parse enum when isTypeScript is false', () {
      const source =
          'enum Status {\n'
          '  Active,\n'
          '  Inactive,\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, isEmpty);
    });
  });

  // ─── 9. TS namespace 解析 ────────────────────────────────────

  group('TS namespace parsing', () {
    test('parses a namespace', () {
      const source =
          'namespace Utils {\n'
          '  export function helper() {}\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final nss = symbols.where((s) => s.type == 'namespace').toList();
      expect(nss, hasLength(1));
      expect(nss[0].name, equals('Utils'));
      expect(nss[0].lineStart, equals(1));
      expect(nss[0].lineEnd, equals(3));
    });

    test('parses an exported namespace', () {
      const source =
          'export namespace Config {\n'
          '  const version = "1.0";\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final nss = symbols.where((s) => s.type == 'namespace').toList();
      expect(nss, hasLength(1));
      expect(nss[0].name, equals('Config'));
      expect(nss[0].signature, contains('export namespace Config'));
    });

    test('does not parse namespace when isTypeScript is false', () {
      const source =
          'namespace Foo {\n'
          '  function bar() {}\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final nss = symbols.where((s) => s.type == 'namespace').toList();
      expect(nss, isEmpty);
    });
  });

  // ─── 10. TS decorator 解析 ───────────────────────────────────

  group('TS decorator parsing', () {
    test('parses a class decorator', () {
      const source =
          '@Component({\n'
          '  selector: "app-root"\n'
          '})\n'
          'class AppComponent {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final decorators = symbols.where((s) => s.type == 'decorator').toList();
      expect(decorators, hasLength(1));
      expect(decorators[0].name, equals('@Component'));
      expect(decorators[0].lineStart, equals(1));
    });

    test('parses a standalone decorator (top-level)', () {
      const source =
          '@Get("/users")\n'
          'function findAll() {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final decorators = symbols.where((s) => s.type == 'decorator').toList();
      expect(decorators, hasLength(1));
      expect(decorators[0].name, equals('@Get'));
      expect(decorators[0].lineStart, equals(1));
    });

    test('parses multiple decorators', () {
      const source =
          '@Injectable()\n'
          '@Controller("/api")\n'
          'class ApiController {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      final decorators = symbols.where((s) => s.type == 'decorator').toList();
      expect(decorators, hasLength(2));
      expect(decorators[0].name, equals('@Injectable'));
      expect(decorators[1].name, equals('@Controller'));
    });

    test('does not parse decorator when isTypeScript is false', () {
      const source =
          '@log\n'
          'function foo() {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final decorators = symbols.where((s) => s.type == 'decorator').toList();
      expect(decorators, isEmpty);
    });
  });

  // ─── 11. symbolTypeFilter 过滤 ───────────────────────────────

  group('symbolTypeFilter', () {
    test('filters to only class symbols', () {
      const source =
          'class Foo {}\n'
          'function bar() {}\n'
          'const x: number = 1;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse(symbolTypeFilter: 'class');

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('class'));
      expect(symbols[0].name, equals('Foo'));
    });

    test('filters to only function symbols', () {
      const source =
          'class Foo {}\n'
          'function bar() {}\n'
          'const x: number = 1;\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse(symbolTypeFilter: 'function');

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('function'));
      expect(symbols[0].name, equals('bar'));
    });

    test('"all" filter returns everything', () {
      const source =
          'class Foo {}\n'
          'function bar() {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final allSymbols = parser.parse();
      final filtered = parser.parse(symbolTypeFilter: 'all');

      expect(filtered.length, equals(allSymbols.length));
    });

    test('non-matching filter returns empty list', () {
      const source = 'class Foo {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse(symbolTypeFilter: 'interface');

      expect(symbols, isEmpty);
    });
  });

  // ─── 12. namePattern 正则过滤 ────────────────────────────────

  group('namePattern filter', () {
    test('filters symbols by name regex', () {
      const source =
          'class UserStore {}\n'
          'class ProductStore {}\n'
          'function doSomething() {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse(namePattern: 'Store');

      expect(symbols, hasLength(2));
      for (final s in symbols) {
        expect(s.name, contains('Store'));
      }
    });

    test('namePattern combined with symbolTypeFilter', () {
      const source =
          'class UserService {}\n'
          'function getUser() {}\n'
          'class ProductRepository {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse(
        symbolTypeFilter: 'class',
        namePattern: 'Service',
      );

      expect(symbols, hasLength(1));
      expect(symbols[0].name, equals('UserService'));
      expect(symbols[0].type, equals('class'));
    });

    test('namePattern with no matches returns empty list', () {
      const source =
          'class Foo {}\n'
          'function bar() {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse(namePattern: 'NonExistent');

      expect(symbols, isEmpty);
    });

    test('namePattern matches import names', () {
      const source =
          "import React from 'react';\n"
          "import Vue from 'vue';\n";
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse(namePattern: 'React');

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, contains('React'));
    });
  });

  // ─── 综合/边界场景 ──────────────────────────────────────────

  group('edge cases', () {
    test('empty source returns empty symbols', () {
      const source = '';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();
      expect(symbols, isEmpty);
    });

    test('comments are ignored', () {
      const source =
          '// class CommentedClass {}\n'
          'class RealClass {}\n'
          '/* function commented() {} */\n'
          'function real() {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final classes = symbols.where((s) => s.type == 'class').toList();
      final funcs = symbols.where((s) => s.type == 'function').toList();

      expect(classes, hasLength(1));
      expect(classes[0].name, equals('RealClass'));
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('real'));
    });

    test('multi-line block comment hides symbols', () {
      const source =
          '/*\n'
          'class Hidden {}\n'
          'function hidden() {}\n'
          '*/\n'
          'class Visible {}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: false,
      );
      final symbols = parser.parse();

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes[0].name, equals('Visible'));
    });

    test('complex TS file with mixed symbols', () {
      const source =
          "import { Injectable } from '@angular/core';\n"
          '\n'
          '@Injectable()\n'
          'export interface Config {\n'
          '  host: string;\n'
          '  port: number;\n'
          '}\n'
          '\n'
          'enum Status {\n'
          '  Active,\n'
          '  Inactive,\n'
          '}\n'
          '\n'
          'export class AppService {\n'
          '  private config: Config;\n'
          '\n'
          '  constructor(config: Config) {\n'
          '    this.config = config;\n'
          '  }\n'
          '\n'
          '  async getStatus(): Promise<Status> {\n'
          '    return Status.Active;\n'
          '  }\n'
          '\n'
          '  const handler = (event: Event) => {\n'
          '    console.log(event);\n'
          '  };\n'
          '}\n';
      final parser = JsTsParser(
        content: source,
        lines: source.split('\n'),
        isTypeScript: true,
      );
      final symbols = parser.parse();

      // Should find: import, decorator, interface, enum, class, function (arrow)
      expect(symbols.where((s) => s.type == 'import'), hasLength(1));
      expect(symbols.where((s) => s.type == 'decorator'), hasLength(1));
      expect(symbols.where((s) => s.type == 'interface'), hasLength(1));
      expect(symbols.where((s) => s.type == 'enum'), hasLength(1));
      expect(symbols.where((s) => s.type == 'class'), hasLength(1));

      // The arrow function regex uses ^ anchor (start of line),
      // so indented arrow functions inside a class body are not matched.
      // This is expected behavior of JsTsParser.
      final arrowFuncs =
          symbols.where((s) => s.type == 'function' && s.name == 'handler');
      expect(arrowFuncs, isEmpty);
    });
  });
}
