# 本地开发

工程入口为 `Clickport.xcodeproj`，共享业务模块为 `Packages/ClickportCore`，不依赖第三方 Swift 包。当前最低部署目标 macOS 15，脚本默认构建本机 Apple Silicon；最低系统与 Intel 兼容性仍待实机验证。

## 命令

签名构建在 Xcode 完成资源复制后，依次重新签名内嵌扩展和主应用，保留该构建生成的沙盒及 App Group 权限，再校验整包。Release 使用 clean build；Debug 支持增量构建。签名失败会返回非零状态，不能继续安装或打包。此流程只使用本地开发证书，不等于 Developer ID 公证发行。

```sh
Scripts/test.sh
bash Scripts/test-appkit.sh
Scripts/build.sh Debug
Scripts/install-local.sh Debug
Scripts/build.sh Release
Scripts/package-dmg.sh Release
```

- 构建脚本优先使用 `CLICKPORT_SIGN_IDENTITY`；未设置时仅在本机恰有一个 Apple Development 身份时自动选择。签名团队从本机签名结果提取，必要时使用 `CLICKPORT_TEAM_ID`。
- 证书、私钥和团队值不写入工程或版本控制。构建日志与产物在忽略的 `build/` 中，分享日志前需移除本机身份信息。
- `Scripts/build.sh Debug --unsigned` 仅验证编译，不用于 Finder 扩展实机验收。
- 安装默认放到用户 Applications；可用 `CLICKPORT_INSTALL_DIR` 指定位置。检测到已有安装会停止；退出应用后可加 `--replace` 更新同一应用，复制校验失败保留旧版本，设置与模板独立保存。
- DMG 脚本生成本地测试镜像，包含应用与 Applications 链接；不会公证、上传或发布。正式发行仍需 Developer ID、公证与 Gatekeeper 验收。

## 结构

- `Apps/Clickport`：SwiftUI 设置、菜单栏、操作调度与共享容器访问。
- `Extensions/FinderExtension`：捕获 Finder 上下文、生成菜单、提交动作请求。
- `Packages/ClickportCore`：配置、目标与菜单规则、模板复制和隐藏属性操作。
- `Config`：两个 Target 的 Info.plist 与 entitlement 模板，无本机身份值。
- `Tests`：跨 Target 与实机验收说明；共享模块测试与 Package 放在一起。
- `Scripts`：测试、构建、安装与 DMG 打包。
- `packaging/dmg`：DMG 交付约定，后续布局资源。

## 当前实现与验证状态

V1 仍在开发和验收中。当前证据以 [V1 验证清单](v1-verification.md) 为准，不能用构建成功代替实机验收。

- 共享模块 54 项测试通过，覆盖路径、菜单配置、持久化、模板创建、取消、批量错误和请求队列等边界。
- `bash Scripts/test-appkit.sh` 检查共享会话的文件权限持有和回调释放，不展示或代替真实 AirDrop 面板。
- 真实 Finder 已验证路径复制、基础 JSON 与导入 DOCX/XLSX/PPTX 新建、隐藏与直接子项取消隐藏、宿主退出后恢复；Word/Excel/PowerPoint 可打开对应测试文档。
- 原生设置已验证菜单草稿保存/放弃与重启保留、精确目录授权/撤销、登录项注册/注销、无效配置导入保留原值、模板失效提示和重导入恢复。
- 永久删除确认框可查看全部目标；12 个测试文件的取消流程已验证。实际永久删除及部分失败仍待实机验收。
- 英中日西法文案已生成；部分控件辅助功能树通过检查，完整键盘、VoiceOver、各语言布局和深浅色验收尚未完成。

### 当前阻塞与外部关卡

- 高级启动：实际接收器能收到全部选中 URL，但沙盒宿主传出的参数和环境变量未生效。独立启动助手或宿主沙盒取舍待用户确认，不能把配置可保存当作功能通过。
- AirDrop：本机管理配置禁用该功能，系统共享服务返回 nil。正常面板与终态回调需在允许 AirDrop 的环境验证；不改变管理限制。
- 最低 macOS 15、Intel、外置盘、网络卷、云盘和实际重新登录启动仍需对应环境验证。
- Developer ID、公证、Gatekeeper、Homebrew 实际安装/升级和发布地址尚未就绪。当前仅本地开发签名，不上传或发布。

## 模板与后台操作

配置文件上限为 4 MB；加载与导入只读取普通本地文件，拒绝目录、符号链接及管道。超限导入或保存失败时保留原配置，导出采用相同上限。

模板导入保留独立副本，重新导入保留条目标识。仅支持 TXT、MD、JSON、DOCX、XLSX、PPTX、Pages、Numbers、Keynote；单个模板最多 256 MB，拒绝符号链接。文本验证 UTF-8、JSON 验证语法、Office 检查 ZIP 目录和必要部件，创建前及临时副本完成后再次检查。基础检查不能代替原应用打开验证。

容器结构参考 [Microsoft Open XML 文档](https://learn.microsoft.com/en-us/office/open-xml/general/how-to-create-a-package)，iWork 存储形态参考 [Apple 文档](https://support.apple.com/en-ca/119883)。未引入第三方代码。

批量文件操作在后台逐项执行，单项失败继续后续项目。停止请求在文件系统调用完成后生效，已完成操作不回滚。新建文件在最终重命名前检查取消；取消会清理未发布的临时副本，已经发布的文件按成功处理。进程崩溃后的残留清理及大文件中途取消实机时序仍待验证。

## Homebrew 草稿

`python3 Scripts/generate-cask.py --help` 查看必填参数。脚本根据指定 DMG 计算摘要，生成本地 Cask；下载地址及主页只接受无认证信息的 HTTPS URL。当前只验证过生成、摘要和 Ruby 语法，尚未用真实发行地址安装。Cask 不会上传证书，也不会自动发布或安装软件。

## 关于页链接

通过本机构建环境变量 `CLICKPORT_GITHUB_URL`、`CLICKPORT_UPDATES_URL` 和 `CLICKPORT_FEEDBACK_URL` 注入公开链接。未设置时保留禁用入口。只接受无账号、密码或查询参数的 HTTPS 地址；源文件不保存个人仓库信息。

更新入口仅打开发布页面，反馈入口仅打开反馈页面。应用不会自动下载、安装或发送诊断内容。正式地址仍待配置，不代表已发布版本。

## 应用图标

应用图标位于 `Apps/Clickport/Resources/Assets.xcassets/AppIcon.appiconset`，包含 macOS 的 10 个尺寸与倍率。资源已纳入主应用的 Resources 阶段，由 Asset Catalog 编译生成 `AppIcon.icns` 与 `Assets.car`。

从仓库根目录运行 `swift Scripts/generate-app-icon.swift` 可重新生成。脚本用 AppKit 绘制原创几何图形，无外部素材或额外 Swift 依赖。生成物随源码保存，正常构建不需要运行生成脚本。当前为开发版本图形，最终品牌视觉仍可调整。
