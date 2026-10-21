# iOS 构建、安装与平台差异

cfluxdo 的 iOS 工程重建自上游 FluxDO `v0.2.28`（与项目锁定的 Flutter 3.44.8 同一套
工具链），最低支持 **iOS 15.0**。cfluxdo 自己的连接方式（本地优选、ECH、cfhub
「帮助优选」、DoH 加速线路、掉登录/弹盾修复）都是平台无关的 Dart + Rust 代码，在
iOS 上原样保留。

> 说明：本文档里的构建命令都需要在 macOS 上执行。Windows 上只能改代码，
> 不能 `pod install`、不能编译 Rust 的 Apple target，也跑不了 Xcode。

## 1. 工程来源与关键决策

| 项目 | 选择 | 原因 |
| --- | --- | --- |
| iOS 工程基线 | 上游 `v0.2.28` 的 `ios/` | 与 `.fvmrc` 锁定的 Flutter 3.44.8 匹配；`AppDelegate` 走经典 `GeneratedPluginRegistrant.register(with: self)` + `window?.rootViewController` |
| 上游 `main` 的 `ios/` | 未采用 | 需要 Flutter 3.47 的 `FlutterImplicitEngineDelegate` 与 `SceneDelegate`，当前工具链编不过 |
| 部署目标 | 15.0 | 用户设备要求；`Podfile` 与 `project.pbxproj` 三处 `IPHONEOS_DEPLOYMENT_TARGET` 已同步 |
| 包名 | `com.github.molchuan.cfluxdo` | 与 Android `applicationId` 一致；`RunnerTests` 用 `.RunnerTests` 后缀 |
| 显示名 | `cfluxdo` | 与 Android `android:label` 一致 |
| 签名 | 走 `apple/Local.xcconfig` | 共享 `pbxproj` 不写死 `DEVELOPMENT_TEAM` |

## 2. 依赖与原生库

### 2.1 Dart 依赖

iOS 需要的插件与 Android 共用同一份 `pubspec.yaml`，没有 iOS 专属分支。后台通知用
`workmanager`：

- 声明为 `workmanager: ^0.10.10`（pub 上的最新稳定版），iOS 侧解析到
  `workmanager_apple 0.9.11`。0.10.x 要求 Flutter ≥ 3.38，本项目 3.44.8 满足。
- `AppDelegate` 用的是 `registerPeriodicTask(withIdentifier:earliestBeginInSeconds:)`
  —— 0.9.11 里 `frequency:` 变体已标记 deprecated，新变体等价（`frequency` 只是转发）。
- 升级 `workmanager` 时要一起验证 `AppDelegate` 里这两个静态方法仍在。

### 2.2 Rust 静态库（`core/doh_proxy`）

iOS 没有动态库分发，Rust 侧用 `staticlib` 静态链接进主二进制，Dart 通过
`DynamicLibrary.process()` 取符号（见 `lib/services/network/doh_proxy/doh_proxy_ffi.dart`）。

构建命令（`tool/project_tasks.dart` 已封装）：

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
dart run tool/project_tasks.dart native:prepare ios --release
```

产物落到：

```
ios/rust_libs/device/libdoh_proxy.a      # aarch64-apple-ios
ios/rust_libs/simulator/libdoh_proxy.a   # aarch64-apple-ios-sim
```

`ios/rust_libs/` 已在 `.gitignore` 里，不入库。`project.pbxproj` 按 SDK 分别
`-force_load` 这两个文件（`OTHER_LDFLAGS[sdk=iphoneos*]` /
`[sdk=iphonesimulator*]`），所以**必须先落盘再 build**，否则链接会报找不到符号。

`dart tool/flutterw.dart build ios ...` 会自动识别目标平台并先跑上面的 `native:prepare`，
手工只调 `flutter build ios` 时不会。

## 3. 构建

### 3.1 前置

- macOS + Xcode 15 或更新（Xcode 26 也能构建 iOS 15 目标，但会提示 UIScene 迁移，见 §6）
- CocoaPods
- Flutter 3.44.8（仓库有 `.fvmrc`）、Dart SDK ^3.10.4
- Rust 工具链 + 上面两个 Apple target
- 首次构建前：

```bash
dart run melos bootstrap
dart run tool/project_prep.dart app      # pub get + l10n + 代理证书
cd ios && pod install && cd ..
```

> `ios/Podfile.lock` 没有入库（换掉 `SwiftTryCatch` 依赖后旧锁文件已失效），
> 第一次 `pod install` 会重新生成，之后建议提交。

### 3.2 签名配置（可选，真机必需）

```bash
cp apple/Local.xcconfig.example apple/Local.xcconfig
```

在 `apple/Local.xcconfig` 里填：

```xcconfig
FLUXDO_APPLE_DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

