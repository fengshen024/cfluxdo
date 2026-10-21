/// 全形态扫描:编辑态(toInlines forEditing)渲染投影的坐标双射性。
///
/// 编辑器光标链路:点击 → RenderParagraph offset(渲染空间)→
/// contentOffsetForRender → 编辑 offset → 渲染光标时再
/// renderOffsetForContent 回渲染空间。任何形态破坏「content→render→content
/// 恒等」或单调性,表现就是"点击的位置不是光标落下的位置"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';
import 'package:fluxdo_render/src/selection/projection_builder.dart';

void main() {
  // 每个用例:名称 + 编辑内容。atomInterior = 渲染层是单 WidgetSpan 原子
  // 的 mark 区间**内部**偏移(开区间):这些位置在渲染空间无法表达,
  // 光标坍缩到原子边界是固有几何,round-trip 恒等豁免(单调性仍必须)。
  final atomInterior = <String, Set<int>>{
    '上标': {2, 3},
    '下标': {2, 3},
  };

  final cases = <String, EditableTextContent>{
    '纯文本': EditableTextContent(text: 'hello 你好'),
    '删除线': EditableTextContent(
      text: 'ab123cd',
      marks: const [MarkSpan(start: 2, end: 5, kind: MarkKind.lineThrough)],
    ),
    '行内代码': EditableTextContent(
      text: 'a code b',
      marks: const [MarkSpan(start: 2, end: 6, kind: MarkKind.inlineCode)],
    ),
    '上标': EditableTextContent(
      text: 'abcdef',
      marks: const [MarkSpan(start: 1, end: 4, kind: MarkKind.superscript)],
    ),
    '下标': EditableTextContent(
      text: 'abcdef',
      marks: const [MarkSpan(start: 1, end: 4, kind: MarkKind.subscript)],
    ),
    'small': EditableTextContent(
      text: 'abcdef',
      marks: const [MarkSpan(start: 1, end: 4, kind: MarkKind.smallStyle)],
    ),
    'kbd': EditableTextContent(
      text: 'abcdef',
      marks: const [MarkSpan(start: 1, end: 4, kind: MarkKind.monospaceStyle)],
    ),
    '链接': EditableTextContent(
      text: 'ab链接cd',
      marks: const [
        MarkSpan(start: 2, end: 4, kind: MarkKind.link, attr: 'https://x.com'),
      ],
    ),
    '行内剧透': EditableTextContent(
      text: 'ab秘密cd',
      marks: const [MarkSpan(start: 2, end: 4, kind: MarkKind.spoilerInline)],
    ),
    '字号': EditableTextContent(
      text: 'abcdef',
      marks: const [
        MarkSpan(start: 1, end: 4, kind: MarkKind.size, attr: '150'),
      ],
    ),
    '颜色': EditableTextContent(
      text: 'abcdef',
      marks: const [
        MarkSpan(start: 1, end: 4, kind: MarkKind.textColor, attr: '#ff0000'),
      ],
    ),
    'emoji 原子': EditableTextContent(text: 'ab￼cd', atoms: const {
      2: EmojiRun(name: 'smile', url: 'u'),
    }),
    'mention 原子': EditableTextContent(text: 'ab￼cd', atoms: const {
      2: MentionRun(username: 'arch_linux', href: '/u/x'),
    }),
    '软换行': EditableTextContent(text: 'ab\ncd'),
    '长串(软换行注入)': EditableTextContent(
      text: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 后缀',
    ),
    '上标+删除线组合': EditableTextContent(
      text: 'x2y and more',
      marks: const [
        MarkSpan(start: 1, end: 2, kind: MarkKind.superscript),
        MarkSpan(start: 4, end: 7, kind: MarkKind.lineThrough),
      ],
    ),
  };

  for (final entry in cases.entries) {
    test('映射双射性:${entry.key}', () {
      final content = entry.value;
      final proj = buildInlineProjection(
        content.toInlines(forEditing: true),
      );
      final interior = atomInterior[entry.key] ?? const <int>{};
      // 契约 1:内容空间总长 == 编辑文本长
      expect(proj.contentLength, content.length,
          reason: 'contentLength 应等于编辑文本长度\nentries=${proj.entries}');
      // 契约 2:content → render → content 恒等(光标往返不漂移);
      // 原子内部偏移豁免恒等(渲染空间表达不了,坍缩到边界),但坍缩
      // 结果必须仍在 [0, length] 且映射单调。
      final issues = <String>[];
      var prevRender = -1;
      for (var c = 0; c <= content.length; c++) {
        final r = proj.renderOffsetForContent(c);
        final back = proj.contentOffsetForRender(r);
        if (back != c && !interior.contains(c)) {
          issues.add('content $c -> render $r -> content $back (≠ $c)');
        }
        if (back < 0 || back > content.length) {
          issues.add('content $c -> render $r -> content $back 越界');
        }
        if (r < prevRender) {
          issues.add('content $c -> render $r 非单调(前值 $prevRender)');
        }
        prevRender = r;
      }
      expect(issues, isEmpty,
          reason: 'entries=${proj.entries}\n${issues.join('\n')}');
    });
  }
}
