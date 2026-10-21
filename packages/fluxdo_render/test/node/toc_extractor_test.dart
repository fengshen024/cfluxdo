import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/toc_extractor.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  final parser = ParagraphParser();

  /// 造服务端 cook 出来的带锚标题。
  String anchoredHeading(int level, String anchor, String text) =>
      '<h$level><a name="$anchor" class="anchor" href="#$anchor"></a>'
      '$text</h$level>';

  group('TocExtractor 提取条件', () {
    test('标题数不足 minHeadings 返回 null', () {
      final nodes = parser.parse('<h2>A</h2><h2>B</h2>');
      expect(TocExtractor.build(nodes, postId: 1), isNull);
    });

    test('h6 不入目录(对齐 DiscoTOC 选择器)', () {
      final nodes = parser.parse('<h6>A</h6><h6>B</h6><h6>C</h6>');
      expect(TocExtractor.build(nodes, postId: 1), isNull);
    });

    test('引用块内的标题不收', () {
      final nodes = parser.parse(
        '<blockquote><h2>引用里的</h2></blockquote>'
        '<h2>A</h2><h2>B</h2><h2>C</h2>',
      );
      final toc = TocExtractor.build(nodes, postId: 1)!;
      expect(toc.flat.map((e) => e.text), ['A', 'B', 'C']);
    });

    test('容器 div 内的标题提升到顶层后可收(对齐 .wrap 口径)', () {
      final nodes = parser.parse(
        '<div data-theme-toc="true"><h2>A</h2><h2>B</h2><h2>C</h2></div>',
      );
      final toc = TocExtractor.build(nodes, postId: 1)!;
      expect(toc.flat, hasLength(3));
    });
  });

  group('TocExtractor id 与文本', () {
    test('id 优先用服务端锚点名', () {
      final nodes = parser.parse(
        '${anchoredHeading(2, 'p-9-h-a-1', 'A')}'
        '${anchoredHeading(2, 'p-9-h-b-2', 'B')}'
        '${anchoredHeading(2, 'p-9-h-c-3', 'C')}',
      );
      final toc = TocExtractor.build(nodes, postId: 9)!;
      expect(toc.flat.map((e) => e.id), ['p-9-h-a-1', 'p-9-h-b-2', 'p-9-h-c-3']);
      // nodeId 是 parser 分配的块 id
      expect(toc.flat.map((e) => e.nodeId), ['b_0', 'b_1', 'b_2']);
    });

    test('无锚点回退 id 形态 p-{postId}-toc-h{level}-{seq}', () {
      final nodes = parser.parse('<h2>A</h2><h3>B</h3><h2>C</h2>');
      final toc = TocExtractor.build(nodes, postId: 7)!;
      expect(toc.flat.map((e) => e.id),
          ['p-7-toc-h2-1', 'p-7-toc-h3-2', 'p-7-toc-h2-3']);
    });

    test('文本取纯文本:样式递归、emoji 不占、mention 带 @', () {
      final nodes = parser.parse(
        '<h2>plain <strong>bold</strong> '
        '<img class="emoji" alt=":heart:" src="x.png"> '
        '<a class="mention" href="/u/alice">@alice</a></h2>'
        '<h2>B</h2><h2>C</h2>',
      );
      final toc = TocExtractor.build(nodes, postId: 1)!;
      expect(toc.flat.first.text, contains('plain bold'));
      expect(toc.flat.first.text, contains('@alice'));
      expect(toc.flat.first.text, isNot(contains('heart')));
    });
  });

  group('TocExtractor 构树(祖先栈)', () {
    test('典型层级嵌套', () {
      final nodes = parser.parse(
        '<h2>A</h2><h3>A1</h3><h3>A2</h3><h2>B</h2><h4>B1x</h4>',
      );
      final toc = TocExtractor.build(nodes, postId: 1, minHeadings: 1)!;
      expect(toc.tree, hasLength(2)); // A, B
      expect(toc.tree[0].text, 'A');
      expect(toc.tree[0].subItems.map((e) => e.text), ['A1', 'A2']);
      expect(toc.tree[1].text, 'B');
      // 跳级(h2 直接下 h4):B1x 仍是 B 的子级
      expect(toc.tree[1].subItems.single.text, 'B1x');
      expect(toc.tree[1].subItems.single.level, 4);
    });

    test('首个标题级别较深时挂根下', () {
      final nodes = parser.parse('<h3>A</h3><h2>B</h2>');
      final toc = TocExtractor.build(nodes, postId: 1, minHeadings: 1)!;
      expect(toc.tree.map((e) => e.text), ['A', 'B']);
    });

    test('flat 与 tree 共享节点且按文档序', () {
      final nodes = parser.parse('<h2>A</h2><h3>A1</h3><h2>B</h2>');
      final toc = TocExtractor.build(nodes, postId: 1, minHeadings: 1)!;
      expect(toc.flat.map((e) => e.text), ['A', 'A1', 'B']);
      expect(identical(toc.flat[1], toc.tree[0].subItems[0]), isTrue);
    });

    test('buildFromChunks 记录 chunkIndex,单 chunk 为 null', () {
      final c0 = parser.parse('<h2>A</h2><p>x</p>');
      final c1 = parser.parse('<h2>B</h2><h3>B1</h3>');
      final toc = TocExtractor.buildFromChunks([c0, c1], postId: 1)!;
      expect(toc.flat.map((e) => e.chunkIndex), [0, 1, 1]);
      // 跨 chunk 构树不断:B1 仍是 B 的子级
      expect(toc.tree.map((e) => e.text), ['A', 'B']);
      expect(toc.tree[1].subItems.single.text, 'B1');

      final single =
          TocExtractor.buildFromChunks([c0, c1], postId: 1, minHeadings: 1);
      // 注意:两个列表当两个 chunk 传才是长帖;短帖应传 [nodes]
      final short = TocExtractor.build(
          parser.parse('<h2>A</h2><h2>B</h2><h2>C</h2>'),
          postId: 1)!;
      expect(short.flat.every((e) => e.chunkIndex == null), isTrue);
      expect(single, isNotNull);
    });
  });
}
