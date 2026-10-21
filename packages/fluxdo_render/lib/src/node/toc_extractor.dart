/// 话题目录(TOC)提取 —— 对齐 DiscoTOC(theme component)的数据口径。
///
/// 与 DiscoTOC `toc-processor.js` 的对应关系:
/// - 选择器 `body > :is(h1..h5), body > :is(.wrap,.d-wrap) :is(h1..h5)`
///   → 这里遍历**顶层块序列**里的 [HeadingNode](引用块/折叠块/表格内的
///   标题天然不在顶层;`.wrap` 类容器 div 在 parser 已透明拆壳,其标题
///   会出现在顶层,语义一致);h6 与 DiscoTOC 一样不收。
/// - id 优先取服务端锚点名([HeadingNode.anchorName],cook 时生成,
///   兼容 `#锚点` 深链);缺失时回退 `p-{postId}-toc-h{level}-{seq}`,
///   与 DiscoTOC `getIdFromHeading` 的回退形态一致(仅作内部标识)。
/// - 构树用同一套祖先栈算法;文本取标题纯文本(DOM textContent 口径,
///   图片/emoji 不占文本)。
library;

import 'node.dart';

/// 锚点键:chunkIndex + nodeId 复合。
///
/// 背景:parser 的节点 id("b_0"…)是**单次解析内**分配的,长帖逐 chunk
/// 解析意味着同一帖子里 chunk0 的 b_2 与 chunk3 的 b_2 是不同标题 —
/// 注册/查找必须带 chunk 维度才不会互相覆盖。chunkIndex 0(含短帖整帖)
/// 直接用 nodeId。渲染侧 HeadingAnchorRegistrar 与提取侧
/// [TocEntry.anchorKey] 共用本函数,保证同口径。
String headingAnchorKey(int chunkIndex, String nodeId) =>
    chunkIndex == 0 ? nodeId : '$chunkIndex:$nodeId';
/// TOC 条目(树节点),对齐 DiscoTOC tocStructure 项。
class TocEntry {
  TocEntry({
    required this.id,
    required this.nodeId,
    required this.level,
    required this.text,
    this.chunkIndex,
    List<TocEntry>? subItems,
  })  : subItems = subItems ?? [],
        anchorKey = headingAnchorKey(chunkIndex ?? 0, nodeId);

  /// 定位 id:优先服务端锚点名(`p-123-h-xxx-1`),缺失时回退
  /// `p-{postId}-toc-h{level}-{seq}`。
  final String id;

  /// [HeadingNode.id] —— 渲染侧滚动定位用(配合 HeadingAnchorRegistry)。
  final String nodeId;

  /// 标题级别 1-5。
  final int level;

  /// 标题纯文本。
  final String text;

  /// 长帖分块渲染时该标题所在的 chunk 下标;短帖(整帖一段)为 null。
  /// 滚动定位用:chunk 段在 sliver 列表里独立成段,可先行跳转。
  final int? chunkIndex;

  /// HeadingAnchorRegistry 里的查找键([headingAnchorKey] 复合产物)。
  /// 跳转/scroll-spy 都用它取挂载 context。
  final String anchorKey;

  /// 子级条目。
  final List<TocEntry> subItems;

  @override
  String toString() => 'TocEntry($id, h$level, "$text", ${subItems.length} sub)';
}

/// 一份帖子的 TOC 提取产物。
class TocData {
  const TocData({required this.tree, required this.flat});

  /// 树形结构(UI 面板渲染用)。
  final List<TocEntry> tree;

  /// 文档序扁平列表(scroll-spy 位置计算用),与 tree 共享节点。
  final List<TocEntry> flat;

  bool get isEmpty => flat.isEmpty;
}

/// TOC 提取器。
abstract final class TocExtractor {
  /// 短帖整帖提取([nodes] 为顶层块序列)。
  static TocData? build(
    List<BlockNode> nodes, {
    required int postId,
    int minHeadings = 3,
  }) =>
      buildFromChunks([nodes], postId: postId, minHeadings: minHeadings);

  /// 按渲染分块提取:长帖每个 chunk 一段 sliver,[TocEntry.chunkIndex]
  /// 记录标题所在块,跳转时先定位到段再精确化。
  ///
  /// [chunkNodes] 每项是一个 chunk 的顶层块序列;[minHeadings] 不足返回
  /// null(对齐 DiscoTOC `TOC_min_heading`)。单元素列表等价短帖,
  /// 条目 chunkIndex 记 null。
  static TocData? buildFromChunks(
    List<List<BlockNode>> chunkNodes, {
    required int postId,
    int minHeadings = 3,
  }) {
    final isSingle = chunkNodes.length <= 1;
    final headings = <(HeadingNode, int?)>[];
    for (var ci = 0; ci < chunkNodes.length; ci++) {
      for (final block in chunkNodes[ci]) {
        if (block is HeadingNode && block.level <= 5) {
          headings.add((block, isSingle ? null : ci));
        }
      }
    }
    if (headings.length < minHeadings) return null;

    final root = TocEntry(id: '', nodeId: '', level: 0, text: '');
    final ancestors = <TocEntry>[root];
    final flat = <TocEntry>[];
    var fallbackSeq = 0;

    for (final (heading, chunkIndex) in headings) {
      // 剔除 level >= 当前的祖先 → 同级成兄弟、更浅则上浮(同 DiscoTOC)
      while (ancestors.last.level >= heading.level) {
        ancestors.removeLast();
      }
      final entry = TocEntry(
        id: heading.anchorName ??
            'p-$postId-toc-h${heading.level}-${++fallbackSeq}',
        nodeId: heading.id,
        level: heading.level,
        text: plainTextOfInlines(heading.inlines).trim(),
        chunkIndex: chunkIndex,
      );
      ancestors.last.subItems.add(entry);
      ancestors.add(entry);
      flat.add(entry);
    }

    return TocData(tree: root.subItems, flat: flat);
  }

  /// 行内序列 → 纯文本(DOM textContent 口径:img/emoji 不占文本;
  /// `<br>` 记一个空格让分词不断裂)。
  static String plainTextOfInlines(List<InlineNode> inlines) {
    final buf = StringBuffer();

    void walk(List<InlineNode> list) {
      for (final node in list) {
        switch (node) {
          case TextRun(:final text):
            buf.write(text);
          case EmRun(:final children) ||
              StrongRun(:final children) ||
              StyledRun(:final children) ||
              ColoredRun(:final children) ||
              SizedRun(:final children) ||
              LinkRun(:final children) ||
              SpoilerRun(:final children):
            walk(children);
          case InlineCodeRun(:final text):
            buf.write(text);
          case MentionRun(:final username):
            buf.write('@$username');
          case LineBreakRun():
            buf.write(' ');
          case FootnoteRefRun(:final number):
            buf.write(number);
          case LocalDateRun(:final fallbackText):
            buf.write(fallbackText);
          case ClickCountRun(:final count):
            buf.write(count);
          case MathInlineRun(:final latex):
            buf.write(latex);
          case EmojiRun() || ImageRun():
            break; // 图片/emoji 在 DOM textContent 里同样不占文本
        }
      }
    }

    walk(inlines);
    return buf.toString();
  }
}
