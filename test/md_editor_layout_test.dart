import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ai_vtuber_agent/l10n/app_localizations.dart';
import 'package:ai_vtuber_agent/providers/appearance_provider.dart';
import 'package:ai_vtuber_agent/widgets/md_markdown_editor.dart';

/// 用户反馈的布局问题验证（2026-08-02）：
/// 1. 中间编辑区与右侧 AI 面板重叠（不是挨着的）
/// 2. 右侧上下拖拽滚动条滑块不显示
/// 3. 打开文件过多时上方页选项卡被 AI 面板遮挡
Widget _wrap(Widget child) {
  return ChangeNotifierProvider<AppearanceProvider>(
    create: (_) => AppearanceProvider(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// 模拟 MarkdownTextScreen 三栏：左栏 350 + 分割条 5 + 编辑器(Expanded) + 分割条 5 + AI 面板 440
Widget _threePane(Widget editor) {
  return Row(
    children: [
      const SizedBox(width: 350, child: ColoredBox(color: Color(0xFF333333))),
      const SizedBox(width: 5),
      Expanded(child: editor),
      const SizedBox(width: 5),
      const SizedBox(width: 440, child: ColoredBox(color: Color(0xFF880000))),
    ],
  );
}

void main() {
  testWidgets('编辑模式：编辑器与 AI 面板不重叠', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longText =
        List.generate(80, (i) => '第 $i 行内容，用于撑高编辑器内容。').join('\n');
    final ctrl = TextEditingController(text: longText);
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(_threePane(
      MdMarkdownEditor(
        tabs: [
          MdOpenTab(
            path: 'README.md',
            title: 'README.md',
            content: longText,
            original: longText,
          ),
        ],
        activeTabPath: 'README.md',
        previewMode: false,
        controller: ctrl,
        onSelectTab: (_) {},
        onCloseTab: (_) {},
        onTogglePreview: () {},
      ),
    )));
    await tester.pumpAndSettle();

    // 1) 无 Flex overflow 等布局异常
    expect(tester.takeException(), isNull, reason: '不应有布局异常（重叠/溢出）');

    // 2) 编辑器右边界 <= AI 面板（深红）左边界：两者相邻不重叠
    final editorBox = tester.getRect(find.byType(MdMarkdownEditor));
    final aiPanelBox = tester.getRect(find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF880000)));
    expect(
      editorBox.right,
      lessThanOrEqualTo(aiPanelBox.left + 0.01),
      reason:
          '编辑器右边界 ${editorBox.right} 应 <= AI 面板左边界 ${aiPanelBox.left}'
          '（当前重叠 ${(editorBox.right - aiPanelBox.left).toStringAsFixed(1)}px）',
    );

    // 3) 编辑器左边界 >= 左栏（深灰）右边界
    final leftPaneBox = tester.getRect(find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF333333)));
    expect(editorBox.left, greaterThanOrEqualTo(leftPaneBox.right - 0.01));
  });

  testWidgets('多 Tab：Tab 栏不溢出到 AI 面板', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tabs = [
      for (var i = 0; i < 12; i++)
        MdOpenTab(
          path: 'very_long_file_name_$i.md',
          title: 'very_long_file_name_$i.md',
          content: 'content $i',
          original: 'content $i',
        ),
    ];
    final ctrl = TextEditingController(text: 'content 0');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(_threePane(
      MdMarkdownEditor(
        tabs: tabs,
        activeTabPath: tabs.first.path,
        previewMode: false,
        controller: ctrl,
        onSelectTab: (_) {},
        onCloseTab: (_) {},
        onTogglePreview: () {},
      ),
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '多 Tab 不应溢出');
  });

  testWidgets('长内容：垂直滚动条 controller 已 attach 且可滚动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longText = List.generate(300, (i) => 'line $i').join('\n');
    final ctrl = TextEditingController(text: longText);
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(_threePane(
      MdMarkdownEditor(
        tabs: [
          MdOpenTab(
            path: 'a.md',
            title: 'a.md',
            content: longText,
            original: longText,
          ),
        ],
        activeTabPath: 'a.md',
        previewMode: false,
        controller: ctrl,
        onSelectTab: (_) {},
        onCloseTab: (_) {},
        onTogglePreview: () {},
      ),
    )));
    await tester.pumpAndSettle();

    // 应有水平 + 垂直两个 Scrollbar
    final scrollbars =
        tester.widgetList<Scrollbar>(find.byType(Scrollbar)).toList();
    expect(scrollbars.length, greaterThanOrEqualTo(2),
        reason: '应有水平+垂直两个 Scrollbar');

    var vAttached = false;
    var vScrollable = false;
    for (final sb in scrollbars) {
      final c = sb.controller;
      if (c == null) continue;
      if (c.hasClients && c.position.axis == Axis.vertical) {
        vAttached = true;
        if (c.position.maxScrollExtent > 0) vScrollable = true;
      }
    }
    expect(vAttached, isTrue,
        reason: '垂直 Scrollbar 的 controller 必须已 attach（否则 thumb 不渲染）');
    expect(vScrollable, isTrue, reason: '300 行内容应可垂直滚动');
  });
}
