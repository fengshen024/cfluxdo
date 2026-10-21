import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/webview_egress_family_service.dart';

void main() {
  group('cdn-cgi/trace 解析', () {
    test('取 ip= 行', () {
      const trace = 'fl=123f45\nh=linux.do\nip=203.0.113.7\n'
          'ts=1700000000.123\nvisit_scheme=https\nuag=Mozilla\n';
      expect(WebViewEgressFamilyService.parseTraceIp(trace), '203.0.113.7');
    });

    test('IPv6 出口', () {
      const trace = 'ip=2001:db8::1\nts=1700000000.123\n';
      expect(WebViewEgressFamilyService.parseTraceIp(trace), '2001:db8::1');
    });

    test('CRLF 换行同样能解析', () {
      const trace = 'fl=123f45\r\nh=linux.do\r\nip=198.51.100.9\r\nts=1\r\n';
      expect(WebViewEgressFamilyService.parseTraceIp(trace), '198.51.100.9');
    });

    test('没有 ip= 或空值返回 null', () {
      expect(WebViewEgressFamilyService.parseTraceIp(null), isNull);
      expect(WebViewEgressFamilyService.parseTraceIp(''), isNull);
      expect(WebViewEgressFamilyService.parseTraceIp('h=linux.do\n'), isNull);
      expect(WebViewEgressFamilyService.parseTraceIp('ip=\n'), isNull);
    });
  });

  group('出口地址族判定', () {
    test('IPv4 / IPv6', () {
      expect(WebViewEgressFamilyService.familyOfIp('203.0.113.7'), isFalse);
      expect(WebViewEgressFamilyService.familyOfIp('2001:db8::1'), isTrue);
    });

    test('非法或缺失返回 null', () {
      expect(WebViewEgressFamilyService.familyOfIp(null), isNull);
      expect(WebViewEgressFamilyService.familyOfIp(''), isNull);
      expect(WebViewEgressFamilyService.familyOfIp('not-an-ip'), isNull);
      // CF 的 trace 在异常出口下可能返回空串或占位
      expect(WebViewEgressFamilyService.familyOfIp('   '), isNull);
    });
  });
}
