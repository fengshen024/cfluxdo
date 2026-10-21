# 用 Sideloadly 安装 cfluxdo（无 Mac 方案）

cfluxdo 没有上架 App Store，也没有 TestFlight。iOS 安装包是一个**未签名 IPA**，
需要用你自己的 Apple ID 现场签名后再装进 iPhone。本文走的是最省事的一条路：
**GitHub Actions 在云端 macOS 上出 IPA → 电脑用 Sideloadly 自签安装**。

整条链路不需要 Mac，只需要一台 Windows 或 macOS 电脑、一个能登录 App Store 的
Apple ID、一根数据线。

> 为什么不能像 Android 那样直接装：iOS 要求每个 App 都带有效签名。免费 Apple ID
> 也能签，但证书 7 天过期，到期后要用同一台电脑重新签一次。

## 1. 从 GitHub Actions 拿 IPA

### 1.1 让仓库先把代码推上去

IPA 由 `.github/workflows/ios-ipa.yaml` 构建，触发条件是「手动运行」或「推送
`v*` tag」。第一次用之前，确认仓库里至少有这些内容：

- `ios/` 工程、`apple/Local.xcconfig.example`、`tool/build_ipa_nosign.dart`
- `.github/workflows/ios-ipa.yaml`
- `core/doh_proxy`（Rust 源码）与 `packages/fluxdo_render`（pub workspace 成员）

两者都在主仓库里，不是子模块，`git clone` 不需要 `--recurse-submodules`。

### 1.2 手动跑一次

1. 打开仓库页面 → **Actions** → 左侧 **iOS 无签名 IPA** → **Run workflow**
2. `version` 留空即可（默认读 `pubspec.yaml` 的版本号）；想给这次构建单独标个
   版本号就填，比如 `1.1.0-test`
3. 等 20–40 分钟（首次要下 Flutter SDK 和编译 Rust，缓存命中后快很多）
4. 跑完后在该次运行的 **Artifacts** 里下载 `cfluxdo-ipa-<ref>`，解压得到
   `cfluxdo-<版本>-nosign.ipa`

### 1.3 发版时自动附带

推送 `v*` tag 后，工作流会自动构建，并且**如果对应的 Release 已经存在**，把
IPA 直接传上去（`gh release upload`）。Release 还不存在时跳过上传，只在
Artifacts 里留一份——发布日志与其它平台的产物仍由原来的发版流程负责，这里不
抢着建 Release。

### 1.4 构建日志里要看的两个点

- `校验 Rust 侧含 iOS 地址族对齐` 步骤：出现 `::warning::` 说明仓库里的
  `core/doh_proxy` 还没有 iOS 出口对齐那个导出。包照样能装能用，但 WebView 与
  API 的出口地址族不会对齐，掉登录/弹盾会比预期频繁。见 [ios.md](ios.md) §3.5。
- `构建未签名 IPA` 步骤末尾会打印 `==> IPA 已输出: build/ios/ipa/...`。

## 2. 在电脑上装 Sideloadly

