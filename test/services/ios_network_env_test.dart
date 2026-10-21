import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/ios_network_env.dart';
import 'package:fluxdo/services/network/vpn_auto_toggle_service.dart';

void main() {
  group('iOS 隧道接口识别', () {
    test('tap/tun/ppp 前缀直接判为隧道', () {
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['en0', 'tap0'],
          scopedInterfaces: const [],
        ),
        isTrue,
      );
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['en0', 'tun1'],
          scopedInterfaces: const [],
        ),
        isTrue,
      );
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['en0', 'ppp0'],
          scopedInterfaces: const [],
        ),
        isTrue,
      );
    });

    test('只有常驻 utun0 时不算 VPN', () {
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['lo0', 'en0', 'utun0'],
          scopedInterfaces: const ['en0'],
        ),
        isFalse,
      );
    });

    test('出现第二个 utun 视为隧道已建立', () {
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['en0', 'utun0', 'utun3'],
          scopedInterfaces: const [],
        ),
        isTrue,
      );
    });

    test('ipsec 不触发（Wi-Fi 通话会挂 ipsec 接口）', () {
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['en0', 'ipsec0'],
          scopedInterfaces: const ['ipsec0'],
        ),
        isFalse,
      );
    });

    test('作用域名也参与判定', () {
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['en0'],
          scopedInterfaces: const ['en0', 'tap0'],
        ),
        isTrue,
      );
    });

    test('大小写与重复不影响计数', () {
      // 同一个 utun 在两张列表里都出现时不能重复计数
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['en0', 'utun0'],
          scopedInterfaces: const ['en0', 'utun0'],
        ),
        isFalse,
      );
      expect(
        IosNetworkEnvDetector.looksLikeVpnActive(
          interfaces: const ['EN0', 'TAP0'],
          scopedInterfaces: const [],
        ),
        isTrue,
      );
    });
  });

  group('iOS 系统代理解析', () {
    test('合法 host:port 拼成 http URL', () {
      expect(
        IosNetworkEnvDetector.normalizeProxyUrl(host: '127.0.0.1', port: 7890),
        'http://127.0.0.1:7890',
      );
      expect(
        IosNetworkEnvDetector.normalizeProxyUrl(host: '10.0.0.2', port: '1080'),
        'http://10.0.0.2:1080',
      );
      // 原生经 MethodChannel 传过来的是 NSNumber
      expect(
        IosNetworkEnvDetector.normalizeProxyUrl(host: '127.0.0.1', port: 7890.0),
        'http://127.0.0.1:7890',
      );
    });

    test('非法输入返回 null', () {
      expect(IosNetworkEnvDetector.normalizeProxyUrl(host: null, port: 1), isNull);
      expect(
        IosNetworkEnvDetector.normalizeProxyUrl(host: '', port: 7890),
        isNull,
      );
      expect(
        IosNetworkEnvDetector.normalizeProxyUrl(host: '127.0.0.1', port: 0),
        isNull,
      );
      expect(
        IosNetworkEnvDetector.normalizeProxyUrl(host: '127.0.0.1', port: 70000),
        isNull,
      );
      expect(
        IosNetworkEnvDetector.normalizeProxyUrl(host: '127.0.0.1', port: 'x'),
        isNull,
      );
    });

    test('fromMap 解析原生快照', () {
      final env = IosNetworkEnv.fromMap({
        'vpnActive': true,
        'proxyHost': '127.0.0.1',
        'proxyPort': 7890,
        'pacUrl': null,
        'interfaces': ['en0', 'utun2'],
        'scopedInterfaces': ['en0'],
      });
      expect(env.vpnActive, isTrue);
      expect(env.proxyUrl, 'http://127.0.0.1:7890');
      expect(env.pacUrl, isNull);
      expect(env.proxyEnabled, isTrue);
      expect(env.interfaces, ['en0', 'utun2']);
    });

    test('PAC-only 也算系统代理已启用', () {
      const env = IosNetworkEnv(pacUrl: 'http://pac.local/p.pac');
      expect(env.proxyUrl, isNull);
      expect(env.proxyEnabled, isTrue);
    });
  });

  group('iOS 隧道信号并入 VPN 判定', () {
    test('隧道信号参与 vpnActive 展示', () {
      expect(
        VpnAutoToggleService.resolveVpnActive(
          connectivityResults: const [ConnectivityResult.wifi],
          hasWindowsVpnAdapter: false,
          hasIosTunnel: true,
        ),
        isTrue,
      );
      expect(
        VpnAutoToggleService.resolveVpnActive(
          connectivityResults: const [ConnectivityResult.wifi],
          hasWindowsVpnAdapter: false,
          hasIosTunnel: false,
        ),
        isFalse,
      );
    });

    test('iOS 隧道触发自动压制，其它平台信号不扩大范围', () {
      expect(
        VpnAutoToggleService.shouldAutoSuppress(
          const [ConnectivityResult.wifi],
          hasIosTunnel: true,
        ),
        isTrue,
      );
      expect(
        VpnAutoToggleService.shouldAutoSuppress(
          const [ConnectivityResult.wifi],
          hasIosTunnel: false,
        ),
        isFalse,
      );
      // connectivity_plus 在 iOS 上不会报告 vpn，没有原生信号时恒为 false
      expect(
        VpnAutoToggleService.shouldAutoSuppress(const [
          ConnectivityResult.wifi,
          ConnectivityResult.other,
        ]),
        isFalse,
      );
    });

    test('强制判定模式仍然覆盖 iOS 隧道信号', () {
      expect(
        VpnAutoToggleService.resolveDetection(
          automaticValue: true,
          mode: VpnDetectionMode.forceInactive,
        ),
        isFalse,
      );
    });
  });
}
