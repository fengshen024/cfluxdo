import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ios_network_env.dart';
import 'system_proxy_detector.dart';

/// 系统代理跟随服务（Windows / iOS）。
///
/// 背景:WebView2 默认跟随系统代理(如 Clash「系统代理」模式),而 Dio/rhttp
/// 走直连。两者出口 IP 不一致时,验证 WebView 铸出的 cf_clearance 绑定的是
/// 代理节点 IP,对 Dio 的直连请求永远无效 → CF 验证无限循环。iOS 同理:
/// 系统代理由 `CFNetworkCopySystemProxySettings()` 读取,WebView 跟随它,
/// 而 Dio 默认不跟。
///
/// 本服务周期读取系统代理:
/// - 已启用固定代理 → [effectiveProxyUrl] 返回代理地址,Dio 跟随,与
///   WebView 保持同一出口;代理进程若已死,请求显式失败(与 WebView 一致),
///   不做可达性探测——探测无法区分翻墙代理与校园网等普通代理,不能作为
///   任何语义判定依据。
/// - 未启用 / PAC-only(无法在 Dart 侧求值)/ 其它平台 → 直连。
///
/// VPN 虚拟网卡(TUN)模式不写系统代理,Dio 与 WebView 都经 TUN 出站,
/// 天然一致,无需本服务干预。
class SystemProxyService {
  SystemProxyService._();

  static final instance = SystemProxyService._();

  static const _refreshInterval = Duration(seconds: 10);

  /// 状态版本号。effectiveProxyUrl 变化时自增,RhttpAdapter 据此重建 client。
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  String? _effectiveProxyUrl;
  SystemProxyConfig _lastConfig = const SystemProxyConfig();
  Timer? _refreshTimer;
  bool _started = false;

  /// 是否由本服务管理系统代理（Windows 注册表 / iOS CFNetwork）
  static bool get isSupported => Platform.isWindows || Platform.isIOS;

  /// 当前系统代理地址（已启用的固定代理），未启用时为 null。
  String? get effectiveProxyUrl {
    _ensureStarted();
    return _effectiveProxyUrl;
  }

  /// 系统代理配置，供诊断 UI 展示。
  SystemProxyConfig get systemConfig => _lastConfig;

  /// 启动周期刷新。不支持的平台为 no-op。
  void start() => _ensureStarted();

  void _ensureStarted() {
    if (_started || !isSupported) return;
    _started = true;
    if (Platform.isIOS) {
      // iOS 的系统代理与 VPN 共用 IosNetworkEnvService 的 10s 原生快照，
      // 这里只跟它的状态变化，不再单独起一条轮询（否则平台通道调用翻倍）
      IosNetworkEnvService.instance.start();
      IosNetworkEnvService.instance.notifier.addListener(_applyIosSnapshot);
      _applyIosSnapshot();
      return;
    }
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => refresh());
    refresh();
  }

  /// 立即重读系统代理。iOS 上代理与 VPN 共用同一份原生快照，读取要跨平台线程，
  /// 所以先用当前快照同步生效，再异步刷新。
  void refresh() {
    if (!isSupported) return;
    if (Platform.isIOS) {
      _applyIosSnapshot();
      unawaited(IosNetworkEnvService.instance.refresh());
      return;
    }
    _applyConfig(SystemProxyDetector.read());
  }

  void _applyIosSnapshot() {
    final env = IosNetworkEnvService.instance.current;
    _applyConfig(SystemProxyConfig(proxyUrl: env.proxyUrl, pacUrl: env.pacUrl));
  }

  void _applyConfig(SystemProxyConfig config) {
    _lastConfig = config;

    final effective = config.proxyUrl;
    if (effective != _effectiveProxyUrl) {
      debugPrint(
        '[SystemProxy] 系统代理变化: ${_effectiveProxyUrl ?? 'direct'} -> '
        '${effective ?? 'direct'}',
      );
      _effectiveProxyUrl = effective;
      version.value++;
    }
  }

  @visibleForTesting
  void resetForTest() {
    if (_started && Platform.isIOS) {
      IosNetworkEnvService.instance.notifier.removeListener(_applyIosSnapshot);
    }
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _started = false;
    _effectiveProxyUrl = null;
    _lastConfig = const SystemProxyConfig();
  }
}
