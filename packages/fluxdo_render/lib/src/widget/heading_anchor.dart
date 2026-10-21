/// 标题锚点注册 —— 阅读侧 TOC(目录树)的渲染侧支撑。
///
/// 三件套:
/// - [HeadingAnchorRegistry]:话题作用域的注册表,`HeadingNode.id` →
///   已挂载标题的 `BuildContext`,TOC 面板点击跳转(精确滚动)与
///   scroll-spy(取视口位置算激活项)共用;
/// - [HeadingAnchorScope]: InheritedWidget,把注册表挂到帖子列表上空;
/// - [HeadingAnchorRegistrar]: NodeFactory 给每个标题块的包装,挂载即
///   注册、卸载即注销;无 scope 时(编辑器/分享卡等)零行为开销。
library;

import 'package:flutter/widgets.dart';

import '../node/toc_extractor.dart' show headingAnchorKey;

/// 标题锚点注册表(锚点键 → 挂载中的标题 context)。
///
/// 锚点键由 [headingAnchorKey] 复合(chunk 维度 + 节点 id);注册表挂在
/// 1 楼上空,帖内唯一。防御性地按 identity 注销,避免重复挂载场景下
/// 误删新注册。
class HeadingAnchorRegistry {
  final Map<String, BuildContext> _contexts = {};

  void register(String nodeId, BuildContext context) {
    _contexts[nodeId] = context;
  }

  void unregister(String nodeId, BuildContext context) {
    if (identical(_contexts[nodeId], context)) {
      _contexts.remove(nodeId);
    }
  }

  /// 该标题的挂载 context;未挂载(滚出回收/chunk 未物化)为 null。
  BuildContext? contextOf(String nodeId) {
    final ctx = _contexts[nodeId];
    return (ctx != null && ctx.mounted) ? ctx : null;
  }

  /// 当前已挂载的全部 (nodeId, context),scroll-spy 遍历用。
  Iterable<MapEntry<String, BuildContext>> get mountedEntries =>
      _contexts.entries.where((e) => e.value.mounted);
}

/// 把 [HeadingAnchorRegistry] 注入子树的 scope。
class HeadingAnchorScope extends InheritedWidget {
  const HeadingAnchorScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final HeadingAnchorRegistry registry;

  static HeadingAnchorRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HeadingAnchorScope>()
      ?.registry;

  @override
  bool updateShouldNotify(HeadingAnchorScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// 标题块包装:向最近的 [HeadingAnchorScope] 注册自己的 context。
class HeadingAnchorRegistrar extends StatefulWidget {
  const HeadingAnchorRegistrar({
    super.key,
    required this.nodeId,
    this.chunkIndex = 0,
    required this.child,
  });

  /// [HeadingNode.id](单次解析内唯一;跨 chunk 会重复,见 [chunkIndex])。
  final String nodeId;

  /// 所在 chunk(NodeFactory.chunkIndex):长帖逐 chunk 解析节点 id 会
  /// 重复,注册键由 [headingAnchorKey] 复合。短帖恒 0。
  final int chunkIndex;
  final Widget child;


  @override
  State<HeadingAnchorRegistrar> createState() =>
      _HeadingAnchorRegistrarState();
}

class _HeadingAnchorRegistrarState extends State<HeadingAnchorRegistrar> {
  HeadingAnchorRegistry? _registry;

  String get _anchorKey => headingAnchorKey(widget.chunkIndex, widget.nodeId);

  void _moveTo(HeadingAnchorRegistry? next) {
    if (identical(next, _registry)) return;
    _registry?.unregister(_anchorKey, context);
    _registry = next;
    _registry?.register(_anchorKey, context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _moveTo(HeadingAnchorScope.maybeOf(context));
  }

  @override
  void didUpdateWidget(covariant HeadingAnchorRegistrar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId ||
        oldWidget.chunkIndex != widget.chunkIndex) {
      _registry?.unregister(
          headingAnchorKey(oldWidget.chunkIndex, oldWidget.nodeId), context);
      _registry?.register(_anchorKey, context);
    }
  }

  @override
  void dispose() {
    _registry?.unregister(_anchorKey, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
