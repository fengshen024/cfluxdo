# cfluxdo

> 面向国内网络环境的 [Linux.do](https://linux.do/) 第三方 Android / iOS 客户端，参考 [cfluxdo](https://github.com/1molchuan/fluxdo) 与 [FluxDO](https://github.com/Lingyan000/fluxdo) 两个项目

[![GitHub Release](https://img.shields.io/github/v/release/1molchuan/fluxdo?style=for-the-badge&logo=github&label=GitHub%20Releases)](https://github.com/1molchuan/fluxdo/releases)
[![Platform](https://img.shields.io/badge/platform-Android%20arm64%20%7C%20armv7%20%7C%20iOS%2015%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/1molchuan/fluxdo/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue?style=for-the-badge)](LICENSE)

cfluxdo 源自 FluxDO 0.2.28，已脱离 fork 关系独立维护。它保留了 FluxDO 的全部论坛功能与界面，重点解决国内网络下访问 linux.do 时遇到的 DNS 污染、频繁弹 Cloudflare 验证、无征兆掉登录等问题。主力平台是 Android；iOS 侧在 0.2.28 的工程上重建，最低支持 iOS 15，cfluxdo 的连接方式（本地优选、ECH、cfhub 帮助优选）在 iOS 上同样可用，差异见 [docs/ios.md](docs/ios.md)。

## 下载安装

- 到 [Releases](https://github.com/1molchuan/fluxdo/releases) 下载对应架构的安装包，旁边有同名的 `.sha256` 校验文件：
  - `cfluxdo-<版本>-arm64-v8a.apk`：64 位 ARM，2015 年以后的手机几乎都是，优先选这个。
  - `cfluxdo-<版本>-armeabi-v7a.apk`：32 位 ARM，只给装不上 arm64 包（报 `INSTALL_FAILED_NO_MATCHING_ABIS`）的老机器。
- 包名是 `com.github.molchuan.cfluxdo`，与官方 FluxDO 不同：两者可以并存，但不能互相覆盖安装，登录态和设置也互不相通。
- 应用内「关于 → 检查更新」会从本仓库的 Releases 获取新版本，并按手机架构挑选安装包。
- iOS 目前只提供无签名 IPA（`cfluxdo-<版本>-nosign.ipa`），需要用 AltStore、Sideloadly 等工具用你自己的 Apple ID 自签安装；没有上架 App Store，也没有 TestFlight。没有 Mac 也可以：推 tag 或手动运行 GitHub Actions 的 **iOS 无签名 IPA** 工作流，从 Artifacts 下载 IPA，再用 [Sideloadly 安装](docs/sideloadly.md)。构建与平台差异见 [docs/ios.md](docs/ios.md)。

## 它怎么连接 linux.do

从 1.1.0 起，cfluxdo 默认不依赖任何中转服务，由 App 自己在 Cloudflare 共享池里找能连上 linux.do 的节点：

1. **取候选**：向公共 DNS（DNSPod、AliDNS、360、Cloudflare、Google、Quad9 等，直连 IP、并发竞速）查询若干托管在 Cloudflare 上的大厂站点，加上社区维护的节点表 atlas，再从 Cloudflare 公布的网段随机抽样。答案不在 Cloudflare 网段内的一律丢弃，防 DNS 投毒。公共 DNS 从不查询 `linux.do` 本身。
2. **竞速**：对候选并发做 ECH 加密握手（内层 SNI 为 linux.do，明文 SNI 在国内会被重置）并请求 `/cdn-cgi/trace`，响应里 `h=linux.do` 才算通过，最快的记为赢家并落盘。
3. **使用**：之后 linux.do 及其所有子域都走赢家这一个节点、同一个地址族，保证 Cloudflare 看到的出口 IP 不变。Cloudflare 换 ECH 钥匙时，用服务端返回的 retry_configs 当场换钥匙重试，不等 DNS 刷新。
4. **重测时机**：切换网络、赢家连续失败、或在设置里手动点「重新优选」。没有定时重测，也没有后台任务。单次竞速约 50–200 KB 流量。

「设置 → 网络 → 连接方式」可以改为「只用 atlas 池」。两种方式都拿不到候选时，自动回退到原有的 DoH 加速线路，仍然连不上则回退系统 DNS，不会因此打不开 App。

## 与 FluxDO 的差异

- **连接方式**：上面的本地优选替代了对加速服务端的依赖；原有的 DoH 加速线路降为兜底。
- **弹盾与掉登录**：针对 Cloudflare 验证页、`cf_clearance` 与登录 Cookie `_t` 的轮换做了一系列修复，详见各版本的 Release 说明。
- **平台**：只保留 Android 与 iOS；桌面、Web 的平台代码，以及 Cronet 网络引擎和 Firebase 崩溃上报都已移除。崩溃排查依靠应用内的日志导出。iOS 上 WebView 内的流量无法走本地网关（iOS 17 以下没有 WebView 代理 API），只有 API 请求享受优选/ECH；为避免两边出口 IP 不一致导致掉登录/弹盾，iOS 侧会检测系统 VPN 与代理（检测到即自动压制 DoH 与上游代理），并用 WebView 实测出口地址族，把 API 压到同一族。
- **上游补丁**：挑选上游尚未合并的 PR 一并接入，保留原作者署名。

## 隐私

- 本地优选向公共 DNS 发出的只是域名查询本身，不附带 Cookie、令牌等任何账号信息，也不查询 `linux.do`。
- **「帮助优选」默认关闭**。打开后 App 会把本来就做的握手测量结果（候选节点地址、握手耗时、是否成功）分享给社区节点站 [cfhub](https://github.com/1molchuan/cfhub)，帮同运营商的其他用户更快找到节点。开启需要用 linux.do 账号通过 Connect 授权 cfhub（与在 cfhub 网页上加入相同，需信任等级 1 以上）；分享内容不含 Cookie、令牌、设备标识或浏览记录；cfhub 记录你的 linux.do 用户名、信任等级和上报归属的运营商与地区，不保存你的完整 IP 地址；随时可关，关闭即作废授权。
- 首次启动 1.1 会弹一次说明，列出以上内容。
- 没有崩溃上报、统计或任何遥测 SDK。论坛流量由手机直接连接 linux.do。

## 从源码构建

前置要求：

- Flutter 3.44（Dart SDK ^3.10.4）、Android SDK、NDK 27.3
- Rust 工具链、`cargo-ndk`，以及 `aarch64-linux-android`、`armv7-linux-androideabi` 两个 target，用于编译 `core/doh_proxy`
- `just`（可选，仅作为本地命令入口）

```bash
git clone https://github.com/1molchuan/fluxdo.git
cd fluxdo
dart run melos bootstrap                 # 初始化 workspace
dart run tool/project_prep.dart app      # pub get、l10n 生成、代理证书同步，等价于 just sync
dart tool/flutterw.dart build apk --release --target-platform android-arm64 \
  --build-name 1.1.0 --build-number 2026101505
dart tool/flutterw.dart build apk --release --target-platform android-arm \
  --build-name 1.1.0 --build-number 2026101505
```

`flutterw` 会在构建前用 `cargo ndk` 编译对应架构的 Rust 库并放进 `android/app/src/main/jniLibs/`。两个架构各出一个 APK，不出合并包。

iOS 只能在 macOS 上构建，前置要求额外多两项：Xcode 15+、`aarch64-apple-ios` 与 `aarch64-apple-ios-sim` 两个 Rust target。`flutterw build ios` 会用 `cargo rustc --crate-type staticlib` 编出 `ios/rust_libs/{device,simulator}/libdoh_proxy.a` 供 Xcode 静态链接（FFI 通过 `DynamicLibrary.process()` 取符号）。打包无签名 IPA：

```bash
dart run tool/build_ipa_nosign.dart
```

详细步骤、签名配置与 iOS 15 上的功能差异见 [docs/ios.md](docs/ios.md)。

没有 Mac 时用 GitHub Actions 出包：Actions → **iOS 无签名 IPA** → Run workflow，
跑完在 Artifacts 里下载 `cfluxdo-ipa-<ref>`，解压即 IPA；安装见
[docs/sideloadly.md](docs/sideloadly.md)。

版本号约定：`--build-name` 是用户可见的版本号，`--build-number` 用「日期 + 两位序号」且只增不减。Git tag 与版本号一致，不带 `v` 前缀。预发布版本带 `-beta` 一类后缀，GitHub Release 标为 Pre-release；App 内的更新检查只看正式版（Latest），不会推送预发布版本。

两个原本是子模块的目录，现在直接放在仓库里（单仓，`git clone` 不需要 `--recurse-submodules`）：

- `core/doh_proxy`：Rust 实现的本地优选、ECH、DoH 代理与本地网关，来自 [1molchuan/fluxdo_doh](https://github.com/1molchuan/fluxdo_doh) 的 `cfluxdo` 分支。`cargo run --example race --features ech` 可以在电脑上跑一轮竞速看结果。
- `packages/fluxdo_render`：来自 [Lingyan000/fluxdo_render](https://github.com/Lingyan000/fluxdo_render) 的渲染包

> 两者在上游都是独立仓库，这里只做了快照合并，方便一次 clone 完；它们的上游仍在独立演进，需要同步时按上游仓库手动合并。

更多开发细节见 [docs/development.md](docs/development.md)。部分文档仍是上游多平台时期的内容，正在整理。

## 项目结构

```
fluxdo/
├── android/                 # Android 工程
├── ios/                     # iOS 工程（Flutter 3.44 工具链，最低 iOS 15）
├── apple/                   # 本地 Apple 签名配置（Local.xcconfig，不入库）
├── lib/
│   ├── pages/               # 页面
│   ├── providers/           # Riverpod 状态管理
│   ├── services/            # 业务逻辑
│   │   └── network/         # 网络层：本地优选、DoH、本地网关、适配器
│   ├── widgets/             # 可复用组件
│   └── main.dart
├── core/
│   └── doh_proxy/           # Rust 本地优选与 DoH 代理（上游 fluxdo_doh）
├── packages/                # 本地依赖包
└── pubspec.yaml
```

## 问题反馈

- 提交 [Issue](https://github.com/1molchuan/fluxdo/issues)
- 在 [Linux.do](https://linux.do/) 论坛发帖讨论

反馈掉登录、弹盾类问题时，请附上「应用设置 → 日志」导出的日志，里面不含密码和 Cookie 原文。反复弹人机验证多半是出口 IP 在变：手机上开着多节点或自动切换的 VPN、ROM 的「双通道网络加速」都会造成这种情况，先关掉再试。

## 致谢与协议

本项目是 [1molchuan/fluxdo](https://github.com/1molchuan/fluxdo)（cfluxdo）与 [Lingyan000/fluxdo](https://github.com/Lingyan000/fluxdo)（FluxDO）两个项目的参考实现，感谢两位作者与所有贡献者；Rust 侧的本地优选、ECH 与 DoH 代理参考 [1molchuan/fluxdo_doh](https://github.com/1molchuan/fluxdo_doh)，渲染包参考 [Lingyan000/fluxdo_render](https://github.com/Lingyan000/fluxdo_render)。也感谢 [Linux.do](https://linux.do/) 社区。

本项目为非官方客户端，与 Linux.do 官方无直接关联。

本项目基于 [GPL-3.0](LICENSE) 协议开源。