到 [sideloadly.io](https://sideloadly.io/) 下载对应系统的版本（Windows / macOS
都有）。

### Windows 额外要装的两样

Sideloadly 在 Windows 上依赖 Apple 的驱动与通信组件，缺了会在「连接设备」或
「签名」阶段报错。**必须是 Apple 官网的安装包，不能装微软商店版**：

1. **iTunes**（[Apple 官网下载](https://www.apple.com/itunes/download/win64)）——
   提供 Apple Mobile Device Support 驱动
2. **iCloud for Windows**（[Apple 官网下载](https://support.apple.com/downloads/icloud)）——
   提供签名需要的组件

> 已经装了微软商店版的话，先卸载再装官网版，否则 Sideloadly 认不到。
> 官网页面在「Before you install」里写得很明确：需要 web 版 iTunes 与 iCloud。

装完重启一次，插上 iPhone，确认 iTunes / 资源管理器能看到设备。

> 只装 iTunes 不装 iCloud 是最常见的失败原因：设备能识别，但点 Start 之后卡在
> `Guru Meditation` 或直接报缺少 dll。走 Wi-Fi 无线安装时还依赖 Bonjour，
> 它随上面两个安装包一起装上。

## 3. 签名并安装

1. iPhone 用数据线连电脑，解锁屏幕，弹出「信任此电脑」时点**信任**并输入锁屏密码
2. 打开 Sideloadly，把 IPA 拖进窗口（或点 IPA 图标选择文件）
3. **Apple ID** 填你的 Apple ID 邮箱
4. 点 **Start**，按提示输入 Apple ID 密码

   如果账号开了双重认证（现在基本都开），Sideloadly 会弹出 6 位验证码输入框，
   手机上确认后把验证码填进去即可；个别情况下它会要求 **App 专用密码**，在
   [appleid.apple.com](https://appleid.apple.com/) →「登录与安全」→「App 专用密码」
   生成，不要用账号主密码。

5. 进度条走完后，手机会自动出现 cfluxdo 图标。首次启动会提示「不受信任的开发者」，
   按下一节处理。

### 装完第一次打开

**设置 → 通用 → VPN与设备管理 → 开发者 App → 你的 Apple ID → 信任**

信任后回到桌面打开 cfluxdo。如果还是提示不受信任，重启一次手机再试。

## 4. 免费 Apple ID 的限制

| 限制 | 说明 |
| --- | --- |
| 有效期 7 天 | 到期后 App 打不开（图标变灰/闪退），要用同一台电脑重新签一次 |
| 最多 3 个 App | 同时存在的自签 App 数量上限，装第 4 个要先删一个 |
| 每个 App 最多 3 台设备 | 同一份签名能装的设备数 |
| 每周 10 个 App ID | 频繁删了重装会消耗额度，删掉的 App ID 要等 7 天才真正释放 |

付费开发者账号（$99/年）签出来的证书有效期 1 年，也没有 3 个 App 的限制。
如果只是自己用，免费账号 + 每周插一次线重新签就够。

> 重新签之前先**不要**卸载 App：Sideloadly 直接覆盖安装（同 bundle id）时，
> 登录态和设置会保留；卸载重装等于清空数据。

## 5. 常见问题

**Sideloadly 提示 `Unable to connect to device` / 设备不出现**

- 换一根**能传数据**的线（很多充电线只有电源针脚）
- Windows：设备管理器里看有没有 `Apple Mobile Device (USB)`；没有就重装 iTunes
- 手机上点「信任此电脑」后重新插拔一次

**提示 `Provision.cpp:150` / `Anisette` 相关错误**

- 关掉 VPN / 代理再试，Apple 的签名接口对异常出口比较敏感
- Windows 上确认 iCloud 已安装并至少登录过一次

**安装成功但打开闪退**

- 大概率是证书没被信任，回到「VPN与设备管理」确认
- 也可能是 7 天到期了，重新签一次

**升级新版本时登录态丢了**

- 只有在「先卸载再装」时才会丢。直接拖新 IPA 覆盖安装（bundle id 相同
  `com.github.molchuan.cfluxdo`）会保留数据
- 跨大版本升级前，建议先在 App 的「设置 → 数据管理 → 数据备份」导出一份
  （备份文件含 AI API Key、代理密码等敏感信息，注意保管）

**想不插线自动续签**

用 AltStore / Sidekick：电脑上常驻 AltServer，同一 Wi-Fi 下自动 7 天续签。
代价是电脑要一直开着（或至少每周开机一次）。安装步骤与 Sideloadly 类似，
同样用 Apple ID 自签。

## 6. 和 Android 的差异

装好之后 iOS 版的 cfluxdo 与 Android 版功能一致，少数平台差异（后台通知是
机会式调度、没有应用内更新、iOS 17 以下 WebView 不走本地网关）见
[docs/ios.md](ios.md) §5。
