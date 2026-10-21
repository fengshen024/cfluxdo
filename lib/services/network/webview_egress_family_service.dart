import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../constants.dart';
import '../connectivity_service.dart';
import '../network_logger.dart';
import '../webview_settings.dart';
import 'doh_proxy/doh_proxy_service.dart';

/// WebView 实际出口地址族探测与对齐。
///
/// 背景：iOS 17 以下 `WKWebView` 没有按应用设置代理的 API（见
/// `NetworkSettingsService._applyWebViewProxy`），站内网页走系统网络，而 API
/// 走本地网关。双栈网络下两边的出口是两个地址，Cloudflare 会把它们当成两个
/// 会话：WebView 铸出的 `cf_clearance` 绑的是 WebView 出口 IP，API 拿着它去
/// 请求网关出口，稳定 403。
///
/// 这里用一个临时 Headless WebView 请求 `/cdn-cgi/trace`，读回 WebView 真正的
/// 出口 IP，判断地址族，再通过 `doh_proxy_set_forced_family` 把 Rust 侧
/// （DoH 解析、建连、优选赢家）压到同一族。两族出口 IP 仍然不同，但至少
/// 不会再出现「v4/v6 各走一边」这种必然不一致。
///
/// 只在 WebView 不走本地网关时启用；iOS 17+ / Android / Windows 上 WebView
/// 本来就跟网关同一出口，无需干预。
class WebViewEgressFamilyService {
  WebViewEgressFamilyService._();

  static final WebViewEgressFamilyService instance =
      WebViewEgressFamilyService._();

  /// 探测结果：true = WebView 走 IPv6；null = 还没测出来 / 测不出来
  final ValueNotifier<bool?> webViewPrefersIpv6 = ValueNotifier<bool?>(null);

  /// 由 `NetworkSettingsService.primePlatformCapabilities()` 写入：
  /// WebView 能否被指到本地网关（iOS 17+ 才有 `setProxyOverride`）。
  /// 用静态字段承接这个信号，避免在字段初始化阶段就触碰单例。
  static bool webViewProxySupported = false;

  /// 由 `NetworkSettingsService` 写入：本地代理当前是否在跑
  static bool localProxyRunning = false;

  /// 同一网络环境下最短重测间隔。换网会立即重测
  static const _revalidateInterval = Duration(minutes: 30);
  static const _debounce = Duration(seconds: 3);

  /// 一次探测的总预算：加载 + fetch trace。超时按失败处理
  static const _probeTimeout = Duration(seconds: 20);

  /// loadData 之后等 onLoadStop 的宽限；超过就自己补发 trace
  static const _loadStopGrace = Duration(milliseconds: 800);

  Timer? _debounceTimer;
  bool _inFlight = false;
  bool _started = false;
  String? _lastSignature;
  DateTime? _lastEvaluatedAt;

  /// 是否正在探测（诊断 / 日志用）
  bool get isEvaluating => _inFlight;

  /// 挂上触发源：启动完成、换网。
  ///
  /// 网关起停不在这里订阅：`NetworkSettingsService._applyProxyState` 收尾时
  /// 会直接调用 [scheduleEvaluation]，省掉一条反向依赖，避免两个服务互相 import。
  /// 只在需要时（iOS 17 以下 + 本地代理在跑）真正发探测。
  void start() {
    if (_started || !Platform.isIOS) return;
    _started = true;
    ConnectivityService().networkSignature.addListener(_onNetworkChanged);
    scheduleEvaluation(reason: 'startup');
  }

  void _onNetworkChanged() =>
      scheduleEvaluation(reason: 'network_signature');

