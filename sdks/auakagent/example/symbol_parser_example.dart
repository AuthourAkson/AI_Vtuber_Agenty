// ============================================================================
// SymbolParser 多语言代码符号解析示例
// ============================================================================
//
// 演示如何使用 symbol_parser 模块解析多种编程语言的代码符号。
// 覆盖 8 种语言：Dart、Python、JavaScript、TypeScript、Java、Go、Rust、C/C++
//
// 运行方式：dart run example/symbol_parser_example.dart
// ============================================================================

import 'package:auakagent/auakagent.dart';

void main() {
  // ============================================================
  // 1. Dart 解析示例
  // ============================================================
  printExample(
    '1. Dart 解析示例',
    dartSource,
    DartParser(content: dartSource, lines: dartSource.split('\n')),
  );

  // ============================================================
  // 2. Python 解析示例
  // ============================================================
  printExample(
    '2. Python 解析示例',
    pythonSource,
    PythonParser(content: pythonSource, lines: pythonSource.split('\n')),
  );

  // ============================================================
  // 3. JavaScript 解析示例
  // ============================================================
  printExample(
    '3. JavaScript 解析示例',
    jsSource,
    JsTsParser(content: jsSource, lines: jsSource.split('\n')),
  );

  // ============================================================
  // 4. TypeScript 解析示例
  // ============================================================
  printExample(
    '4. TypeScript 解析示例',
    tsSource,
    JsTsParser(
      content: tsSource,
      lines: tsSource.split('\n'),
      isTypeScript: true,
    ),
  );

  // ============================================================
  // 5. Java 解析示例
  // ============================================================
  printExample(
    '5. Java 解析示例',
    javaSource,
    JavaParser(content: javaSource, lines: javaSource.split('\n')),
  );

  // ============================================================
  // 6. Go 解析示例
  // ============================================================
  printExample(
    '6. Go 解析示例',
    goSource,
    GoParser(content: goSource, lines: goSource.split('\n')),
  );

  // ============================================================
  // 7. Rust 解析示例
  // ============================================================
  printExample(
    '7. Rust 解析示例',
    rustSource,
    RustParser(content: rustSource, lines: rustSource.split('\n')),
  );

  // ============================================================
  // 8. C/C++ 解析示例
  // ============================================================
  printExample(
    '8. C/C++ 解析示例',
    cppSource,
    CCppParser(content: cppSource, lines: cppSource.split('\n')),
  );

  // ============================================================
  // 9. 过滤功能演示
  // ============================================================
  printFilterExample();

  // ============================================================
  // 10. 语言检测演示
  // ============================================================
  printLanguageDetectionExample();

  // ============================================================
  // 11. CodeSymbol 数据模型演示
  // ============================================================
  printCodeSymbolModelExample();
}

// ═══════════════════════════════════════════════════════════════
// 格式化输出工具
// ═══════════════════════════════════════════════════════════════

void printExample(String title, String source, SymbolParser parser) {
  final separator = '═' * 60;
  print('\n$separator');
  print('  $title');
  print(separator);

  // 打印带行号的源代码
  print('\n--- 源代码 ---');
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final num = (i + 1).toString().padLeft(3);
    print('  $num | ${lines[i]}');
  }

  // 解析并打印结果
  final symbols = parser.parse();
  print('\n--- 解析结果 (共 ${symbols.length} 个符号) ---');
  for (final s in symbols) {
    final parent = s.parentName != null ? ' [${s.parentName}]' : '';
    final access = s.accessModifier != null ? ' (${s.accessModifier})' : '';
    final lineRange = s.lineEnd != null
        ? '${s.lineStart}-${s.lineEnd}'
        : '${s.lineStart}-?';
    print(
      '  [${s.type.padRight(12)}] ${s.name}$parent$access  (line $lineRange)',
    );
    if (s.signature != null && s.signature!.isNotEmpty) {
      print('    ${s.signature}');
    }
  }
}