`apple/Local.xcconfig` 已被 `.gitignore` 忽略，属于本机配置。不填时 `DEVELOPMENT_TEAM`
为空，只能做 `--no-codesign` 构建（出 IPA 用自签工具安装）。

### 3.3 无签名 IPA

```bash
just ipa                 # 交互式确认版本
# 或
dart run tool/build_ipa_nosign.dart 1.1.0 -y
```

产物：`build/ios/ipa/cfluxdo-<版本>-nosign.ipa`。脚本内部调用
`tool/flutterw.dart build ios --release --no-codesign`，因此 Rust 静态库会自动准备好。

### 3.4 在 GitHub Actions 上构建（没有 Mac 时）

`.github/workflows/ios-ipa.yaml` 在 `macos-15` runner 上跑同一条
`tool/build_ipa_nosign.dart` 链路，产物作为 Actions Artifact 下载；推 `v*` tag
且 Release 已存在时还会自动 `gh release upload`。

- 手动触发：Actions → **iOS 无签名 IPA** → Run workflow，`version` 可留空
- 工具链：Flutter 版本读 `.fvmrc`，Rust 额外装 `aarch64-apple-ios` 与
  `aarch64-apple-ios-sim`，`Swatinem/rust-cache` 缓存 `core/doh_proxy/target`
- 不涉及签名：`apple/Local.xcconfig` 不存在时 `DEVELOPMENT_TEAM` 解析为空，
  `--no-codesign` 直接可用，仓库里不需要放任何证书或密码

安装步骤见 [sideloadly.md](sideloadly.md)。

### 3.5 子模块与 iOS 改动

iOS 移植的 Rust 部分（`forced_family`、`doh_proxy_set_forced_family`）在
`core/doh_proxy` 子模块里，指向 `cfluxdo` 分支。CI 按子模块**已推送的提交**构建，
所以：

- 只改本地子模块不推送 → CI 出的 IPA 里没有 `doh_proxy_set_forced_family`，
  WebView 出口对齐失效（工作流会给 `::warning::`，不会失败）
- 推送子模块后，还要在主仓库把 `core/doh_proxy` 的新提交号提交进去，CI 才会用上

### 3.6 直接用 Xcode 跑真机

1. `open ios/Runner.xcworkspace`
2. 选 Runner target → Signing & Capabilities → 选自己的 Team
3. 连真机运行

`Runner.entitlements` 里**只有注释**：原先的 `com.apple.developer.web-browser`
（EU DMA 的默认浏览器 entitlement）已移除——它需要 Apple 单独批准，免费个人账号
签不了，而 cfluxdo 也不注册为系统默认浏览器、不用 BrowserEngineKit。

## 4. 安装到自己的 iPhone

没有 App Store / TestFlight，只有无签名 IPA：

- **Sideloadly**：Windows / macOS 都能用，用 Apple ID 自签。完整步骤（含 Windows
  上要先装 iTunes + iCloud、双重认证的专用密码、覆盖安装保留数据）见
  [sideloadly.md](sideloadly.md)
- **AltStore / Sidekick**：电脑装 AltServer，同一 Wi-Fi 下自动 7 天续签
- 付费开发者账号（$99/年）签名有效期 1 年

首次打开需要在「设置 → 通用 → VPN与设备管理」里信任开发者证书。免费账号最多同时
签 3 个 App、每个 App 最多 3 台设备，证书 7 天过期。

## 5. iOS 上的功能差异

### 5.1 保留的 cfluxdo 特性

| 特性 | iOS 状态 |
| --- | --- |
| 本地动态优选（Cloudflare 节点竞速 + ECH） | 可用，`selectorEligible` 已放开 iOS |
| cfhub「帮助优选」上报 | 可用（纯 Dart，无平台判断） |
| DoH 加速线路 / 加速令牌 | 可用 |
| 掉登录修复（`session_token_lineage`） | 可用 |
| 弹盾处理（`cf_clearance` 刷新、Turnstile） | 可用 |
| 本地网关（Dio 请求改写 `127.0.0.1:port`） | 可用 |

