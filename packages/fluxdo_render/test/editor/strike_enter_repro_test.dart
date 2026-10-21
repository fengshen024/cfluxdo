/// 回归:wysiwyg 软换行回车不得把行内 mark(删除线等)延续到下一行。
///
/// 翻车形态(修复前):删除线末尾回车,`\n` 被 inclusive 末端延伸吸进
/// mark;若回车后再关删除线打字,mark 区间停在 `\n` 之后,闭 `~~` 被
/// 序列化到下一行行首(`~~123  \n~~123`)—— cook 认不出闭定界符前的
/// 换行,两行全部退化成 `~~123` 字面。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';
import 'package:fluxdo_render/src/editor/model/editor_state.dart';
import 'package:fluxdo_render/src/editor/model/markdown_serializer.dart';

void main() {
  EditorState makeState() {
    final s = EditorState.fromTexts(const ['']);
    s.mode = EditorMode.wysiwyg;
    s.enterInsertsSoftBreak = true;
    s.updateSelection(EditorSelection.collapsed(
      EditorPosition(blockId: s.blocks[0].id, offset: 0),
    ));
    return s;
  }

  test('删除线打字 → 回车 → 继续打字:新行不在删除线内', () {
    final s = makeState();
    s.toggleMark(MarkKind.lineThrough);
    s.insertText('123');
    s.insertNewline();
    s.insertText('123');
    final b = s.blocks[0] as TextBlock;
    expect(b.content.text, '123\n123');
    expect(
      b.content.marks,
      [const MarkSpan(start: 0, end: 3, kind: MarkKind.lineThrough)],
    );
    expect(docToMarkdown(s.blocks), '~~123~~  \n123');
  });

  test('删除线打字 → 回车 → 工具栏不再显示删除线激活', () {
    final s = makeState();
    s.toggleMark(MarkKind.lineThrough);
    s.insertText('123');
    s.insertNewline();
    final b = s.blocks[0] as TextBlock;
    expect(b.content.marksAt(s.selection!.extent.offset),
        isNot(contains(MarkKind.lineThrough)));
  });

  test('pending 删除线未打字就回车:pending 作废,新行是普通文本', () {
    final s = makeState();
    s.insertText('123');
    s.toggleMark(MarkKind.lineThrough); // pending
    s.insertNewline();
    s.insertText('123');
    final b = s.blocks[0] as TextBlock;
    expect(b.content.marks, isEmpty);
    expect(docToMarkdown(s.blocks), '123  \n123');
  });

  test('删除线中间回车:两半各自保持删除线(合法跨行 GFM)', () {
    final s = makeState();
    s.toggleMark(MarkKind.lineThrough);
    s.insertText('1234');
    s.updateSelection(EditorSelection.collapsed(
      EditorPosition(blockId: s.blocks[0].id, offset: 2),
    ));
    s.insertNewline();
    final b = s.blocks[0] as TextBlock;
    expect(b.content.text, '12\n34');
    // 区间内插入延续样式(主流语义),`~~12  \n34~~` 是合法 GFM
    expect(
      b.content.marks,
      [const MarkSpan(start: 0, end: 5, kind: MarkKind.lineThrough)],
    );
  });

  test('分块回车(软换行关闭):新块无删除线', () {
    final s = makeState();
    s.enterInsertsSoftBreak = false;
    s.toggleMark(MarkKind.lineThrough);
    s.insertText('123');
    s.insertNewline();
    s.insertText('123');
    expect(s.blocks, hasLength(2));
    expect((s.blocks[0] as TextBlock).content.marks, hasLength(1));
    expect((s.blocks[1] as TextBlock).content.marks, isEmpty);
    expect(docToMarkdown(s.blocks), '~~123~~\n\n123');
  });
}