void printFilterExample() {
  final separator = '═' * 60;
  print('\n$separator');
  print('  9. 过滤功能演示');
  print(separator);

  final parser = DartParser(content: dartSource, lines: dartSource.split('\n'));

  // symbolTypeFilter
  print('\n--- symbolTypeFilter: 仅显示 class ---');
  final classes = parser.parse(symbolTypeFilter: 'class');
  for (final s in classes) {
    print('  [${s.type}] ${s.name}  (line ${s.lineStart}-${s.lineEnd})');
  }

  print('\n--- symbolTypeFilter: 仅显示 function ---');
  final functions = parser.parse(symbolTypeFilter: 'function');
  for (final s in functions) {
    print('  [${s.type}] ${s.name}  (line ${s.lineStart}-${s.lineEnd})');
  }

  print('\n--- symbolTypeFilter: 仅显示 import ---');
  final imports = parser.parse(symbolTypeFilter: 'import');
  for (final s in imports) {
    print('  [${s.type}] ${s.name}  (line ${s.lineStart})');
  }

  // namePattern
  print('\n--- namePattern: 名称以 "parse" 开头 ---');
  final parseSymbols = parser.parse(namePattern: r'^parse');
  for (final s in parseSymbols) {
    print('  [${s.type}] ${s.name}  (line ${s.lineStart})');
  }

  // 组合过滤
  print('\n--- 组合: type=function + name 以 "create" 开头 ---');
  final combined = parser.parse(
    symbolTypeFilter: 'function',
    namePattern: r'^create',
  );
  for (final s in combined) {
    print('  [${s.type}] ${s.name}  (line ${s.lineStart})');
  }
}

void printLanguageDetectionExample() {
  final separator = '═' * 60;
  print('\n$separator');
  print('  10. 语言检测演示');
  print(separator);

  final testPaths = [
    'src/app.dart',
    'scripts/main.py',
    'web/index.js',
    'lib/utils.ts',
    'app/Server.tsx',
    'components/Button.jsx',
    'src/Main.java',
    'cmd/main.go',
    'src/lib.rs',
    'include/types.h',
    'src/engine.cpp',
    'src/MyClass.kt',
    'ios/App.swift',
    'data/config.json',
    'README.md',
  ];

  print('\n--- detectLanguage() 文件扩展名 → 语言 ---');
  for (final path in testPaths) {
    final lang = detectLanguage(path);
    final display = languageDisplayName(lang);
    print('  ${path.padRight(25)} → ${display.padRight(12)} (${lang.id})');
  }

  print('\n--- allSymbolTypes (共 ${allSymbolTypes.length} 种) ---');
  for (final type in allSymbolTypes) {
    print('  • $type');
  }
}

void printCodeSymbolModelExample() {
  final separator = '═' * 60;
  print('\n$separator');
  print('  11. CodeSymbol 数据模型演示');
  print(separator);

  // 创建符号
  final s1 = CodeSymbol(
    name: 'MyClass',
    type: 'class',
    lineStart: 10,
    lineEnd: 50,
    signature: 'class MyClass extends Base implements Serializable {',
    accessModifier: 'public',
    parentName: null,
  );

  final s2 = CodeSymbol(
    name: 'MyClass',
    type: 'class',
    lineStart: 10,
    lineEnd: 50,
  );

  final s3 = CodeSymbol(
    name: 'OtherClass',
    type: 'class',
    lineStart: 10,
    lineEnd: 50,
  );

  print('\n--- toString() ---');
  print('  ${s1.toString()}');

  print('\n--- 相等比较 ---');
  print('  s1 == s2 (同名同类型同行): ${s1 == s2}'); // true
  print('  s1 == s3 (名称不同):       ${s1 == s3}'); // false
  print('  s1.hashCode == s2.hashCode: ${s1.hashCode == s2.hashCode}');

  print('\n--- 字段访问 ---');
  print('  name:           ${s1.name}');
  print('  type:           ${s1.type}');
  print('  lineStart:      ${s1.lineStart}');
  print('  lineEnd:        ${s1.lineEnd}');
  print('  signature:      ${s1.signature}');
  print('  accessModifier: ${s1.accessModifier}');
  print('  parentName:     ${s1.parentName}');
}