网关模式的原理：`platform_adapter.dart` 的 `_GatewayAdapterWrapper` 在传输层把
`https://linux.do/...` 改写成 `http://127.0.0.1:<port>/...` 并带上原始 `Host` 头，
TLS 在 Rust 侧完成。`dart:io` 的 `HttpClient` 不走 NSURLSession，所以 ATS 不参与，
`Info.plist` 不需要 `NSAppTransportSecurity` 例外。

### 5.2 已知限制

1. **WebView 内的流量不走本地网关**（iOS 17 以下）。`flutter_inappwebview` 的
   `ProxyController.setProxyOverride` 需要 iOS 17+；`_applyWebViewProxy` 在更低版本
   直接返回。因此 API 请求（Dio）走优选 / ECH / 网关，站内网页（WebView）走系统
   网络。出口不一致会让 Cloudflare 把两边当成两个会话（`cf_clearance` 绑 IP），
   掉登录和弹盾比 Android 频繁。已做两层缓解：

   - **VPN / 系统代理自动压制**（`VpnAutoToggleService`）。`connectivity_plus` 在
     iOS 上底层是 `NWPathMonitor`，永远不会返回 `ConnectivityResult.vpn`，所以
     原来的自动压制在 iOS 上是死代码。现在由原生 `NetworkEnvHandler` 读
     `getifaddrs()` 与 `CFNetworkCopySystemProxySettings()`，Dart 侧
     `IosNetworkEnvService` 每 10 秒兜底轮询一次：发现 `tap`/`tun`/`ppp` 接口或
     第二个 `utun*`（`utun0` 常驻，`ipsec` 是 Wi-Fi 通话，都不算）就按 VPN 处理，
     自动关掉 DoH 与上游代理，让 API 也退回系统网络——两边同一个出口，与
     Android 的压制语义一致；VPN 断开后按压制标记恢复。
   - **双栈地址族对齐**（`WebViewEgressFamilyService`）。没有 VPN、但网络是双栈
     时，API 和 WebView 可能一个走 v4 一个走 v6，出口 IP 依然不同。iOS 17 以下
     App 无法给 WebView 设代理，于是反过来让 API 跟随 WebView：启动、换网或网关
     状态变化后，用一个临时 Headless WebView 请求 `/cdn-cgi/trace`（带站点
     Cookie，与应用内请求同源），读回 WebView 真实出口 IP，判断地址族，再通过
     FFI `doh_proxy_set_forced_family` 把 Rust 侧（DoH 解析、建连、优选赢家）
     压到同一族。同一网络环境下 30 分钟内不重复探测。

   两层都只影响地址族/传输选择，不改变会话；剩下的限制是同族不同地址（例如
   IPv4 出口 IP 因 NAT 变化）仍会被 CF 视为换 IP，这类情况只能靠 VPN 全局接管。
2. **后台通知是机会式调度**。iOS 用 `BGTaskScheduler` 的 `BGAppRefreshTask`，
   系统按使用习惯决定什么时候跑，最短约 15 分钟，可能几小时不跑。App 被用户
   从多任务里划掉后不再唤醒。
3. **没有应用内更新**。Android 的 APK 下载安装（`ota_update`）在 iOS 不存在，
   「检查更新」会打开 GitHub Release 页面，由用户自己下载 IPA 重新自签。
4. **后台任务里的插件需要显式注册**。`AppDelegate` 里必须保留
   `WorkmanagerPlugin.setPluginRegistrantCallback { GeneratedPluginRegistrant.register(with: $0) }`，
   否则后台 Isolate 里的 `shared_preferences`、`flutter_local_notifications`
   全是 `MissingPluginException`。
5. **iOS 26 SDK 的 UIScene 警告**。用 Xcode 26 构建会打印
   「UIScene lifecycle will soon be required」。当前工程用的是经典 AppDelegate
   生命周期，在 iOS 15–26 上都能跑；等 Apple 在新系统里强制 UIScene（预计 iOS 27）
   时需要把 `AppDelegate` 迁到 `SceneDelegate` + `FlutterImplicitEngineDelegate`，
   可以参照上游 `main` 分支的 `ios/Runner/AppDelegate.swift`。

### 5.3 证书安装

iOS 上 per-device CA 是强制的（`CertPreferenceService.isPerDeviceRequired`）。
「设置 → 网络 → DNS over HTTPS」里点安装，会走 `com.fluxdo/profile_install`
把 `.mobileconfig` 通过本地 HTTP 服务交给 Safari 安装，然后在
「设置 → 通用 → 关于本机 → 证书信任设置」里手动开启完全信任。
`DohProxyCertHandler.swift` 会 swizzle `flutter_inappwebview` 的
`webView:didReceiveAuthenticationChallenge:completionHandler:`，在原生层直接信任
这个 CA，避免 Dart 通道往返导致握手超时。