  /// 安排一次对齐检查。同一网络环境下 30 分钟内只做一次。
  ///
  /// 调用方：启动完成、换网、网关启动。失败静默，不影响任何请求路径。
  void scheduleEvaluation({required String reason}) {
    if (!_isSupported) return;
    final signature = _currentSignature;
    if (!_needsEvaluation(signature)) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(evaluate(reason: reason));
    });
  }

  bool get _isSupported =>
      Platform.isIOS &&
      // iOS 17 起 WebView 也走本地网关，出口天然一致
      !webViewProxySupported &&
      // 本地代理没在跑时没有可对齐的 API 出口
      localProxyRunning;

  String get _currentSignature =>
      ConnectivityService().networkSignature.value ?? 'unknown';

  bool _needsEvaluation(String signature) {
    if (_inFlight) return false;
    if (_lastEvaluatedAt == null) return true;
    if (_lastSignature != signature) return true;
    return DateTime.now().difference(_lastEvaluatedAt!) > _revalidateInterval;
  }

  /// 立即探测并对齐一次
  Future<void> evaluate({required String reason}) async {
    if (!_isSupported || _inFlight) return;
    _inFlight = true;
    final signature = _currentSignature;
    try {
      final trace = await _fetchTrace();
      final ip = parseTraceIp(trace);
      final family = familyOfIp(ip);
      if (family == null) {
        // 探测失败不做负缓存：下次触发（换网 / 网关重启）还要再试
        NetworkLogger.log('[EgressFamily] 探测失败（$reason），保持当前地址族');
        return;
      }
      webViewPrefersIpv6.value = family;
      _lastSignature = signature;
      _lastEvaluatedAt = DateTime.now();
      final applied = await DohProxyService.instance.setForcedFamily(family);
      NetworkLogger.log(
        '[EgressFamily] WebView 出口 $ip（${family ? "IPv6" : "IPv4"}，$reason）'
        '，${applied ? "已对齐" : "未下发"}',
      );
    } catch (e) {
      NetworkLogger.log('[EgressFamily] 探测异常（$reason）: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// 清掉强制族（例如用户关闭 DoH 时）
  ///
  /// 只有 iOS 会下发强制族，其它平台直接返回，免得每次关网关都多一次 FFI 往返。
  Future<void> clear() async {
    if (!Platform.isIOS) return;
    webViewPrefersIpv6.value = null;
    _lastEvaluatedAt = null;
    // 关网关后 DoH 也停了，FFI 侧没有可下发的 resolver；这里返回 false 是
    // 正常情况，强制族已随网关关闭一起消失
    await DohProxyService.instance.setForcedFamily(null);
  }

  // ---------------------------------------------------------------------------
  // 探测
  // ---------------------------------------------------------------------------

  Future<String?> _fetchTrace() async {
    final result = Completer<String?>();
    HeadlessInAppWebView? webView;
    InAppWebViewController? controller;
    // loadData 之后才允许发 trace：建 WebView 时的初始空白页也会触发
    // onLoadStop，那次不算数
    var dataLoadStarted = false;
    var traceRequested = false;

    void finish(String? trace) {
      // JS 侧的失败路径回传空串，按「没测到」处理
      final text = trace?.trim();
      if (!result.isCompleted) {
        result.complete(text == null || text.isEmpty ? null : text);
      }
    }

    try {
      webView = HeadlessInAppWebView(
        initialSettings: WebViewSettings.headless,
        onReceivedServerTrustAuthRequest: (_, challenge) =>
            WebViewSettings.handleServerTrustAuthRequest(challenge),
        onWebViewCreated: (created) {
          controller = created;
          created.addJavaScriptHandler(
            handlerName: 'egressTrace',
            callback: (args) {
              finish(args.isNotEmpty ? args.first?.toString() : null);
              return null;
            },
          );
        },
        onLoadStop: (created, _) {
          if (!dataLoadStarted || traceRequested) return;
          traceRequested = true;
          unawaited(_runTraceFetch(created, finish));
        },
        onReceivedError: (_, request, _) {
          // 初始空白页的失败忽略，避免抢先判负
          if (traceRequested && request.isForMainFrame != false) finish(null);
        },
      );
      await webView.run();
      final ready = controller;
      if (ready == null) return null;

      // trace 在 onLoadStop 里发起，探测总预算从这里开始算
      final deadline = result.future.timeout(
        _probeTimeout,
        onTimeout: () => null,
      );
      // 与 WebViewHttpAdapter 一致：用应用站点作 baseUrl，fetch 才带同源
      // Cookie（CF 对无 Cookie 的 trace 也可能直接给盾）
      dataLoadStarted = true;
      await ready.loadData(
        data: _bootstrapHtml,
        baseUrl: WebUri(AppConstants.baseUrl),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
      // 兜底：个别平台 loadData 的 onLoadStop 报的 URL 不是站点地址，等不到就
      // 自己发一次；traceRequested 保证只会发一次
      if (!traceRequested) {
        await Future<void>.delayed(_loadStopGrace);
        if (!traceRequested && !result.isCompleted) {
          traceRequested = true;
          await _runTraceFetch(ready, finish);
        }
      }

      return await deadline;
    } catch (e) {
      debugPrint('[EgressFamily] WebView 探测失败: $e');
      return null;
    } finally {
      try {
        await webView?.dispose();
      } catch (e) {
        debugPrint('[EgressFamily] WebView dispose 异常: $e');
      }
    }
  }

  Future<void> _runTraceFetch(
    InAppWebViewController controller,
    void Function(String?) finish,
  ) async {
    try {
      await controller.evaluateJavascript(
        source:
            '''
(async function() {
  try {
    const response = await fetch('/cdn-cgi/trace', {
      method: 'GET',
      credentials: 'include',
      cache: 'no-store'
    });
    const text = await response.text();
    window.flutter_inappwebview.callHandler('egressTrace', text);
  } catch (e) {
    window.flutter_inappwebview.callHandler('egressTrace', '');
  }
})();
''',
      );
    } catch (e) {
      finish(null);
    }
  }

  String get _bootstrapHtml =>
      '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
      '<body></body></html>';

  // ---------------------------------------------------------------------------
  // 解析（纯函数，便于单测）
  // ---------------------------------------------------------------------------

  /// 从 `/cdn-cgi/trace` 的响应体里取 `ip=` 的值
  @visibleForTesting
  static String? parseTraceIp(String? trace) {
    if (trace == null) return null;
    for (final line in trace.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ip=')) {
        final value = trimmed.substring(3).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  /// IP 字面量的地址族：true = IPv6；无法解析返回 null
  @visibleForTesting
  static bool? familyOfIp(String? ip) {
    if (ip == null) return null;
    final address = InternetAddress.tryParse(ip.trim());
    if (address == null) return null;
    return address.type == InternetAddressType.IPv6;
  }

  @visibleForTesting
  void resetForTest() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _inFlight = false;
    _started = false;
    _lastSignature = null;
    _lastEvaluatedAt = null;
    webViewPrefersIpv6.value = null;
  }
}
