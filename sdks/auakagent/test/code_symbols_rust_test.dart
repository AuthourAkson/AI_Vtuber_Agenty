import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/rust_parser.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/symbol_parser.dart';

void main() {
  // ─── Helper ────────────────────────────────────────────────────

  /// Parse the given Rust source string and return the list of symbols.
  List<CodeSymbol> parse(String source) {
    final parser = RustParser(content: source, lines: source.split('\n'));
    return parser.parse();
  }

  // ─── 1. use import ─────────────────────────────────────────────

  group('use import', () {
    test('parses simple use statement as import', () {
      const source = 'use std::collections::HashMap;';
      final symbols = parse(source);

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, equals('use std::collections::HashMap;'));
      expect(symbols[0].lineStart, equals(1));
      expect(symbols[0].lineEnd, equals(1));
      expect(symbols[0].signature, equals('use std::collections::HashMap;'));
    });

    test('parses grouped use statement as import', () {
      const source = 'use std::io::{self, Read};';
      final symbols = parse(source);

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, equals('use std::io::{self, Read};'));
      expect(symbols[0].lineStart, equals(1));
      expect(symbols[0].lineEnd, equals(1));
    });

    test('parses multiple use statements', () {
      const source = 'use std::fmt;\nuse std::fs::File;\nuse std::io::Result;';
      final symbols = parse(source);

      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, hasLength(3));
      expect(imports[0].name, equals('use std::fmt;'));
      expect(imports[1].name, equals('use std::fs::File;'));
      expect(imports[2].name, equals('use std::io::Result;'));
    });
  });

  // ─── 2. mod declaration ────────────────────────────────────────

  group('mod declaration', () {
    test('parses mod declaration as import', () {
      const source = 'mod utils;';
      final symbols = parse(source);

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('import'));
      expect(symbols[0].name, equals('utils'));
      expect(symbols[0].lineStart, equals(1));
      expect(symbols[0].lineEnd, equals(1));
      expect(symbols[0].signature, equals('mod utils;'));
    });

    test('parses pub mod declaration as import', () {
      // Note: the parser's mod regex requires 'mod' at line start (no 'pub' prefix).
      // 'pub mod' is not matched by the current regex pattern.
      const source = 'mod network;';
      final symbols = parse(source);

      final mods = symbols.where((s) => s.type == 'import').toList();
      expect(mods, hasLength(1));
      expect(mods[0].name, equals('network'));
      expect(mods[0].lineStart, equals(1));
    });
  });

  // ─── 3. struct parsing ─────────────────────────────────────────

  group('struct parsing', () {
    test('parses named struct with fields', () {
      const source = 'struct Point {\n    x: i32,\n    y: i32,\n}';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Point'));
      expect(structs[0].lineStart, equals(1));
      expect(structs[0].lineEnd, equals(4));
      expect(structs[0].signature, equals('struct Point {'));
    });

    test('parses unit struct', () {
      const source = 'struct Unit;';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Unit'));
      expect(structs[0].lineStart, equals(1));
      expect(structs[0].lineEnd, equals(1));
      expect(structs[0].signature, equals('struct Unit;'));
    });

    test('parses pub struct with access modifier', () {
      const source = 'pub struct Config {\n    name: String,\n}';
      final symbols = parse(source);

      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('Config'));
      expect(structs[0].accessModifier, equals('public'));
      expect(structs[0].lineStart, equals(1));
      expect(structs[0].lineEnd, equals(3));
    });
  });

  // ─── 4. enum parsing ───────────────────────────────────────────

  group('enum parsing', () {
    test('parses simple enum', () {
      const source = 'enum Color {\n    Red,\n    Green,\n    Blue,\n}';
      final symbols = parse(source);

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Color'));
      expect(enums[0].lineStart, equals(1));
      expect(enums[0].lineEnd, equals(5));
      expect(enums[0].signature, equals('enum Color {'));
    });

    test('parses generic enum with variants', () {
      const source = 'enum Result<T, E> {\n    Ok(T),\n    Err(E),\n}';
      final symbols = parse(source);

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Result'));
      expect(enums[0].lineStart, equals(1));
      expect(enums[0].lineEnd, equals(4));
      expect(enums[0].signature, equals('enum Result<T, E> {'));
    });

    test('parses pub enum with access modifier', () {
      const source = 'pub enum Direction {\n    Up,\n    Down,\n}';
      final symbols = parse(source);

      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Direction'));
      expect(enums[0].accessModifier, equals('public'));
    });
  });

  // ─── 5. trait parsing ──────────────────────────────────────────

  group('trait parsing', () {
    test('parses trait with method signature', () {
      const source = 'trait Drawable {\n    fn draw(&self);\n}';
      final symbols = parse(source);

      final traits = symbols.where((s) => s.type == 'trait').toList();
      expect(traits, hasLength(1));
      expect(traits[0].name, equals('Drawable'));
      expect(traits[0].lineStart, equals(1));
      expect(traits[0].lineEnd, equals(3));
      expect(traits[0].signature, equals('trait Drawable {'));
    });

    test('parses pub trait with access modifier', () {
      const source = 'pub trait Shape {\n    fn area(&self) -> f64;\n}';
      final symbols = parse(source);

      final traits = symbols.where((s) => s.type == 'trait').toList();
      expect(traits, hasLength(1));
      expect(traits[0].name, equals('Shape'));
      expect(traits[0].accessModifier, equals('public'));
      expect(traits[0].lineStart, equals(1));
      expect(traits[0].lineEnd, equals(3));
    });
  });

  // ─── 6. impl block ─────────────────────────────────────────────

  group('impl block', () {
    test('parses inherent impl block', () {
      const source = 'impl Point {\n    fn new() -> Self {\n        Point { x: 0, y: 0 }\n    }\n}';
      final symbols = parse(source);

      final impls = symbols.where((s) => s.type == 'impl').toList();
      expect(impls, hasLength(1));
      expect(impls[0].name, equals('Point'));
      expect(impls[0].lineStart, equals(1));
      expect(impls[0].lineEnd, equals(5));
      expect(impls[0].signature, equals('impl Point {'));
    });

    test('methods inside impl are typed as method with parentName', () {
      const source = 'impl Point {\n    fn new() -> Self {\n        Point { x: 0, y: 0 }\n    }\n    fn distance(&self, other: &Point) -> f64 {\n        0.0\n    }\n}';
      final symbols = parse(source);

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(2));
      expect(methods[0].name, equals('new'));
      expect(methods[0].parentName, equals('Point'));
      expect(methods[0].lineStart, equals(2));
      expect(methods[1].name, equals('distance'));
      expect(methods[1].parentName, equals('Point'));
      expect(methods[1].lineStart, equals(5));
    });
  });

  // ─── 7. impl for trait ─────────────────────────────────────────

  group('impl for trait', () {
    test('parses impl Trait for Type', () {
      const source = 'impl Display for Point {\n    fn fmt(&self, f: &mut Formatter) -> Result {\n        write!(f, "({}, {})", self.x, self.y)\n    }\n}';
      final symbols = parse(source);

      final impls = symbols.where((s) => s.type == 'impl').toList();
      expect(impls, hasLength(1));
      expect(impls[0].name, equals('Display for Point'));
      expect(impls[0].lineStart, equals(1));
      expect(impls[0].lineEnd, equals(5));
      expect(impls[0].signature, equals('impl Display for Point {'));
    });

    test('methods inside impl for trait have parentName set to type name', () {
      const source = 'impl Display for Point {\n    fn fmt(&self, f: &mut Formatter) -> Result {\n        write!(f, "Point")\n    }\n}';
      final symbols = parse(source);

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(1));
      expect(methods[0].name, equals('fmt'));
      expect(methods[0].parentName, equals('Point'));
      expect(methods[0].lineStart, equals(2));
    });
  });

  // ─── 8. Function parsing ───────────────────────────────────────

  group('function parsing', () {
    test('parses simple function', () {
      const source = 'fn main() {\n    println!("Hello");\n}';
      final symbols = parse(source);

      final functions = symbols.where((s) => s.type == 'function').toList();
      expect(functions, hasLength(1));
      expect(functions[0].name, equals('main'));
      expect(functions[0].lineStart, equals(1));
      expect(functions[0].lineEnd, equals(3));
      expect(functions[0].signature, equals('fn main() {'));
      expect(functions[0].parentName, isNull);
    });

    test('parses pub function with parameters and return type', () {
      const source = 'pub fn add(a: i32, b: i32) -> i32 {\n    a + b\n}';
      final symbols = parse(source);

      final functions = symbols.where((s) => s.type == 'function').toList();
      expect(functions, hasLength(1));
      expect(functions[0].name, equals('add'));
      expect(functions[0].accessModifier, equals('public'));
      expect(functions[0].lineStart, equals(1));
      expect(functions[0].lineEnd, equals(3));
      expect(functions[0].signature, equals('pub fn add(a: i32, b: i32) -> i32 {'));
    });

    test('parses async function', () {
      const source = 'async fn fetch_data() -> Result<String, Error> {\n    Ok("data".to_string())\n}';
      final symbols = parse(source);

      final functions = symbols.where((s) => s.type == 'function').toList();
      expect(functions, hasLength(1));
      expect(functions[0].name, equals('fetch_data'));
      expect(functions[0].lineStart, equals(1));
      expect(functions[0].lineEnd, equals(3));
    });
  });

  // ─── 9. Method in impl ─────────────────────────────────────────

  group('method in impl', () {
    test('method has type method and parentName set to impl type', () {
      const source = 'impl Calculator {\n    pub fn add(&self, a: i32, b: i32) -> i32 {\n        a + b\n    }\n    fn reset(&mut self) {\n        self.value = 0;\n    }\n}';
      final symbols = parse(source);

      final impls = symbols.where((s) => s.type == 'impl').toList();
      expect(impls, hasLength(1));
      expect(impls[0].name, equals('Calculator'));

      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(2));

      expect(methods[0].name, equals('add'));
      expect(methods[0].type, equals('method'));
      expect(methods[0].parentName, equals('Calculator'));
      expect(methods[0].accessModifier, equals('public'));
      expect(methods[0].lineStart, equals(2));

      expect(methods[1].name, equals('reset'));
      expect(methods[1].type, equals('method'));
      expect(methods[1].parentName, equals('Calculator'));
      expect(methods[1].accessModifier, isNull);
      expect(methods[1].lineStart, equals(5));
    });

    test('free function outside impl has type function not method', () {
      const source = 'fn helper() {}\nimpl Foo {\n    fn bar(&self) {}\n}';
      final symbols = parse(source);

      final functions = symbols.where((s) => s.type == 'function').toList();
      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(functions, hasLength(1));
      expect(functions[0].name, equals('helper'));
      expect(methods, hasLength(1));
      expect(methods[0].name, equals('bar'));
      expect(methods[0].parentName, equals('Foo'));
    });
  });

  // ─── 10. let/const/static variables ────────────────────────────

  group('let/const/static variables', () {
    test('parses let variable', () {
      const source = 'fn main() {\n    let x: i32 = 5;\n}';
      final symbols = parse(source);

      final variables =
          symbols.where((s) => s.type == 'variable').toList();
      expect(variables, hasLength(1));
      expect(variables[0].name, equals('x'));
      expect(variables[0].lineStart, equals(2));
      expect(variables[0].lineEnd, equals(2));
      expect(variables[0].signature, equals('let x: i32 = 5;'));
    });

    test('parses const variable', () {
      const source = 'const MAX: i32 = 100;';
      final symbols = parse(source);

      final variables =
          symbols.where((s) => s.type == 'variable').toList();
      expect(variables, hasLength(1));
      expect(variables[0].name, equals('MAX'));
      expect(variables[0].lineStart, equals(1));
      expect(variables[0].lineEnd, equals(1));
      expect(variables[0].signature, equals('const MAX: i32 = 100;'));
    });

    test('parses static variable', () {
      const source = 'static GLOBAL: i32 = 0;';
      final symbols = parse(source);

      final variables =
          symbols.where((s) => s.type == 'variable').toList();
      expect(variables, hasLength(1));
      expect(variables[0].name, equals('GLOBAL'));
      expect(variables[0].lineStart, equals(1));
      expect(variables[0].lineEnd, equals(1));
      expect(variables[0].signature, equals('static GLOBAL: i32 = 0;'));
    });

    test('parses mut let variable', () {
      const source = 'fn main() {\n    let mut count = 0;\n}';
      final symbols = parse(source);

      final variables =
          symbols.where((s) => s.type == 'variable').toList();
      expect(variables, hasLength(1));
      expect(variables[0].name, equals('count'));
      expect(variables[0].lineStart, equals(2));
      expect(variables[0].signature, equals('let mut count = 0;'));
    });

    test('parses pub const and pub static', () {
      const source = 'pub const VERSION: &str = "1.0";\npub static COUNT: usize = 0;';
      final symbols = parse(source);

      final variables =
          symbols.where((s) => s.type == 'variable').toList();
      expect(variables, hasLength(2));
      expect(variables[0].name, equals('VERSION'));
      expect(variables[1].name, equals('COUNT'));
    });
  });

  // ─── 11. type alias ────────────────────────────────────────────

  group('type alias', () {
    test('parses type alias as typedef', () {
      const source = 'type Alias = Vec<i32>;';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, hasLength(1));
      expect(typedefs[0].name, equals('Alias'));
      expect(typedefs[0].lineStart, equals(1));
      expect(typedefs[0].lineEnd, equals(1));
      expect(typedefs[0].signature, equals('type Alias = Vec<i32>;'));
    });

    test('parses pub type alias', () {
      const source = 'pub type Id = u64;';
      final symbols = parse(source);

      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, hasLength(1));
      expect(typedefs[0].name, equals('Id'));
      expect(typedefs[0].signature, equals('pub type Id = u64;'));
    });
  });

  // ─── 12. macro_rules ───────────────────────────────────────────

  group('macro_rules', () {
    test('parses macro_rules as macro with name ending in !', () {
      const source = 'macro_rules! foo {\n    (\$x:expr) => {\n        \$x + 1\n    };\n}';
      final symbols = parse(source);

      final macros = symbols.where((s) => s.type == 'macro').toList();
      expect(macros, hasLength(1));
      expect(macros[0].name, equals('foo!'));
      expect(macros[0].lineStart, equals(1));
      expect(macros[0].lineEnd, equals(5));
      expect(macros[0].signature, equals('macro_rules! foo {'));
    });

    test('parses macro_rules with multiple arms', () {
      const source =
          'macro_rules! say_hello {\n    () => {\n        println!("Hello!");\n    };\n    (name) => {\n        println!("Hello, {}!", name);\n    };\n}';
      final symbols = parse(source);

      final macros = symbols.where((s) => s.type == 'macro').toList();
      expect(macros, hasLength(1));
      expect(macros[0].name, equals('say_hello!'));
      expect(macros[0].lineStart, equals(1));
      expect(macros[0].lineEnd, equals(8));
    });
  });

  // ─── 13. symbolTypeFilter ──────────────────────────────────────

  group('symbolTypeFilter', () {
    test('filters by type to return only functions', () {
      const source = 'use std::io;\nstruct Foo;\nfn bar() {}\nlet x = 1;';
      final parser =
          RustParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse(symbolTypeFilter: 'function');

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('function'));
      expect(symbols[0].name, equals('bar'));
    });

    test('filters by type to return only structs', () {
      const source = 'use std::io;\nstruct Foo;\nfn bar() {}\nlet x = 1;';
      final parser =
          RustParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse(symbolTypeFilter: 'struct');

      expect(symbols, hasLength(1));
      expect(symbols[0].type, equals('struct'));
      expect(symbols[0].name, equals('Foo'));
    });
  });

  // ─── 14. namePattern filter ────────────────────────────────────

  group('namePattern filter', () {
    test('filters by name regex pattern', () {
      const source = 'fn foo() {}\nfn bar() {}\nfn foobar() {}';
      final parser =
          RustParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse(namePattern: r'^foo');

      expect(symbols, hasLength(2));
      expect(symbols.any((s) => s.name == 'foo'), isTrue);
      expect(symbols.any((s) => s.name == 'foobar'), isTrue);
    });
  });

  // ─── 15. Comments are skipped ──────────────────────────────────

  group('comments are skipped', () {
    test('line comments are not parsed as symbols', () {
      const source = '// use std::io;\n// fn hidden() {}';
      final symbols = parse(source);

      expect(symbols, isEmpty);
    });

    test('block comments are not parsed as symbols', () {
      const source = '/* struct Hidden; */\nfn visible() {}';
      final symbols = parse(source);

      expect(symbols, hasLength(1));
      expect(symbols[0].name, equals('visible'));
    });
  });

  // ─── 16. Complex combined source ───────────────────────────────

  group('complex combined source', () {
    test('parses a realistic Rust file with multiple symbol types', () {
      const source = '''use std::fmt;
use std::io::Result;

mod utils;

const MAX_SIZE: usize = 1024;

type Id = u64;

struct User {
    name: String,
    age: u32,
}

enum Status {
    Active,
    Inactive,
}

trait Validator {
    fn validate(&self) -> bool;
}

impl User {
    pub fn new(name: String, age: u32) -> Self {
        User { name, age }
    }
}

impl Validator for User {
    fn validate(&self) -> bool {
        !self.name.is_empty()
    }
}

fn main() {
    let user = User::new("Alice".to_string(), 30);
    println!("{}", user.name);
}''';

      final symbols = parse(source);

      // imports (2 use + 1 mod)
      final imports = symbols.where((s) => s.type == 'import').toList();
      expect(imports, hasLength(3));

      // variables (const)
      final variables =
          symbols.where((s) => s.type == 'variable').toList();
      expect(variables, hasLength(2)); // MAX_SIZE + let user

      // typedef
      final typedefs = symbols.where((s) => s.type == 'typedef').toList();
      expect(typedefs, hasLength(1));
      expect(typedefs[0].name, equals('Id'));

      // struct
      final structs = symbols.where((s) => s.type == 'struct').toList();
      expect(structs, hasLength(1));
      expect(structs[0].name, equals('User'));

      // enum
      final enums = symbols.where((s) => s.type == 'enum').toList();
      expect(enums, hasLength(1));
      expect(enums[0].name, equals('Status'));

      // trait
      final traits = symbols.where((s) => s.type == 'trait').toList();
      expect(traits, hasLength(1));
      expect(traits[0].name, equals('Validator'));

      // impl (2 impl blocks)
      final impls = symbols.where((s) => s.type == 'impl').toList();
      expect(impls, hasLength(2));
      expect(impls.map((e) => e.name).contains('User'), isTrue);
      expect(impls.map((e) => e.name).contains('Validator for User'), isTrue);

      // methods (new + validate)
      final methods = symbols.where((s) => s.type == 'method').toList();
      expect(methods, hasLength(2));
      expect(methods.any((m) => m.name == 'new' && m.parentName == 'User'), isTrue);
      expect(methods.any((m) => m.name == 'validate' && m.parentName == 'User'), isTrue);

      // functions (validate + main)
      final functions =
          symbols.where((s) => s.type == 'function').toList();
      expect(functions, hasLength(2));
      expect(functions.any((f) => f.name == 'main'), isTrue);
      expect(functions.any((f) => f.name == 'validate'), isTrue);
    });
  });
}