// ═══════════════════════════════════════════════════════════════
// 各语言示例源代码
// ═══════════════════════════════════════════════════════════════

const dartSource = r'''
import 'dart:async';
import 'dart:convert';

/// 用户实体类
class User {
  final String name;
  final int age;
  late final String email;

  User(this.name, this.age);

  /// 工厂构造函数
  factory User.fromJson(Map<String, dynamic> json) {
    return User(json['name'] as String, json['age'] as int);
  }

  /// 命名构造函数
  User.anonymous() : name = 'Anonymous', age = 0;

  String get displayName => '$name ($age岁)';
  set displayName(String value) => email = value;

  String greet() => 'Hello, $name!';
}

/// 用户状态枚举
enum UserStatus { active, inactive, banned }

/// 可序列化混入
mixin Serializable on User {
  Map<String, dynamic> toJson();
}

/// 字符串扩展
extension StringX on String {
  String get capitalized =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}

/// 回调类型别名
typedef UserCallback = void Function(User user);

/// 解析用户数据
Future<User> parseUser(String jsonStr) async {
  final data = jsonDecode(jsonStr) as Map<String, dynamic>;
  return User.fromJson(data);
}

/// 创建默认用户
User createDefaultUser() => User.anonymous();

/// 应用配置
const appName = 'WenzAgent';
final version = '1.0.0';
''';

const pythonSource = r'''
import os
import sys
from dataclasses import dataclass
from typing import Optional, List

@dataclass
class User:
    name: str
    age: int
    email: Optional[str] = None

    @property
    def display_name(self) -> str:
        return f"{self.name} ({self.age}岁)"

    @display_name.setter
    def display_name(self, value: str) -> None:
        self.email = value

    def greet(self) -> str:
        return f"Hello, {self.name}!"

    @staticmethod
    def create_anonymous() -> "User":
        return User(name="Anonymous", age=0)

    @classmethod
    def from_dict(cls, data: dict) -> "User":
        return cls(**data)

class UserStatus:
    ACTIVE = "active"
    INACTIVE = "inactive"
    BANNED = "banned"

async def parse_user(json_str: str) -> User:
    import json
    data = json.loads(json_str)
    return User(**data)

def create_default_user() -> User:
    return User.create_anonymous()

APP_NAME = "WenzAgent"
VERSION = "1.0.0"
''';

const jsSource = r'''
import { EventEmitter } from 'events';
import fs from 'fs';

class User {
  constructor(name, age) {
    this.name = name;
    this.age = age;
  }

  greet() {
    return `Hello, ${this.name}!`;
  }

  static createAnonymous() {
    return new User('Anonymous', 0);
  }
}

class UserStatus {
  static ACTIVE = 'active';
  static INACTIVE = 'inactive';
}

function parseUser(jsonStr) {
  const data = JSON.parse(jsonStr);
  return new User(data.name, data.age);
}

const createUser = (name, age) => new User(name, age);
const createDefaultUser = () => User.createAnonymous();

const APP_NAME = 'WenzAgent';
const VERSION = '1.0.0';
''';

const tsSource = r'''
import { EventEmitter } from 'events';

// 接口定义
interface User {
  name: string;
  age: number;
  email?: string;
}

// 类型别名
type UserCallback = (user: User) => void;
type Status = 'active' | 'inactive' | 'banned';

// 枚举
enum UserStatus {
  Active = 'active',
  Inactive = 'inactive',
  Banned = 'banned',
}

// 命名空间
namespace Utils {
  export function greet(user: User): string {
    return `Hello, ${user.name}!`;
  }
}

// 装饰器
@Component({ selector: 'app-user' })
class UserService {
  private users: User[] = [];

  constructor(private config: Config) {}

  async parseUser(jsonStr: string): Promise<User> {
    return JSON.parse(jsonStr);
  }

  get count(): number {
    return this.users.length;
  }
}

const APP_NAME: string = 'WenzAgent';
''';

