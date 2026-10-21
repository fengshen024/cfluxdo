import CFNetwork
import Darwin
import Flutter
import Foundation

/// iOS 网络环境检测：系统代理与 VPN（隧道）活动状态。
///
/// `connectivity_plus` 在 iOS 上底层是 `NWPathMonitor`，而 `NWPath` 没有单独的
/// VPN 接口类型，插件永远只返回 wifi / mobile / ethernet / other。因此
/// 「VPN 自动切换」在 iOS 上必须由原生补信号，否则整条自动压制逻辑是死代码。
///
/// 这里只读取系统状态，不建 Network Extension：`NEAppProxyProvider` 只在受监管
/// 设备上可用，免费账号自签也拿不到对应 entitlement。
///
/// 与 Dart 侧 `lib/services/network/ios_network_env.dart` 的判定保持一致。
final class NetworkEnvHandler {
  static let shared = NetworkEnvHandler()
  private init() {}

  /// 与 Dart 侧 `IosNetworkEnvDetector` 的 channel 名保持一致
  private static let channelName = "com.fluxdo/network_env"

  /// 触发自动压制的接口名前缀。
  ///
  /// `utun` 不在此列：utun0 是 iOS 常驻的系统接口，iCloud 私密中继、Wi-Fi 通话
  /// 也会挂 utun/ipsec 接口，单看名字会误判。utun 只按数量判定（见下），
  /// `ipsec` 同样排除（Wi-Fi 通话的 ipsec0 会误报）。
  private static let tunnelPrefixes = ["tap", "tun", "ppp"]

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getNetworkEnv":
        result(NetworkEnvHandler.snapshot())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 一次快照：`{vpnActive, proxyHost, proxyPort, pacUrl, interfaces, scopedInterfaces}`
  ///
  /// 代理地址由 Dart 侧拼装（`IosNetworkEnvDetector.normalizeProxyUrl`），
  /// 原生只返回结构化字段，避免两边各写一套格式校验。
  private static func snapshot() -> [String: Any] {
    let settings = (CFNetworkCopySystemProxySettings()?.takeRetainedValue()
      as? [String: Any]) ?? [:]
    let scoped = settings["__SCOPED__"] as? [String: Any] ?? [:]
    let interfaces = activeInterfaceNames()
    let scopedNames = Array(scoped.keys)
    let proxy = resolveProxy(settings: settings, scoped: scoped)

    return [
      "vpnActive": looksLikeVpnActive(
        interfaces: interfaces,
        scopedInterfaces: scopedNames
      ),
      "proxyHost": proxy.host ?? NSNull(),
      "proxyPort": proxy.port.map { NSNumber(value: $0) } ?? NSNull(),
      "pacUrl": proxy.pac ?? NSNull(),
      "interfaces": interfaces,
      "scopedInterfaces": scopedNames,
    ]
  }

  // MARK: - VPN 判定

  /// 接口名或作用域名里出现 tap/tun/ppp，或 utun 接口数 ≥ 2，视为隧道已建立
  static func looksLikeVpnActive(
    interfaces: [String],
    scopedInterfaces: [String]
  ) -> Bool {
    let names = Set(interfaces).union(scopedInterfaces)
    let lowered = names.map { $0.lowercased() }.filter { !$0.isEmpty }
    if lowered.contains(where: { name in
      tunnelPrefixes.contains { name.hasPrefix($0) }
    }) {
      return true
    }
    // utun0 常驻；出现第二个 utun* 说明有隧道建立
    return lowered.filter { $0.hasPrefix("utun") }.count >= 2
  }

  // MARK: - 系统代理

  /// 读取固定代理与 PAC。顶层是全局设置；Wi-Fi 手动代理也可能只写在
  /// `__SCOPED__.en0` 下，所以两处都看。
  private static func resolveProxy(
    settings: [String: Any],
    scoped: [String: Any]
  ) -> (host: String?, port: Int?, pac: String?) {
    var candidates: [[String: Any]] = [settings]
    if let en0 = scoped["en0"] as? [String: Any] {
      candidates.append(en0)
    }

    var pac: String?
    for dict in candidates {
      if pac == nil,
        let pacUrl = dict["ProxyAutoConfigURLString"] as? String,
        !pacUrl.trimmingCharacters(in: .whitespaces).isEmpty
      {
        pac = pacUrl
      }
      if let fixed = fixedProxy(dict) {
        return (fixed.host, fixed.port, pac)
      }
    }
    return (nil, nil, pac)
  }

  /// 固定代理地址。优先 HTTPS（CFNetwork 的 HTTPSProxy 即 CONNECT 代理），
  /// 其次 HTTP
  private static func fixedProxy(_ dict: [String: Any]) -> (host: String, port: Int)? {
    let fields = [
      ("HTTPSEnable", "HTTPSProxy", "HTTPSPort"),
      ("HTTPEnable", "HTTPProxy", "HTTPPort"),
    ]
    for (enableKey, hostKey, portKey) in fields {
      guard number(dict[enableKey]) != 0,
        let host = dict[hostKey] as? String,
        !host.isEmpty,
        let port = number(dict[portKey]),
        port > 0,
        port <= 65535
      else { continue }
      return (host, port)
    }
    return nil
  }

  private static func number(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
  }

  // MARK: - 接口枚举

  /// 当前处于 UP 状态的接口名（去重、保序）
  private static func activeInterfaceNames() -> [String] {
    var names: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return names }
    defer { freeifaddrs(ifaddr) }

    var cursor = first
    while true {
      let flags = cursor.pointee.ifa_flags
      if (flags & UInt32(IFF_UP)) != 0 {
        let name = String(cString: cursor.pointee.ifa_name)
        if !name.isEmpty && !names.contains(name) {
          names.append(name)
        }
      }
      guard let next = cursor.pointee.ifa_next else { break }
      cursor = next
    }
    return names
  }
}
