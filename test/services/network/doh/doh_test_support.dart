/// DoH 相关测试共用的平台打桩。
///
/// `flutter test` 跑在纯 Dart VM 上，没有插件实现。而
/// [CertPreferenceService.isPerDeviceRequired] 在 Windows 上为 true，
/// DoH 初始化会走 per-device CA 分支，一路调到 `path_provider` 的
/// MethodChannel —— 于是这三个用例只在 Windows 上炸（Linux CI 上走
/// 内置 CA 分支，根本不碰 path_provider）。
///
/// 这里给 path_provider 换一个落在系统临时目录的假实现，让同一套测试
/// 在 Windows 本地也能跑绿，不必为平台差异维护两份期望。
library;

import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 指向系统临时目录下的一个专属子目录的假实现。
class FakePathProvider extends PathProviderPlatform {
  FakePathProvider({this.root});

  /// 根目录；为空时用系统临时目录下的 `fluxdo_test_support`。
  final String? root;

  String get _base => root ?? '${Directory.systemTemp.path}/fluxdo_test_support';

  @override
  Future<String?> getTemporaryPath() async => _base;

  @override
  Future<String?> getApplicationSupportPath() async => _base;

  @override
  Future<String?> getApplicationDocumentsPath() async => _base;

  @override
  Future<String?> getApplicationCachePath() async => _base;

  @override
  Future<String?> getDownloadsPath() async => _base;
}

/// 安装 [FakePathProvider]，返回一个还原函数。
///
/// 只在需要碰 path_provider 的用例里调用：全局替换 instance 会影响
/// 同进程的其他测试文件。
Future<void Function()> useFakePathProvider() async {
  final previous = PathProviderPlatform.instance;
  PathProviderPlatform.instance = FakePathProvider();
  return () => PathProviderPlatform.instance = previous;
}
