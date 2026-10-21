import 'dart:async';

import 'package:flutter/scheduler.dart';

/// 空闲任务调度:替代 `SchedulerBinding.scheduleTask(..., Priority.idle)`。
///
/// Flutter 3.44 的 `handleEventLoopCallback` 在队首任务因优先级不足被拒绝
/// 执行时仍返回 true,`_runTasks` 便用零延时 Timer 无限重排自己——只要
/// 队列里躺着一个 idle 任务且页面存在持续动画(transientCallbackCount>0,
/// 如着色器背景/加载动画),事件循环就退化为全速忙等,UI 线程被活锁
/// (实测每秒 9~18 万条空消息)。这里用 8ms 定时器链自实现"空闲礼让",
/// 完全不进框架任务队列。
///
/// 语义:动画进行中每 8ms 探测一次(代价可忽略),动画停止后执行;
/// 连续礼让超过 [maxDeferral] 后强制执行,避免常驻动画把任务饿死。
///
/// 返回的 [IdleTask] 可在宿主销毁时 [IdleTask.cancel] 掉未触发的探测:
/// 只靠 [isCanceled] 只能让任务不执行,定时器本身仍会挂到下一跳,
/// 测试框架会判定为残留 Timer。
IdleTask scheduleIdleTask(
  void Function() task, {
  bool Function()? isCanceled,
  Duration maxDeferral = const Duration(seconds: 2),
}) {
  final handle = IdleTask._();
  final deadline = DateTime.now().add(maxDeferral);

  void attempt() {
    handle._timer = Timer(const Duration(milliseconds: 8), () {
      handle._timer = null;
      if (isCanceled?.call() ?? false) return;
      if (SchedulerBinding.instance.transientCallbackCount > 0 &&
          DateTime.now().isBefore(deadline)) {
        attempt();
        return;
      }
      task();
    });
  }

  attempt();
  return handle;
}

/// [scheduleIdleTask] 返回的句柄:持有当前这一跳的定时器。
class IdleTask {
  IdleTask._();

  Timer? _timer;

  /// 是否还有未触发的探测。
  bool get isActive => _timer != null;

  /// 取消尚未触发的探测;已经执行过的任务不受影响。
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
