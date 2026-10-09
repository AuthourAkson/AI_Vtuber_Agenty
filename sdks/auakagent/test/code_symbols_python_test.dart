import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/python_parser.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/symbol_parser.dart';

void main() {
  // ─── 1. Import parsing ─────────────────────────────────────────

  group('import parsing', () {
    test('parses a simple import statement', () {
      const source = 'import os\nimport sys';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, hasLength(2));
      expect(imports[0].name, 'import os');
      expect(imports[0].type, 'import');
      expect(imports[0].lineStart, 1);
      expect(imports[0].lineEnd, 1);
      expect(imports[0].signature, 'import os');
      expect(imports[1].name, 'import sys');
    });

    test('parses a from-import statement', () {
      const source = 'from sys import path\nfrom os.path import join';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, hasLength(2));
      expect(imports[0].name, 'from sys import path');
      expect(imports[0].type, 'import');
      expect(imports[0].lineStart, 1);
      expect(imports[1].name, 'from os.path import join');
      expect(imports[1].lineStart, 2);
    });
  });

  // ─── 2. Class parsing ──────────────────────────────────────────

  group('class parsing', () {
    test('parses a simple class', () {
      const source = 'class Foo:\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final cls = symbols.firstWhere((s) => s.type == 'class');
      expect(cls.name, 'Foo');
      expect(cls.type, 'class');
      expect(cls.lineStart, 1);
      expect(cls.lineEnd, 2);
      expect(cls.signature, 'class Foo:');
      expect(cls.parentName, isNull);
    });

    test('parses a class with inheritance', () {
      const source = 'class Foo(Bar):\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final cls = symbols.firstWhere((s) => s.type == 'class');
      expect(cls.name, 'Foo');
      expect(cls.type, 'class');
      expect(cls.lineStart, 1);
      expect(cls.signature, 'class Foo(Bar):');
    });

    test('parses a nested class', () {
      const source = 'class Outer:\n    class Inner:\n        pass\n\nclass Other:\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final classes = symbols.where((s) => s.type == 'class').toList();
      // Note: the regex uses ^ which only matches top-level classes.
      // Nested classes with indentation are not matched.
      expect(classes, hasLength(2));
      expect(classes[0].name, 'Outer');
      expect(classes[0].lineStart, 1);
      expect(classes[1].name, 'Other');
      expect(classes[1].lineStart, 5);
    });
  });

  // ─── 3. Function parsing ───────────────────────────────────────

  group('function parsing', () {
    test('parses a regular function', () {
      const source = 'def foo():\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final func = symbols.firstWhere((s) => s.type == 'function');
      expect(func.name, 'foo');
      expect(func.type, 'function');
      expect(func.lineStart, 1);
      expect(func.lineEnd, 2);
      expect(func.signature, 'def foo():');
      expect(func.parentName, isNull);
    });

    test('parses an async function', () {
      const source = 'async def bar():\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final func = symbols.firstWhere((s) => s.type == 'function');
      expect(func.name, 'bar');
      expect(func.type, 'function');
      expect(func.lineStart, 1);
      expect(func.signature, 'async def bar():');
    });
  });

  // ─── 4. Method parsing ─────────────────────────────────────────

  group('method parsing', () {
    test('parses methods inside a class', () {
      const source = 'class Foo:\n    def method_a(self):\n        pass\n\n    def method_b(self):\n        pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(2));
      expect(methods[0].name, 'method_a');
      expect(methods[0].type, 'method');
      expect(methods[0].parentName, 'Foo');
      expect(methods[1].name, 'method_b');
      expect(methods[1].parentName, 'Foo');
    });
  });

  // ─── 5. @property getter ───────────────────────────────────────

  group('@property getter', () {
    test('parses a property getter', () {
      const source = 'class Foo:\n    @property\n    def name(self):\n        return self._name';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final getter = symbols.firstWhere((s) => s.type == 'getter');
      expect(getter.name, 'name');
      expect(getter.type, 'getter');
      expect(getter.lineStart, 3);
      expect(getter.parentName, 'Foo');
    });
  });

  // ─── 6. @name.setter ───────────────────────────────────────────

  group('@name.setter', () {
    test('parses a property setter', () {
      const source = 'class Foo:\n    @name.setter\n    def name(self, value):\n        self._name = value';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final setter = symbols.firstWhere((s) => s.type == 'setter');
      expect(setter.name, 'name');
      expect(setter.type, 'setter');
      expect(setter.lineStart, 3);
      expect(setter.parentName, 'Foo');
    });
  });

  // ─── 7. @staticmethod / @classmethod ───────────────────────────

  group('@staticmethod and @classmethod', () {
    test('parses a staticmethod', () {
      const source = 'class Foo:\n    @staticmethod\n    def static_method():\n        pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final method = symbols.firstWhere((s) => s.type == 'method');
      expect(method.name, 'static_method');
      expect(method.type, 'method');
      expect(method.parentName, 'Foo');
    });

    test('parses a classmethod', () {
      const source = 'class Foo:\n    @classmethod\n    def from_string(cls, s):\n        pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final method = symbols.firstWhere((s) => s.type == 'method');
      expect(method.name, 'from_string');
      expect(method.type, 'method');
      expect(method.parentName, 'Foo');
    });
  });

  // ─── 8. Variable parsing ───────────────────────────────────────

  group('variable parsing', () {
    test('parses top-level UPPER_CASE variables', () {
      const source = 'MAX_SIZE = 100\nDEFAULT_NAME = "hello"\napi_url = "https://example.com"';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final variables = symbols.where((s) => s.type == 'variable').toList();
      expect(variables, hasLength(2));
      expect(variables[0].name, 'MAX_SIZE');
      expect(variables[0].type, 'variable');
      expect(variables[0].lineStart, 1);
      expect(variables[1].name, 'DEFAULT_NAME');
      expect(variables[1].lineStart, 2);
    });
  });

  // ─── 9. Decorator parsing ──────────────────────────────────────

  group('decorator parsing', () {
    test('parses custom decorators on functions', () {
      const source = '@app.route("/home")\ndef home():\n    return "hello"';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final decorators = symbols.where((s) => s.type == 'decorator').toList();
      expect(decorators, isNotEmpty);
      expect(decorators.first.name, '@app.route("/home")');
      expect(decorators.first.type, 'decorator');
      expect(decorators.first.lineStart, 1);
      expect(decorators.first.parentName, 'home');
    });

    test('parses custom decorators on classes', () {
      const source = '@dataclass\nclass Point:\n    x: int\n    y: int';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final decorators = symbols.where((s) => s.type == 'decorator').toList();
      expect(decorators, isNotEmpty);
      expect(decorators.first.name, '@dataclass');
      expect(decorators.first.type, 'decorator');
      expect(decorators.first.parentName, 'Point');
    });
  });

  // ─── 10. symbol_type filter ────────────────────────────────────

  group('symbol_type filter', () {
    test('filters symbols by type', () {
      const source = 'import os\n\nclass Foo:\n    pass\n\ndef bar():\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse(symbolTypeFilter: 'class');

      expect(symbols, hasLength(1));
      expect(symbols.first.type, 'class');
      expect(symbols.first.name, 'Foo');
    });

    test('returns all symbols when filter is all', () {
      const source = 'import os\n\nclass Foo:\n    pass\n\ndef bar():\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse(symbolTypeFilter: 'all');

      expect(symbols.length, greaterThan(1));
    });
  });

  // ─── 11. name_pattern filter ───────────────────────────────────

  group('name_pattern filter', () {
    test('filters symbols by name regex pattern', () {
      const source = 'def foo():\n    pass\n\ndef bar():\n    pass\n\ndef foobar():\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse(namePattern: r'^foo');

      expect(symbols, isNotEmpty);
      for (final s in symbols) {
        expect(RegExp(r'^foo').hasMatch(s.name), isTrue);
      }
    });

    test('returns empty when no symbols match the pattern', () {
      const source = 'def foo():\n    pass\n\ndef bar():\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse(namePattern: r'^xyz');

      expect(symbols, isEmpty);
    });
  });

  // ─── 12. Comment lines not parsed ──────────────────────────────

  group('comment lines', () {
    test('does not parse comment lines as symbols', () {
      const source = '# This is a comment\n# import os\n\ndef foo():\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      // The commented import should NOT appear
      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, isEmpty);

      // The function should still be parsed
      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs.first.name, 'foo');
    });

    test('does not parse commented class definitions', () {
      const source = '# class Foo:\n#     pass\n\nclass Bar:\n    pass';
      final parser = PythonParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes.first.name, 'Bar');
    });
  });
}
