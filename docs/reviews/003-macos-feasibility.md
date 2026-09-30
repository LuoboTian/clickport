# Mac 技术验证 · 第一轮

2026-09-29：用户确认 V1 功能边界并授权 Mac 技术验证。当前是隔离实验，不代表全量开发或发布获批。

## 已运行

环境：macOS 26.6.2、Apple Silicon、Xcode 26.1.1、macOS SDK 26.1、Swift 6.2.1。

- Swift 6 模式下 SwiftUI、Finder Sync 目标 API、应用启动参数/环境变量/新实例配置通过 arm64 和 x86_64 类型检查，最低目标设置为 macOS 15.0。
- 临时目录实验通过：中文/空格/百分号 URL 往返、模板复制字节一致、隐藏/取消隐藏、不覆盖已有目标。实验目录完成后自动清理。
- 本机有开发签名身份；没有 Developer ID Application 发行身份。未导出身份或凭据。

## 尚未验证

Finder/桌面真实加载扩展、空白/单选/多选目标捕获、App Group 通信、目录授权、主应用退出后的恢复、实际启动外部应用、Office/iWork 打开有效性及签名公证均未完成。类型检查不是旧系统/Intel 实测，也不是扩展运行验证。

下一轮需选择开发团队与实验标识，构建最小宿主和扩展，并由用户开启扩展后验证。当前不宣布技术准入通过。

## 基线与发行建议

建议 macOS 15.0+；API 探针暂未显示必须限定 15.6 的理由，但须补 15.0 实机验证。Swift 6 是语言，SwiftUI 是界面框架，辅以 AppKit/Finder Sync。Apple Silicon 首验，Intel 待实机验证。

本期 DMG；正式发行准备 Developer ID 签名、公证及 Gatekeeper 验证。后续自有 Homebrew tap/cask 复用同一产物，再单独评估 App Store 沙盒和商店更新要求。Homebrew 安装不能绕过扩展开启和系统授权。

参考：[Apple Developer ID](https://developer.apple.com/developer-id/)、[App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)、[Homebrew Cask](https://docs.brew.sh/Cask-Cookbook)。

## 本地签名实验 · 2026-09-29

用户授权使用本机现有开发证书，禁止上传证书到 GitHub。已编译最小宿主和 Finder Sync 扩展，并使用本机 Apple Development 身份签名；codesign 深度严格验证通过。签名身份在进程内读取，未写入项目文件。产物和 entitlements 仅存于系统临时目录。

HostProbe.swift / ExtensionProbe.swift 为隔离实验源文件，不含签名团队或证书信息。尚未注册、启用或验证 Finder 加载；扩展实验监控目录及沙盒访问需下一步配置核验。没有把签名成功当作实际菜单验证。当前仍缺发行证书，不代表可对外分发。