const javaSource = r'''
package com.wenzagent.app;

import java.util.List;
import java.util.ArrayList;
import static java.util.Objects.requireNonNull;

public class UserService {
    private final List<User> users = new ArrayList<>();
    public static final String APP_NAME = "WenzAgent";

    public UserService() {
        // default constructor
    }

    public void addUser(User user) {
        requireNonNull(user);
        users.add(user);
    }

    public List<User> getUsers() {
        return List.copyOf(users);
    }

    public void setUsers(List<User> users) {
        this.users.clear();
        this.users.addAll(users);
    }

    public int getUserCount() {
        return users.size();
    }
}

interface Serializable {
    String toJson();
}

enum Status {
    ACTIVE, INACTIVE, BANNED
}

@interface Author {
    String value();
    String date() default "";
}
''';

const goSource = r'''
package main

import (
    "encoding/json"
    "fmt"
    "os"
)

// User 用户结构体
type User struct {
    Name  string `json:"name"`
    Age   int    `json:"age"`
    Email string `json:"email,omitempty"`
}

// UserStatus 用户状态
type UserStatus int

const (
    StatusActive   UserStatus = iota
    StatusInactive
    StatusBanned
)

// Stringer 接口
type Stringer interface {
    String() string
}

// DisplayName 别名
type DisplayName = string

func (u *User) Greet() string {
    return fmt.Sprintf("Hello, %s!", u.Name)
}

func (u *User) DisplayName() string {
    return fmt.Sprintf("%s (%d岁)", u.Name, u.Age)
}

func parseUser(jsonStr string) (*User, error) {
    var user User
    err := json.Unmarshal([]byte(jsonStr), &user)
    return &user, err
}

func createUser(name string, age int) *User {
    return &User{Name: name, Age: age}
}

var appName = "WenzAgent"
const version = "1.0.0"
''';

const rustSource = r'''
use std::collections::HashMap;
use std::fmt;

// 用户结构体
#[derive(Debug, Clone)]
pub struct User {
    pub name: String,
    pub age: u32,
    email: Option<String>,
}

// 单元结构体
pub struct Config;

// 用户状态枚举
pub enum UserStatus {
    Active,
    Inactive,
    Banned,
}

// Display trait
pub trait Display {
    fn display(&self) -> String;
}

// 为 User 实现 Display
impl Display for User {
    fn display(&self) -> String {
        format!("{} ({}岁)", self.name, self.age)
    }
}

// User 的方法
impl User {
    pub fn new(name: String, age: u32) -> Self {
        User { name, age, email: None }
    }

    pub fn greet(&self) -> String {
        format!("Hello, {}!", self.name)
    }
}

// 类型别名
type UserId = u64;

// 宏定义
macro_rules! impl_status {
    ($name:ident) => {
        impl $name {
            pub fn is_active(&self) -> bool {
                matches!(self, $name::Active)
            }
        }
    };
}

impl_status!(UserStatus);

pub fn parse_user(json_str: &str) -> Result<User, serde_json::Error> {
    serde_json::from_str(json_str)
}

const APP_NAME: &str = "WenzAgent";
static VERSION: &str = "1.0.0";

fn main() {
    let user = User::new(String::from("Alice"), 30);
    println!("{}", user.greet());
}
''';

const cppSource = r'''
#include <iostream>
#include <string>
#include <vector>
#include <map>

#define APP_NAME "WenzAgent"
#define MAX_USERS 1000
#define SQUARE(x) ((x) * (x))

using namespace std;

namespace wenzagent {

class User {
private:
    string name;
    int age;

public:
    User(string name, int age) : name(name), age(age) {}

    string getName() const { return name; }
    void setName(const string& value) { name = value; }

    string greet() const {
        return "Hello, " + name + "!";
    }

    static User createAnonymous() {
        return User("Anonymous", 0);
    }
};

struct Point {
    double x;
    double y;
    double distanceTo(const Point& other) const;
};

enum class Status {
    Active,
    Inactive,
    Banned
};

typedef void (*Callback)(const User&);

using UserList = vector<User>;

} // namespace wenzagent

int main(int argc, char** argv) {
    User user("Alice", 30);
    cout << user.greet() << endl;
    return 0;
}
''';
