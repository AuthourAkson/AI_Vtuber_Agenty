import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/go_parser.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/symbol_parser.dart';

void main() {
  // ─── Helper ────────────────────────────────────────────────────

  /// Parse the given Go source string and return the list of symbols.
  List<CodeSymbol> parse(String source, {String? symbolTypeFilter, String? namePattern}) {
    final parser = GoParser(content: source, lines: source.split('\n'));
    return parser.parse(symbolTypeFilter: symbolTypeFilter, namePattern: namePattern);
  }

  // ─── 1. Package declaration ──────────────────────────────────

  group('Package declaration', () {
    test('parses package main as import type', () {
      const source = 'package main';
      final symbols = parse(source);

      expect(symbols, hasLength(1));
      expect(symbols[0].name, equals('main'));
      expect(symbols[0].type, equals('import'));
      expect(symbols[0].lineStart, equals(1));
      expect(symbols[0].lineEnd, equals(1));
      expect(symbols[0].signature, equals('package main'));
    });

    test('parses package with a custom name', () {
      const source = 'package myapp\n\nfunc hello() {}';
      final symbols = parse(source);

      final pkg = symbols.where((s) => s.name == 'myapp').toList();
      expect(pkg, hasLength(1));
      expect(pkg[0].type, equals('import'));
    });
  });

  // ─── 2. Import parsing ───────────────────────────────────────

  group('Import parsing', () {
    test('parses single-line import as import type', () {
      const source = 'package main\nimport "fmt"';
      final symbols = parse(source);

      final imports = symbols.where((s) => s.type == 'import' && s.name.contains('fmt')).toList();
      expect(imports, hasLength(1));
      expect(imports[0].name, equals('import "fmt"'));
      expect(imports[0].type, equals('import'));
      expect(imports[0].lineStart, equals(2));
    });

    test('parses multi-line import block', () {
      const source = 'package main\nimport (\n\t"fmt"\n\t"os"\n)';
      final symbols = parse(source);

      final imports = symbols.where((s) => s.type == 'import' && s.name.contains('"')).toList();
      expect(imports, hasLength(2));
      expect(imports[0].name, equals('"fmt"'));
      expect(imports[0].lineStart, equals(3));
      expect(imports[1].name, equals('"os"'));
      expect(imports[1].lineStart, equals(4));
    });
  });

  // ─── 3. Struct parsing ───────────────────────────────────────

  group('Struct parsing', () {
    test('parses simple struct with correct type and line range', () {
      const source = 'type Point struct {\n\tX int\n\tY int\n}';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Point'));
      expect(structs[0].lineStart, equals(1));
      expect(structs[0].lineEnd, equals(4));
      expect(structs[0].signature, equals('type Point struct {'));
    });

    test('parses struct with multiple fields', () {
      const source = 'type Person struct {\n\tName    string\n\tAge     int\n\tAddress string\n}';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Person'));
      expect(structs[0].lineStart, equals(1));
      expect(structs[0].lineEnd, equals(5));
    });
  });

  // ─── 4. Interface parsing ────────────────────────────────────

  group('Interface parsing', () {
    test('parses interface with method signature', () {
      const source = 'type Reader interface {\n\tRead(p []byte) (n int, err error)\n}';
      final symbols = parse(source);

      final ifaces = symbols.where((s) => s.type == 'interface').toList();
      expect(ifaces, hasLength(1));
      expect(ifaces[0].name, equals('Reader'));
      expect(ifaces[0].lineStart, equals(1));
      expect(ifaces[0].lineEnd, equals(3));
      expect(ifaces[0].signature, equals('type Reader interface {'));
    });

    test('parses empty interface', () {
      const source = 'type Empty interface {}';
      final symbols = parse(source);

      final ifaces = symbols.where((s) => s.type == 'interface').toList();
      expect(ifaces, hasLength(1));
      expect(ifaces[0].name, equals('Empty'));
    });
  });

  // ─── 5. Function parsing ─────────────────────────────────────

  group('Function parsing', () {
    test('parses simple function as function type', () {
      const source = 'func main() {}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('main'));
      expect(funcs[0].lineStart, equals(1));
      expect(funcs[0].lineEnd, equals(1));
      expect(funcs[0].signature, equals('func main() {}'));
    });

    test('parses function with parameters and return type', () {
      const source = 'func add(a, b int) int {\n\treturn a + b\n}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('add'));
      expect(funcs[0].lineStart, equals(1));
      expect(funcs[0].lineEnd, equals(3));
      expect(funcs[0].signature, equals('func add(a, b int) int {'));
    });

    test('parses multi-line function body correctly', () {
      const source = 'func greet(name string) string {\n\tmsg := "Hello, " + name\n\treturn msg\n}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('greet'));
      expect(funcs[0].lineStart, equals(1));
      expect(funcs[0].lineEnd, equals(4));
    });
  });

  // ─── 6. Method parsing ───────────────────────────────────────

  group('Method parsing', () {
    test('parses pointer receiver method with correct parentName', () {
      const source = 'func (r *Receiver) Method() {}';
      final symbols = parse(source);

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(1));
      expect(methods[0].name, equals('Method'));
      expect(methods[0].type, equals('method'));
      expect(methods[0].parentName, equals('Receiver'));
      expect(methods[0].lineStart, equals(1));
    });

    test('parses value receiver method', () {
      const source = 'func (s Server) Start() {\n\treturn\n}';
      final symbols = parse(source);

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(1));
      expect(methods[0].name, equals('Start'));
      expect(methods[0].parentName, equals('Server'));
      expect(methods[0].lineStart, equals(1));
      expect(methods[0].lineEnd, equals(3));
    });
  });

  // ─── 7. Type alias ───────────────────────────────────────────

  group('Type alias parsing', () {
    test('parses type alias as typedef', () {
      const source = 'type Alias = OriginalType';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, hasLength(1));
      expect(typedefs[0].name, equals('Alias'));
      expect(typedefs[0].type, equals('typedef'));
      expect(typedefs[0].lineStart, equals(1));
      expect(typedefs[0].signature, equals('type Alias = OriginalType'));
    });

    test('parses multiple type aliases', () {
      const source = 'type ByteSlice = []byte\ntype RuneSlice = []rune';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, hasLength(2));
      expect(typedefs[0].name, equals('ByteSlice'));
      expect(typedefs[1].name, equals('RuneSlice'));
    });
  });

  // ─── 8. Iota enum pattern ────────────────────────────────────

  group('Iota enum pattern', () {
    test('parses iota enum as enum type', () {
      const source = 'type Color int\nconst (\n\tRed Color = iota\n\tGreen\n\tBlue\n)';
      final symbols = parse(source);

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Color'));
      expect(enums[0].type, equals('enum'));
      expect(enums[0].lineStart, equals(1));
    });

    test('does not treat plain int type as enum without iota', () {
      const source = 'type Status int\nvar s Status = 1';
      final symbols = parse(source);

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, isEmpty);
    });
  });

  // ─── 9. var declaration ──────────────────────────────────────

  group('var declaration', () {
    test('parses single var declaration as variable type', () {
      const source = 'var x int = 5';
      final symbols = parse(source);

      final vars = symbols.where((s) => s.type == 'variable').toList();
      expect(vars, hasLength(1));
      expect(vars[0].name, equals('x'));
      expect(vars[0].type, equals('variable'));
      expect(vars[0].lineStart, equals(1));
      expect(vars[0].signature, equals('var x int = 5'));
    });

    test('parses var block with multiple declarations', () {
      const source = 'var (\n\tname string\n\tage  int\n)';
      final symbols = parse(source);

      final vars = symbols.where((s) => s.type == 'variable').toList();
      expect(vars, hasLength(2));
      expect(vars[0].name, equals('name'));
      expect(vars[0].lineStart, equals(2));
      expect(vars[1].name, equals('age'));
      expect(vars[1].lineStart, equals(3));
    });
  });

  // ─── 10. const declaration ───────────────────────────────────

  group('const declaration', () {
    test('parses single const declaration as variable type', () {
      const source = 'const Pi = 3.14';
      final symbols = parse(source);

      final consts = symbols.where((s) => s.type == 'variable').toList();
      expect(consts, hasLength(1));
      expect(consts[0].name, equals('Pi'));
      expect(consts[0].type, equals('variable'));
      expect(consts[0].lineStart, equals(1));
      expect(consts[0].signature, equals('const Pi = 3.14'));
    });

    test('parses const block declarations', () {
      const source = 'const (\n\tMaxRetries = 3\n\tTimeout   = 30\n)';
      final symbols = parse(source);

      final consts = symbols.where((s) => s.type == 'variable').toList();
      expect(consts, hasLength(2));
      expect(consts[0].name, equals('MaxRetries'));
      expect(consts[1].name, equals('Timeout'));
    });
  });

  // ─── 11. symbol_type filter ──────────────────────────────────

  group('symbolTypeFilter', () {
    test('filters to only function symbols', () {
      const source = 'package main\nimport "fmt"\nfunc main() {}\nfunc helper() {}';
      final symbols = parse(source, symbolTypeFilter: 'function');

      expect(symbols, hasLength(2));
      for (final s in symbols) {
        expect(s.type, equals('function'));
      }
      expect(symbols.map((s) => s.name), containsAll(['main', 'helper']));
    });

    test('filters to only struct symbols', () {
      const source = 'type Point struct {\n\tX int\n}\nfunc main() {}';
      final symbols = parse(source, symbolTypeFilter: 'struct');

      expect(symbols, hasLength(1));
      expect(symbols[0].name, equals('Point'));
      expect(symbols[0].type, equals('struct'));
    });

    test('returns all symbols when filter is null', () {
      const source = 'package main\nfunc main() {}';
      final symbols = parse(source);

      expect(symbols.length, greaterThanOrEqualTo(2));
    });
  });

  // ─── 12. Comment filtering ───────────────────────────────────

  group('Comment filtering', () {
    test('ignores symbols on single-line comment lines', () {
      const source = '// func commentedOut() {}\nfunc real() {}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('real'));
    });

    test('ignores symbols inside block comments', () {
      const source = '/*\nfunc hiddenFunc() {}\n*/\nfunc visibleFunc() {}';
      final symbols = parse(source);

      final funcs = symbols.where((s) => s.type == 'function').toList();
      expect(funcs, hasLength(1));
      expect(funcs[0].name, equals('visibleFunc'));
    });

    test('ignores package declaration inside a line comment', () {
      const source = '// package fake\npackage real';
      final symbols = parse(source);

      final pkgs = symbols.where((s) => s.type == 'import' && s.name == 'package').toList();
      // 'real' is the package name, 'fake' is commented out
      expect(pkgs, isNot(anyElement((s) => s.name == 'fake')));
    });

    test('ignores struct inside block comment', () {
      const source = '/* type Hidden struct {\n\tX int\n} */\ntype Visible struct {\n\tY int\n}';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Visible'));
    });
  });
}
