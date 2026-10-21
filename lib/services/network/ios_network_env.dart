import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 系统网络环境快照（原生 `com.fluxdo/network_env` 返回）。
///
/// `connectivity_plus` 在 iOS 上底层是 `NWPathMonitor`，`NWPath` 没有 VPN
/// 接口类型，插件永远只报告 wifi / mobile / ethernet / other。所以 VPN 与
/// 系统代理只能由原生侧读 `CFNetworkCopySystemProxySettings()` 与
/// `getifaddrs()` 补齐（见 `ios/Runner/NetworkEnvHandler.swift`）。
@immutable
class IosNetworkEnv {
  const IosNetworkEnv({
    this.vpnActive = false,
    this.proxyUrl,
    this.pacUrl,
    this.interfaces = const [],
    this.scopedInterfaces = const [],
  });

  static const inactive = IosNetworkEnv();

  /// 是否存在已建立的隧道接口（VPN / TUN）
  final bool vpnActive;

  /// 固定系统代理（`http://host:port`）。未启用时为 null
  final String? proxyUrl;

  /// PAC 脚本地址。PAC 无法在 Dart 侧求值，只用于「系统代理已启用」判定
  final String? pacUrl;

  /// 当前处于 UP 状态的接口名
  final List<String> interfaces;

  /// `__SCOPED__` 里出现过的接口名
  final List<String> scopedInterfaces;

  bool get proxyEnabled => proxyUrl != null || (pacUrl?.isNotEmpty ?? false);

  factory IosNetworkEnv.fromMap(Map<Object?, Object?> map) {
    List<String> strings(Object? value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const [];
    String? optionalString(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty || text == 'null' ? null : text;
    }

    return IosNetworkEnv(
      vpnActive: map['vpnActive'] == true,
      proxyUrl: IosNetworkEnvDetector.normalizeProxyUrl(
        host: map['proxyHost'],
        port: map['proxyPort'],
      ),
      pacUrl: optionalString(map['pacUrl']),
      interfaces: strings(map['interfaces']),
      scopedInterfaces: strings(map['scopedInterfaces']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IosNetworkEnv &&
      other.vpnActive == vpnActive &&
      other.proxyUrl == proxyUrl &&
      other.pacUrl == pacUrl;

  @override
  int get hashCode => Object.hash(vpnActive, proxyUrl, pacUrl);

  @override
  String toString() =>
      'IosNetworkEnv(vpn: $vpnActive, proxy: ${proxyUrl ?? '-'}, '
      'pac: ${pacUrl ?? '-'})';
}

/// iOS 网络环境检测。
///
/// 判定逻辑与原生 `NetworkEnvHandler` 一致，这里保留纯函数版本供单测
/// （Windows 的 [WindowsVpnAdapterDetector] 是同样的结构）。
class IosNetworkEnvDetector {
  const IosNetworkEnvDetector._();

  static const channelName = 'com.fluxdo/network_env';
  static const _channel = MethodChannel(channelName);

  /// 直接触发自动压制的接口名前缀。
  ///
  /// 不含 `utun`：utun0 是 iOS 常驻的系统接口，iCloud 私密中继、Wi-Fi 通话
  /// 也会挂 utun/ipsec 接口，只按名字判断会误报。`ipsec` 同样排除。
  static const _tunnelPrefixes = <String>['tap', 'tun', 'ppp'];

  /// 读取一次原生网络环境。非 iOS 平台返回 [IosNetworkEnv.inactive]。
  static Future<IosNetworkEnv> read() async {
    if (!Platform.isIOS) return IosNetworkEnv.inactive;
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getNetworkEnv',
      );
      if (result == null) return IosNetworkEnv.inactive;
      return IosNetworkEnv.fromMap(result);
    } on MissingPluginException {
      // 旧二进制（未带 NetworkEnvHandler）或单测环境：按未开启处理
      return IosNetworkEnv.inactive;
    } catch (e) {
      debugPrint('[IosNetworkEnv] 读取失败: $e');
      return IosNetworkEnv.inactive;
    }
  }

  /// 接口名 / 作用域名里出现 tap/tun/ppp，或 utun 接口数 ≥ 2，视为隧道已建立
  @visibleForTesting
  static bool looksLikeVpnActive({
    required List<String> interfaces,
    required List<String> scopedInterfaces,
  }) {
    final names = <String>{
      ...interfaces,
      ...scopedInterfaces,
    }.map((name) => name.trim().toLowerCase()).where((name) {
      return name.isNotEmpty;
    }).toList(growable: false);
    if (names.any((name) => _tunnelPrefixes.any(name.startsWith))) {
      return true;
    }
    return names.where((name) => name.startsWith('utun')).length >= 2;
  }

  /// 把原生返回的固定代理字段拼成 `http://host:port`，非法值返回 null
  @visibleForTesting
  static String? normalizeProxyUrl({Object? host, Object? port}) {
    final hostText = host?.toString().trim() ?? '';
    if (hostText.isEmpty) return null;
    final portValue = port is num ? port.toInt() : int.tryParse('$port');
    if (portValue == null || portValue < 1 || portValue > 65535) return null;
    return 'http://$hostText:$portValue';
  }
}

/// iOS 网络环境的单例轮询。
///
/// 系统代理与 VPN 状态都来自同一个原生快照，这里只轮询一次，供
/// [SystemProxyService] 与 [VpnAutoToggleService] 共用，避免两套 MethodChannel
/// 往返。隧道开关不一定产生 connectivity 事件，所以需要低频兜底节拍。
class IosNetworkEnvService {
  IosNetworkEnvService._();

  static final IosNetworkEnvService instance = IosNetworkEnvService._();

  static const _pollInterval = Duration(seconds: 10);

  final ValueNotifier<IosNetworkEnv> notifier = ValueNotifier(
    IosNetworkEnv.inactive,
  );

  Timer? _timer;
  Future<IosNetworkEnv>? _inflight;
  bool _started = false;

  IosNetworkEnv get current => notifier.value;

  void start() {
    if (_started || !Platform.isIOS) return;
    _started = true;
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  /// 立即重读一次；并发调用共享同一个 Future
  Future<IosNetworkEnv> refresh() {
    if (!Platform.isIOS) return Future.value(IosNetworkEnv.inactive);
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = IosNetworkEnvDetector.read().then((env) {
      if (env != notifier.value) {
        debugPrint('[IosNetworkEnv] 状态变化: $env');
        notifier.value = env;
      }
      return env;
    }).whenComplete(() {
      _inflight = null;
    });
    _inflight = future;
    return future;
  }

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _inflight = null;
    notifier.value = IosNetworkEnv.inactive;
  }
}
