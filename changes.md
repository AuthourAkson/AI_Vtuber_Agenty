1. 真正实现“圆角桌面窗口”的关键，不是 Flutter Widget 的 `borderRadius`。
   
   而是：
   核心条件
   ====
   
       无边框窗口（Frameless Window）
   
   只有窗口本身变成：
       自定义窗口
   
   Windows 11 才会给你：
   * 圆角
   * 现代阴影
   * 类似 VSCode / Cursor 的效果
   
   否则你永远是：
       Win32 默认矩形窗口
   
   * * *
   
   你现在已经安装了：
   =========
   
       window_managerbitsdojo_window
   
   所以已经够了。
   
   * * *
   
   正确实现步骤（非常重要）
   ============
   
   * * *
   
   一、main.dart
   ===========
   
   你的 main.dart 应该改成：
       import 'dart:io';import 'package:flutter/material.dart';import 'package:bitsdojo_window/bitsdojo_window.dart';void main() async {  WidgetsFlutterBinding.ensureInitialized();  runApp(const MyApp());  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {    doWhenWindowReady(() {      const initialSize = Size(1400, 900);      appWindow.minSize = const Size(1000, 700);      appWindow.size = initialSize;      appWindow.alignment = Alignment.center;      appWindow.title = "AI VTuber Agent";      appWindow.show();    });  }}
   
   * * *
   
   二、修改 windows/runner/main.cpp（最关键）
   =================================
   
   打开：
       windows/runner/main.cpp
   
   * * *
   
   添加 include
   ----------
   
   找到：
       #include <flutter/dart_project.h>
   
   下面加：
       #include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
   
   * * *
   
   三、添加 frameless 配置
   =================
   
   找到：
       FlutterWindow window(project);
   
   在下面添加：
       auto bdw = bitsdojo_window_configure(    BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);
   
   * * *
   
   四、运行后效果
   =======
   
   你会发现：
   
   * 标题栏消失
   * 系统边框消失
   * Windows 11 自动圆角
   * 更像 IDE
   
   * * *
   
   五、但这时会出现一个问题
   ============
   
   因为：
       系统标题栏没了
   
   所以：
   
   * 无法拖动窗口
   * 没有关闭按钮
   * 没有最大化按钮
   
   你必须自己做标题栏。
   
   * * *
   
   六、自定义标题栏（推荐）
   ============
   
   创建：
       lib/widgets/window_title_bar.dart
   
   内容：
       import 'package:flutter/material.dart';import 'package:bitsdojo_window/bitsdojo_window.dart';class WindowTitleBar extends StatelessWidget {  const WindowTitleBar({super.key});  @override  Widget build(BuildContext context) {    return Container(      height: 46,      color: const Color(0xFF1E1E1E),      child: Row(        children: [          Expanded(            child: MoveWindow(),          ),          MinimizeWindowButton(),          MaximizeWindowButton(),          CloseWindowButton(),        ],      ),    );  }}
   
   * * *
   
   七、在页面顶部使用
   =========
   
   例如：
       Column(  children: [    const WindowTitleBar(),    Expanded(      child: YourMainContent(),    ),  ],)
   
   * * *
   
   八、如果你想更像 Cursor / ChatGPT Desktop
   =================================
   
   推荐：
   整个 Scaffold 做圆角裁剪
   -----------------
   
   例如：
       ClipRRect(  borderRadius: BorderRadius.circular(16),  child: Scaffold(    backgroundColor: const Color(0xFF181818),    body: ...  ),)
   
   * * *
   
   九、为什么别人窗口“特别丝滑”
   ===============
   
   因为他们还加了：
   
   | 效果          | 技术              |
   | ----------- | --------------- |
   | Acrylic 毛玻璃 | flutter_acrylic |
   | Mica        | flutter_acrylic |
   | 阴影          | DWM             |
   | 无边框         | bitsdojo_window |
   | 深色主题        | Material3       |
   | Sidebar     | 自定义布局           |
   
   * * *
   
   十、如果你还想实现：
   ==========
   
   * Win11 毛玻璃
   * 半透明背景
   * Claude Desktop 风格
   * Cursor 风格
   * Live2D 悬浮透明窗口
   
   下一步再接：
       flutter_acrylic
   
   即可。
   
   * * *
   
   十一、一个非常关键的现实问题
   ==============
   
   如果你：
       只是给 Widget 加 borderRadius
   
   而不做：
       frameless window
   
   那么：
   外层窗口仍然是矩形
   ---------
   
   你会看到：
       里面圆角外面黑边矩形
   
   这是很多 Flutter 桌面项目“假圆角”的来源。
   
   * * *
   
   十二、所以真正的完整链路是
   =============
   
       bitsdojo_window    ↓frameless    ↓Windows 11 DWM    ↓系统圆角    ↓再配合 Flutter 内部 borderRadius
   
   这样才是现代桌面 UI。
