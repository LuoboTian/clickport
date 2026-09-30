<div align="center">

<img src="Apps/Clickport/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="88" alt="Clickport 图标">

# Clickport

**让右键，更顺手。**

为 Mac 设计的 Finder 右键工具。复制路径、选择应用打开、从模板新建文件，把常用操作放到手边。

macOS 15.0+ · Swift 6 + SwiftUI · Finder 原生扩展 · MIT

[功能](#你可以用它做什么) · [交互设计稿](docs/ui/wireframes.html) · [本地体验](#开始体验) · [路线图](docs/roadmap.md)

</div>

> **V1 本地试用中。** 核心功能已实现，正在通过实际使用打磨细节；完整实机验收与正式发行尚未完成。当前没有公开 DMG 下载或可用的 Homebrew 安装命令。

## 你可以用它做什么

| 功能 | 使用场景 |
| --- | --- |
| 复制路径 | 复制选中文件、文件夹或空白处当前目录的路径，支持多选 |
| 自定义打开方式 | 添加常用应用；高级启动支持参数与环境变量 |
| 新建文件 | 内置纯文本、Markdown、JSON；Office / iWork 使用用户导入的有效模板 |
| 文件操作 | 隐藏、取消隐藏、AirDrop，以及默认关闭、执行前确认的直接删除 |
| 目录快捷入口 | 在右键菜单中放置常用目录 |
| 菜单配置 | 最多 5 个第一层快捷操作，可调整分组顺序 |
| 原生设置 | 按需授权目录、配置导入导出、语言与外观设置；菜单栏提供状态、设置与退出 |

V1 的自定义围绕已有功能展开：应用、模板、目录和菜单入口。脚本、插件及快捷指令执行留待后续评估。

## 先看看交互

[交互设计稿](docs/ui/wireframes.html) 包含 Finder / 桌面右键场景、七个设置模块、菜单栏菜单和深浅色切换。操作使用示例数据，刷新后恢复，不访问真实文件。

[官网预览](docs/site/index.html) 提供产品介绍和演示入口。GitHub 文件页只展示 HTML 源码；在线点击体验需要部署 GitHub Pages。发布步骤见 [站点说明](docs/site/README.md)。当前尚未公布在线站点地址。

在项目根目录运行：

```sh
python3 -m http.server 8765 --directory docs --bind 127.0.0.1
```

浏览器打开 `http://localhost:8765/site/` 查看官网，或 `http://localhost:8765/ui/wireframes.html` 查看交互设计稿。按 `Ctrl+C` 停止服务。

## 开始体验

当前以 **macOS 15.0+、Apple Silicon** 为构建与验证基线；Intel 及完整系统兼容性尚未实测。需要安装 Xcode 并选择相应的命令行工具。

### 从源码构建

用 Xcode 打开 `Clickport.xcodeproj`，或在项目根目录执行：

```sh
# 运行共享模块测试
bash Scripts/test.sh

# 使用本机开发证书构建 Release
bash Scripts/build.sh Release

# 先退出正在运行的 Clickport，再安装本地构建
bash Scripts/install-local.sh Release --replace
```

构建脚本在本机只有一个 Apple Development 身份时自动选择；有多个身份时，请通过 `CLICKPORT_SIGN_IDENTITY` 选择证书，必要时设置 `CLICKPORT_TEAM_ID`。证书与私钥不存入仓库。

安装后启用 Finder 扩展，并在应用中按需授权目录、配置常用入口。具体环境下未通过或待验证的行为见 [验收清单](docs/development/v1-verification.md)。

### 本地打包与无签名检查

```sh
# 在签名 Release 构建完成后生成本地 DMG
bash Scripts/package-dmg.sh Release

# 仅做编译检查：不能用于启动助手的完整功能体验
bash Scripts/build.sh Release --unsigned
```

DMG 输出到本地 `build/packages/`，不提交到 Git。正式 DMG 与 Homebrew 分发需在稳定并完成发行验证后另行发布。

## 开发与验证

项目使用本地 Swift Package 管理共享模块，当前没有第三方 Swift 依赖，也不需要 CocoaPods。

```text
Apps/Clickport/          SwiftUI 主应用与设置
Extensions/             Finder 扩展
Helpers/LaunchHelper/   按需启动的 XPC 助手
Shared/                 进程间共享协议
Packages/ClickportCore/  共享逻辑、资源与单元测试
Scripts/                测试、构建、安装与本地打包
Config/                 工程配置与权限声明
.github/workflows/      GitHub CI
docs/                   需求、设计、验收与官网预览
```

GitHub Swift CI 检查共享模块测试、AppKit 生命周期、本地化一致性和无签名 Release 构建。CI 不上传安装包，也不使用本机证书。编译通过不替代 Finder、权限与安装升级的实机验收。

- [当前交付状态](docs/development/v1-status.md) · [验证记录](docs/development/v1-verification.md)
- [需求与验收](docs/requirements.md) · [架构](docs/architecture.md) · [UI 设计](docs/ui/design.md)
- [协作规范](CONTRIBUTING.md) · [测试与 CI](docs/quality.md)

## 后续计划

先收集 V1 本地体验反馈，再逐项评估批量重命名、压缩、图片转换、快捷指令和脚本扩展。AI 文件处理单独评审使用场景与数据边界。详见 [Roadmap](docs/roadmap.md)，不承诺具体发布时间。

## 反馈与许可

反馈时请提供 macOS 版本、芯片类型、操作步骤和预期结果；如附截图或日志，请移除个人文件路径及敏感内容。

本项目采用 [MIT License](LICENSE)。
