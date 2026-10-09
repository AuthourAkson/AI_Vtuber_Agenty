import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/java_parser.dart';
import 'package:auakagent/src/agent/tool/builtin/symbol_parser/symbol_parser.dart';

void main() {
  // ─── 1. Package declaration ──────────────────────────────────────

  group('package declaration', () {
    test('parses package declaration as type import', () {
      const source = 'package com.example;\n\npublic class Foo {}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final pkg = symbols.firstWhere(
        (s) => s.type == 'import' && s.name == 'com.example',
      );
      expect(pkg.name, 'com.example');
      expect(pkg.type, 'import');
      expect(pkg.lineStart, 1);
      expect(pkg.lineEnd, 1);
      expect(pkg.signature, 'package com.example;');
    });
  });

  // ─── 2. Import parsing ───────────────────────────────────────────

  group('import parsing', () {
    test('parses regular import', () {
      const source = 'import java.util.List;\n\npublic class Foo {}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final imp = symbols.firstWhere(
        (s) => s.type == 'import' && s.name.contains('java.util.List'),
      );
      expect(imp.name, 'import java.util.List');
      expect(imp.type, 'import');
      expect(imp.lineStart, 1);
      expect(imp.signature, 'import java.util.List;');
    });

    test('parses static import', () {
      const source = 'import static java.util.Math.PI;\n\npublic class Foo {}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final imp = symbols.firstWhere(
        (s) => s.type == 'import' && s.name.contains('static'),
      );
      expect(imp.name, 'import static java.util.Math.PI');
      expect(imp.type, 'import');
      expect(imp.lineStart, 1);
    });
  });

  // ─── 3. Class parsing ────────────────────────────────────────────

  group('class parsing', () {
    test('parses a public class', () {
      const source = 'public class Foo {\n  private int x;\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final cls = symbols.firstWhere((s) => s.type == 'class');
      expect(cls.name, 'Foo');
      expect(cls.type, 'class');
      expect(cls.lineStart, 1);
      expect(cls.lineEnd, 3);
    });

    test('parses an abstract class', () {
      const source = 'abstract class Shape {\n  double area();\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final cls = symbols.firstWhere((s) => s.type == 'class');
      expect(cls.name, 'Shape');
      expect(cls.type, 'class');
      expect(cls.lineStart, 1);
    });

    test('parses a final class', () {
      const source = 'final class Immutable {\n  private final int value;\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final cls = symbols.firstWhere((s) => s.type == 'class');
      expect(cls.name, 'Immutable');
      expect(cls.type, 'class');
      expect(cls.lineStart, 1);
    });
  });

  // ─── 4. Interface parsing ────────────────────────────────────────

  group('interface parsing', () {
    test('parses a public interface', () {
      const source = 'public interface Foo {\n  void bar();\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final iface = symbols.firstWhere((s) => s.type == 'interface');
      expect(iface.name, 'Foo');
      expect(iface.type, 'interface');
      expect(iface.lineStart, 1);
      expect(iface.lineEnd, 3);
    });
  });

  // ─── 5. Enum parsing ─────────────────────────────────────────────

  group('enum parsing', () {
    test('parses a public enum', () {
      const source = 'public enum Color {\n  RED,\n  GREEN\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final enm = symbols.firstWhere((s) => s.type == 'enum');
      expect(enm.name, 'Color');
      expect(enm.type, 'enum');
      expect(enm.lineStart, 1);
      expect(enm.lineEnd, 4);
    });
  });

  // ─── 6. @interface annotation ────────────────────────────────────

  group('@interface annotation', () {
    test('parses a public @interface annotation', () {
      const source = 'public @interface MyAnnotation {\n  String value() default "";\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final ann = symbols.firstWhere((s) => s.type == 'annotation');
      expect(ann.name, '@MyAnnotation');
      expect(ann.type, 'annotation');
      expect(ann.lineStart, 1);
      expect(ann.lineEnd, 3);
    });
  });

  // ─── 7. Method parsing ───────────────────────────────────────────

  group('method parsing', () {
    test('parses a public void method inside a class', () {
      const source =
          'public class Foo {\n  public void hello() {\n    System.out.println("hi");\n  }\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final method = symbols.firstWhere(
        (s) => s.name == 'hello' && s.type == 'method',
      );
      expect(method.name, 'hello');
      expect(method.type, 'method');
      expect(method.accessModifier, 'public');
      expect(method.parentName, 'Foo');
      expect(method.lineStart, 2);
    });

    test('parses a private static int method inside a class', () {
      const source =
          'public class Foo {\n  private static int bar() {\n    return 42;\n  }\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final method = symbols.firstWhere(
        (s) => s.name == 'bar' && s.type == 'method',
      );
      expect(method.name, 'bar');
      expect(method.type, 'method');
      expect(method.accessModifier, 'private');
      expect(method.parentName, 'Foo');
    });
  });

  // ─── 8. Constructor parsing ──────────────────────────────────────

  group('constructor parsing', () {
    test('parses a no-arg package-private constructor', () {
      // The parser recognizes constructors when the declaration line
      // contains no spaces (e.g. 'Foo(){}' not 'Foo(String name)').
      const source = 'public class Foo {\nFoo(){}\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final ctor = symbols.firstWhere(
        (s) => s.type == 'constructor' && s.name == 'Foo',
      );
      expect(ctor.name, 'Foo');
      expect(ctor.type, 'constructor');
      expect(ctor.accessModifier, isNull);
      expect(ctor.parentName, 'Foo');
      expect(ctor.lineStart, 2);
    });
  });

  // ─── 9. Getter recognition ───────────────────────────────────────

  group('getter recognition', () {
    test('recognizes getName() as a getter', () {
      const source =
          'public class Foo {\n  private String name;\n  public String getName() {\n    return name;\n  }\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final getter = symbols.firstWhere(
        (s) => s.name == 'getName' && s.type == 'getter',
      );
      expect(getter.name, 'getName');
      expect(getter.type, 'getter');
      expect(getter.accessModifier, 'public');
      expect(getter.parentName, 'Foo');
    });

    test('recognizes isEnabled() as a getter (is-prefix)', () {
      const source =
          'public class Foo {\n  private boolean enabled;\n  public boolean isEnabled() {\n    return enabled;\n  }\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final getter = symbols.firstWhere(
        (s) => s.name == 'isEnabled' && s.type == 'getter',
      );
      expect(getter.name, 'isEnabled');
      expect(getter.type, 'getter');
    });
  });

  // ─── 10. Setter recognition ──────────────────────────────────────

  group('setter recognition', () {
    test('recognizes setName() as a setter', () {
      const source =
          'public class Foo {\n  private String name;\n  public void setName(String name) {\n    this.name = name;\n  }\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final setter = symbols.firstWhere(
        (s) => s.name == 'setName' && s.type == 'setter',
      );
      expect(setter.name, 'setName');
      expect(setter.type, 'setter');
      expect(setter.accessModifier, 'public');
      expect(setter.parentName, 'Foo');
    });
  });

  // ─── 11. Field parsing ───────────────────────────────────────────

  group('field parsing', () {
    test('parses a private int field', () {
      const source = 'public class Foo {\n  private int count;\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final field = symbols.firstWhere(
        (s) => s.name == 'count' && s.type == 'variable',
      );
      expect(field.name, 'count');
      expect(field.type, 'variable');
      expect(field.accessModifier, 'private');
      expect(field.lineStart, 2);
    });

    test('parses a public static final String field', () {
      const source =
          'public class Foo {\n  public static final String NAME = "x";\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      final field = symbols.firstWhere(
        (s) => s.name == 'NAME' && s.type == 'variable',
      );
      expect(field.name, 'NAME');
      expect(field.type, 'variable');
      expect(field.accessModifier, 'public');
      expect(field.lineStart, 2);
    });
  });

  // ─── 12. Comment filtering ───────────────────────────────────────

  group('comment filtering', () {
    test('ignores symbols inside single-line comments', () {
      const source =
          '// public class CommentedOut {}\npublic class RealClass {}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      // CommentedOut should not appear
      expect(
        symbols.any((s) => s.name == 'CommentedOut'),
        false,
        reason: 'Commented-out class should not be parsed',
      );
      // RealClass should appear
      expect(
        symbols.any((s) => s.name == 'RealClass' && s.type == 'class'),
        true,
      );
    });

    test('ignores symbols inside block comments', () {
      const source =
          '/* public class CommentedOut {} */\npublic class RealClass {}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      expect(
        symbols.any((s) => s.name == 'CommentedOut'),
        false,
        reason: 'Block-commented class should not be parsed',
      );
      expect(
        symbols.any((s) => s.name == 'RealClass' && s.type == 'class'),
        true,
      );
    });

    test('ignores fields inside block comments', () {
      const source =
          'public class Foo {\n  /* private int hidden; */\n  private int visible;\n}';
      final parser = JavaParser(content: source, lines: source.split('\n'));
      final symbols = parser.parse();

      expect(
        symbols.any((s) => s.name == 'hidden'),
        false,
        reason: 'Block-commented field should not be parsed',
      );
      expect(
        symbols.any((s) => s.name == 'visible' && s.type == 'variable'),
        true,
      );
    });
  });
}