## 6. 这次移植改了哪些文件

Dart 侧（相对 Android-only 时期的 cfluxdo 新增/改动）：

- `pubspec.yaml`：新增 `workmanager`
- `lib/services/background/background_notification_service.dart`：按平台分派
  Android 前台服务 / iOS BGTaskScheduler
- `lib/services/background/ios_background_fetch.dart`：后台单次轮询（新增）
- `lib/providers/message_bus/topic_tracking_providers.dart`：把 MessageBus 域名
  与会话密钥落盘给后台 Isolate
- `lib/services/network/doh/network_settings_service.dart`：`selectorEligible` 放开 iOS
- `lib/services/network/ios_network_env.dart`：iOS VPN / 系统代理原生快照与轮询（新增）
- `lib/services/network/webview_egress_family_service.dart`：WebView 出口地址族探测
  与 `forced_family` 下发（新增）
- `lib/services/network/vpn_auto_toggle_service.dart`：接入 iOS 隧道信号
- `lib/services/network/system_proxy_service.dart`：Windows 之外增加 iOS
- `lib/services/network/doh_proxy/doh_proxy_{ffi,service}.dart`：`setForcedFamily`
- `lib/main.dart`：本地优选首次说明在 iOS 上也弹；启动时读 iOS 网络环境、
  `primePlatformCapabilities()`、启动出口地址族对齐

iOS 原生侧：

- `ios/Runner/AppDelegate.swift`：插件 registrant 回调 + 新版 `registerPeriodicTask`
- `ios/Runner/NetworkEnvHandler.swift`：`com.fluxdo/network_env` 通道，读
  `getifaddrs()` / `CFNetworkCopySystemProxySettings()`（新增）
- `ios/Runner/Info.plist`：`CFBundleDisplayName` / `CFBundleName` → `cfluxdo`
- `ios/Runner/Runner.entitlements`：移除 `com.apple.developer.web-browser`
- `ios/Runner.xcodeproj/project.pbxproj`：部署目标 15.0、包名；登记 `NetworkEnvHandler.swift`
- `core/doh_proxy/src/{dns,select,ech,ffi}.rs`：运行时 `forced_family`（优先级高于
  建连亲和与 `prefer_ipv6`），导出 `doh_proxy_set_forced_family`
- `ios/Podfile`：部署目标 15.0、移除不再需要的 `SwiftTryCatch`
- `ios/Podfile.lock`：删除，待 macOS 上重新生成

## 7. 首次验收清单

这台开发机（Windows）没有 Flutter / Dart SDK，以下步骤都**没有在本地执行过**。
其中 `flutter analyze` / `flutter test` / iOS 构建现在也可以直接看 GitHub Actions：

- **Dart 检查**（`dart-check.yaml`）：推 `main` 与 PR 自动跑，等价于
  `flutter analyze` + `dart run tool/project_tasks.dart test:all`
- **iOS 无签名 IPA**（`ios-ipa.yaml`）：手动 Run workflow，等价于下面的
  `native:prepare ios --release` + `build ios --no-codesign`

剩下的（`pod install` 的具体输出、真机行为）仍需 macOS + 真机：

```bash
dart run melos bootstrap
dart run tool/project_prep.dart app
flutter analyze
flutter test
dart run tool/project_tasks.dart native:prepare ios --release
cd ios && pod install && cd ..
dart tool/flutterw.dart build ios --release --no-codesign
```

真机验收重点：

1. 首次启动能连上 linux.do（本地优选拿到赢家，或回退 DoH 加速线路）
2. 「设置 → 网络」里本地优选卡片能显示赢家与重测按钮
3. DoH 开启后安装 CA，WebView 打开站内页面不报证书错误
4. 切后台再回来，登录态与 `_t` 不丢
5. 后台通知在系统允许的前提下能收到（`BGTaskScheduler` 调度，不保证准时）
6. 开系统 VPN 后「设置 → 网络」显示 VPN 活跃、DoH 被压制；关 VPN 后自动恢复
7. 日志里出现 `[EgressFamily] WebView 出口 <ip>`：该 IP 的地址族与随后 API
   建连的地址族一致（`select: winner` 行的 IP 同族）
