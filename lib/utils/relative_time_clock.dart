import 'dart:async';

import 'package:flutter/foundation.dart';

/// 全应用唯一的相对时间心跳。
///
/// "3分钟前"这类相对时间的刷新,此前是每个 [RelativeTimeText] 实例
/// 自养一个 Timer(15s~30min 自适应)+ 自己 setState —— 详情页一屏
/// 十几个实例就是十几个定时器在随机时刻各自醒来打扰事件循环;而
/// 自绘卡的排版快照又完全不刷,同一 app 两种行为。Flutter 框架与
/// 生态都没有共享心跳原语(原生 Android 有 ACTION_TIME_TICK 系统
/// 分钟广播,Flutter 无对等物),此类为其对等物:
///
/// - 单 Timer,对齐到**分钟边界**触发(相对时间的最小显示粒度是
///   分钟,亚分钟档"刚刚/N秒前"的过渡瑕疵 ≤1 分钟,不为它付
///   秒级心跳);
/// - 无监听者时不跑(最后一个移除即停,首个添加即启)——列表全部
///   滚出/页面销毁后零常驻;
/// - 通知在分钟边界统一发出:所有订阅方同帧重建,一次帧调度收编
///   此前十几个随机时刻的独立重建。
class RelativeTimeClock extends ChangeNotifier {
  RelativeTimeClock._();

  static final RelativeTimeClock instance = RelativeTimeClock._();

  Timer? _timer;

  /// 自己维护一份订阅者名单:`ChangeNotifier` 的 `_listeners` 是私有字段,
  /// [debugStop] 需要它来强制解绑(见那里的说明)。
  final Set<VoidCallback> _registered = <VoidCallback>{};

  @override
  void addListener(VoidCallback listener) {
    _registered.add(listener);
    super.addListener(listener);
    _ensureTimer();
  }

  @override
  void removeListener(VoidCallback listener) {
    _registered.remove(listener);
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _ensureTimer() {
    if (_timer != null) return;
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    // 下一个分钟边界 +50ms 余量(防计时器早醒落在边界前)
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 1, milliseconds: 50));
    _timer = Timer(next.difference(now), () {
      _timer = null;
      if (!hasListeners) return;
      notifyListeners();
      _schedule();
    });
  }

  /// 测试专用:停掉心跳。
  ///
  /// 这是进程级单例,`testWidgets` 结束时若还有订阅者(例如自绘卡的排版
  /// 缓存持有的一次性 hook),待触发的 Timer 会让测试框架报
  /// 「A Timer is still pending」。测试里配合各持有方的解绑一起调用。
  @visibleForTesting
  void debugStop() {
    _timer?.cancel();
    _timer = null;
    // 测试用例结束时 widget 树可能还没 detach（清理跑在框架检查之前），
    // 订阅者仍在。这里直接清空，避免残留订阅在下一帧又把心跳拉起来。
    for (final listener in List<VoidCallback>.from(_registered)) {
      removeListener(listener);
    }
  }
}
