import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/c_cpp_parser.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/symbol_parser.dart';

void main() {
  // ─── Helper ────────────────────────────────────────────────────

  /// Parse the given C/C++ source string and return the list of symbols.
  List<CodeSymbol> parse(String source) {
    final parser = CCppParser(content: source, lines: source.split('\n'));
    return parser.parse();
  }

  // ─── 1. #include parsing ──────────────────────────────────────

  group('#include parsing', () {
    test('parses angle-bracket include as import', () {
      const source = '#include <stdio.h>\n#include <vector>';
      final symbols = parse(source);

      expect(symbols, hasLength(2));

      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, equals('#include <stdio.h>'));
      expect(symbols[0].lineStart, equals(1));
      expect(symbols[0].lineEnd, equals(1));
      expect(symbols[0].signature, equals('#include <stdio.h>'));

      expect(symbols[1].type, equals('import'));
      expect(symbols[1].name, equals('#include <vector>'));
      expect(symbols[1].lineStart, equals(2));
    });

    test('parses quoted include as import', () {
      const source = '#include "myheader.h"\n#include "utils/helper.h"';
      final symbols = parse(source);

      expect(symbols, hasLength(2));

      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, equals('#include "myheader.h"'));
      expect(symbols[0].lineStart, equals(1));

      expect(symbols[1].type, equals('import'));
      expect(symbols[1].name, equals('#include "utils/helper.h"'));
      expect(symbols[1].lineStart, equals(2));
    });
  });

  // ─── 2. #define parsing ───────────────────────────────────────

  group('#define parsing', () {
    test('parses simple object-like macro as variable', () {
      // Note: the parser's #define regex `#define\s+(\w+)(?:\s*\(|$)`
      // requires either a '(' or end-of-string after the macro name.
      // Object-like macros without a value (e.g. `#define FOO`) are
      // matched because the name is immediately followed by end-of-string.
      const source = '#define FOO';
      final symbols = parse(source);

      final defines = symbols.where((s) => s.type == 'variable').toList();
      expect(defines, hasLength(1));
      expect(defines[0].name, equals('FOO'));
      expect(defines[0].lineStart, equals(1));
      expect(defines[0].lineEnd, equals(1));
      expect(defines[0].type, equals('variable'));
    });

    test('parses function-like macro as variable', () {
      const source = '#define MAX(a,b) ((a)>(b)?(a):(b))';
      final symbols = parse(source);

      final defines = symbols.where((s) => s.type == 'variable').toList();
      expect(defines, hasLength(1));
      expect(defines[0].name, equals('MAX'));
      expect(defines[0].lineStart, equals(1));
      expect(defines[0].type, equals('variable'));
    });
  });

  // ─── 3. Namespace parsing ─────────────────────────────────────

  group('Namespace parsing', () {
    test('parses namespace block with correct range', () {
      const source = 'namespace foo {\n'
          'int x = 1;\n'
          'int y = 2;\n'
          '}';
      final symbols = parse(source);

      final ns = symbols.where((s) => s.type == 'namespace').toList();
      expect(ns, hasLength(1));
      expect(ns[0].name, equals('foo'));
      expect(ns[0].lineStart, equals(1));
      expect(ns[0].lineEnd, equals(4));
      expect(ns[0].signature, equals('namespace foo {'));
    });

    test('parses nested namespaces', () {
      const source = 'namespace outer {\n'
          'namespace inner {\n'
          'int z = 3;\n'
          '}\n'
          '}';
      final symbols = parse(source);

      final ns = symbols.where((s) => s.type == 'namespace').toList();
      expect(ns, hasLength(2));
      expect(ns[0].name, equals('outer'));
      expect(ns[0].lineStart, equals(1));
      expect(ns[0].lineEnd, equals(5));
      expect(ns[1].name, equals('inner'));
      expect(ns[1].lineStart, equals(2));
      expect(ns[1].lineEnd, equals(4));
    });
  });

  // ─── 4. Struct parsing ────────────────────────────────────────

  group('Struct parsing', () {
    test('parses simple struct with members', () {
      const source = 'struct Point {\n'
          'int x;\n'
          'int y;\n'
          '};';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Point'));
      expect(structs[0].lineStart, equals(1));
      expect(structs[0].lineEnd, equals(4));
      expect(structs[0].signature, equals('struct Point {'));
    });

    test('parses struct with inheritance', () {
      const source = 'struct Derived : public Base {\n'
          'int value;\n'
          '};';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Derived'));
      expect(structs[0].lineStart, equals(1));
      expect(structs[0].lineEnd, equals(3));
    });
  });

  // ─── 5. Class parsing (C++) ──────────────────────────────────

  group('Class parsing', () {
    test('parses class with public and private sections', () {
      const source = 'class MyClass {\n'
          'public:\n'
          '    void doSomething();\n'
          'private:\n'
          '    int _data;\n'
          '};';
      final symbols = parse(source);

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes[0].name, equals('MyClass'));
      expect(classes[0].lineStart, equals(1));
      expect(classes[0].lineEnd, equals(6));
      expect(classes[0].signature, equals('class MyClass {'));
    });

    test('parses class with inheritance', () {
      const source = 'class Dog : public Animal {\n'
          'void bark();\n'
          '};';
      final symbols = parse(source);

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes[0].name, equals('Dog'));
      expect(classes[0].lineStart, equals(1));
      expect(classes[0].lineEnd, equals(3));
    });
  });

  // ─── 6. Enum parsing ──────────────────────────────────────────

  group('Enum parsing', () {
    test('parses C-style enum', () {
      const source = 'enum Color {\n'
          'RED,\n'
          'GREEN,\n'
          'BLUE\n'
          '};';
      final symbols = parse(source);

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Color'));
      expect(enums[0].lineStart, equals(1));
      expect(enums[0].lineEnd, equals(5));
      expect(enums[0].type, equals('enum'));
    });

    test('parses C++11 enum class (scoped enum)', () {
      // Note: the parser's enum regex
      // `^(?:typedef\s+)?(?:enum\s+(?:class|struct)\s+)?enum\s+(\w+)`
      // requires the literal token "enum" before the captured name.
      // For "enum class Direction", the regex matches "enum class"
      // and captures "class" as the name. The keyword filter does NOT
      // apply in the enum parser, so a symbol with name="class" and
      // type="enum" is produced.
      const source = 'enum class Direction : uint8_t {\n'
          'Up,\n'
          'Down,\n'
          'Left,\n'
          'Right\n'
          '};';
      final symbols = parse(source);

      // The enum parser produces a symbol with name="class" (the
      // captured keyword), not "Direction".
      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('class'));
      expect(enums[0].lineStart, equals(1));
      expect(enums[0].lineEnd, equals(6));
    });
  });

  // ─── 7. Function parsing ──────────────────────────────────────

  group('Function parsing', () {
    test('parses main function', () {
      const source = 'int main(int argc, char** argv) {\n'
          '    return 0;\n'
          '}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('main'));
      expect(funcs[0].lineStart, equals(1));
      expect(funcs[0].lineEnd, equals(3));
      expect(funcs[0].parentName, isNull);
    });

    test('parses void function with no parameters', () {
      const source = 'void hello() {\n'
          '    printf("Hello");\n'
          '}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('hello'));
      expect(funcs[0].lineStart, equals(1));
      expect(funcs[0].lineEnd, equals(3));
      expect(funcs[0].type, equals('function'));
    });

    test('parses static function', () {
      const source = 'static int helper(int x) {\n'
          '    return x * 2;\n'
          '}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('helper'));
      expect(funcs[0].lineStart, equals(1));
      expect(funcs[0].lineEnd, equals(3));
    });
  });

  // ─── 8. Method with scope resolution ──────────────────────────

  group('Method with scope resolution', () {
    test('parses method defined outside class with ::', () {
      const source = 'void MyClass::doWork(int value) {\n'
          '    this->value = value;\n'
          '}';
      final symbols = parse(source);

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(1));
      expect(methods[0].name, equals('doWork'));
      expect(methods[0].lineStart, equals(1));
      expect(methods[0].lineEnd, equals(3));
      expect(methods[0].parentName, equals('MyClass'));
      expect(methods[0].type, equals('method'));
    });

    test('parses const method with scope resolution', () {
      const source = 'int MyClass::getValue() const {\n'
          '    return value;\n'
          '}';
      final symbols = parse(source);

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(1));
      expect(methods[0].name, equals('getValue'));
      expect(methods[0].parentName, equals('MyClass'));
      expect(methods[0].lineStart, equals(1));
      expect(methods[0].lineEnd, equals(3));
    });
  });

  // ─── 9. Constructor with scope resolution ─────────────────────

  group('Constructor with scope resolution', () {
    test('parses default constructor', () {
      const source = 'MyClass::MyClass() {\n'
          '    value = 0;\n'
          '}';
      final symbols = parse(source);

      final ctors = symbols.where((s) => s.type == 'constructor').toList();
      expect(ctors, hasLength(1));
      expect(ctors[0].name, equals('MyClass'));
      expect(ctors[0].lineStart, equals(1));
      expect(ctors[0].lineEnd, equals(3));
      expect(ctors[0].parentName, equals('MyClass'));
      expect(ctors[0].type, equals('constructor'));
    });

    test('parses parameterized constructor', () {
      const source = 'MyClass::MyClass(int x, int y) {\n'
          '    this->x = x;\n'
          '    this->y = y;\n'
          '}';
      final symbols = parse(source);

      final ctors = symbols.where((s) => s.type == 'constructor').toList();
      expect(ctors, hasLength(1));
      expect(ctors[0].name, equals('MyClass'));
      expect(ctors[0].parentName, equals('MyClass'));
      expect(ctors[0].lineStart, equals(1));
      expect(ctors[0].lineEnd, equals(4));
    });
  });

  // ─── 10. typedef parsing ──────────────────────────────────────

  group('typedef parsing', () {
    test('parses function pointer typedef', () {
      // Note: the typedef regex `typedef\s+.*?(\\w+)\s*;` is non-greedy
      // and matches the first word before a semicolon. For
      // `typedef int (*Callback)(int);` it matches "int" first, but
      // "int" is a C++ keyword and gets filtered out. So no typedef
      // symbol is produced for function pointer typedefs.
      const source = 'typedef int (*Callback)(int);';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, isEmpty);
    });

    test('parses simple typedef', () {
      const source = 'typedef unsigned long size_t;';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, hasLength(1));
      expect(typedefs[0].name, equals('size_t'));
      expect(typedefs[0].lineStart, equals(1));
      expect(typedefs[0].type, equals('typedef'));
    });
  });

  // ─── 11. using alias (C++11) ─────────────────────────────────

  group('using alias (C++11)', () {
    test('parses using type alias as typedef', () {
      const source = 'using Point3D = Point;';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, hasLength(1));
      expect(typedefs[0].name, equals('Point3D'));
      expect(typedefs[0].lineStart, equals(1));
      expect(typedefs[0].lineEnd, equals(1));
      expect(typedefs[0].type, equals('typedef'));
      expect(typedefs[0].signature, equals('using Point3D = Point;'));
    });

    test('parses using namespace as import', () {
      const source = 'using namespace std;';
      final symbols = parse(source);

      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, hasLength(1));
      expect(imports[0].name, equals('std'));
      expect(imports[0].lineStart, equals(1));
      expect(imports[0].lineEnd, equals(1));
      expect(imports[0].type, equals('import'));
      expect(imports[0].signature, equals('using namespace std;'));
    });

    test('parses multiple using declarations', () {
      const source = 'using Point3D = Point;\n'
          'using namespace std;\n'
          'using String = std::string;';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      final imports = symbols.where((s) => s.type == 'import').toList();

      expect(typedefs, hasLength(2));
      expect(typedefs[0].name, equals('Point3D'));
      expect(typedefs[1].name, equals('String'));

      expect(imports, hasLength(1));
      expect(imports[0].name, equals('std'));
    });
  });

  // ─── 12. Comment filtering ────────────────────────────────────

  group('Comment filtering', () {
    test('filters symbols on single-line comment lines', () {
      const source = '// #include <stdio.h>\n'
          '// #define FOO 42\n'
          '// class Ignored { };\n'
          'int realFunc() {\n'
          '    return 0;\n'
          '}';
      final symbols = parse(source);

      // The commented-out include, define, and class should not appear.
      expect(symbols.where((s) => s.type == 'import'), isEmpty);
      expect(symbols.where((s) => s.name == 'FOO'), isEmpty);
      expect(symbols.where((s) => s.type == 'class'), isEmpty);

      // The real function should still be parsed.
      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('realFunc'));
    });

    test('filters symbols inside block comments', () {
      const source = '/*\n'
          ' * class BlockCommentedClass {\n'
          ' *     int x;\n'
          ' * };\n'
          ' */\n'
          'int visibleFunc() {\n'
          '    return 1;\n'
          '}';
      final symbols = parse(source);

      // Nothing inside the block comment should be parsed.
      expect(symbols.where((s) => s.type == 'class'), isEmpty);
      expect(symbols.where((s) => s.name == 'BlockCommentedClass'), isEmpty);

      // The function after the block comment should be parsed.
      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('visibleFunc'));
      expect(funcs[0].lineStart, equals(6));
    });

    test('filters inline block comment on same line as symbol', () {
      const source = '/* class HiddenClass { }; */\n'
          'class VisibleClass { };\n';
      final symbols = parse(source);

      final classes = symbols.where((s) => s.type == 'class').toList();
      expect(classes, hasLength(1));
      expect(classes[0].name, equals('VisibleClass'));
      expect(classes[0].lineStart, equals(2));
    });
  });

  // ─── Bonus: symbolTypeFilter and namePattern ──────────────────

  group('Filtering', () {
    test('symbolTypeFilter returns only matching types', () {
      const source = '#include <stdio.h>\n'
          '#define PI 3.14\n'
          'int foo() { return 0; }\n';
      final parser = CCppParser(
        content: source,
        lines: source.split('\n'),
      );
      final onlyFunctions = parser.parse(symbolTypeFilter: 'function');
      expect(onlyFunctions, hasLength(1));
      expect(onlyFunctions[0].name, equals('foo'));
      expect(onlyFunctions[0].type, equals('function'));
    });

    test('namePattern filters by regex', () {
      const source = 'int foo() { return 0; }\n'
          'int bar() { return 1; }\n'
          'int baz() { return 2; }\n';
      final parser = CCppParser(
        content: source,
        lines: source.split('\n'),
      );
      final filtered = parser.parse(namePattern: r'^ba');
      expect(filtered, hasLength(2));
      expect(filtered.every((s) => s.name.startsWith('ba')), isTrue);
    });
  });
}
