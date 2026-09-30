# 高级启动助手方案 · 实施中

日期：2026-09-29。关联 FR-01 / FR-02 / FR-11 / FR-13。

2026-09-30 用户明确授权在独立 feature 分支新增并集成启动助手，随后再次要求开始开发。主应用及 Finder 扩展保留 App Sandbox；先验证内嵌 XPC 服务，再接入产品。正式验收以接收器及 Finder 实测为准。

## 需要解决的问题

当前接收器实测收到全部文件 URL，但参数和测试环境变量未到达。系统 SDK 的 NSWorkspaceOpenConfiguration 声明明确指出：沙盒调用者的 arguments 会被忽略；参数和 environment 均只适用于新应用实例。环境变量失败的具体原因仍须在实验中区分，不能把 SDK 对 arguments 的说明直接推广到 environment。

目标仍是让配置的参数、环境变量和全部文件 URL 实际到达目标应用，并准确说明复用已有进程的限制。设置可保存、系统打开调用返回成功均不足以通过 FR-02。

## 提议的职责划分

| 组件 | 职责 |
| --- | --- |
| Finder 扩展 | 捕获明确目标、提交动作标识；不能直接调用助手 |
| 沙盒主应用 | 校验当前配置、请求有效期、目标及授权；构造一次启动请求并显示结果 |
| 启动助手 | 仅启动明确指定的应用，传递结构化参数、环境变量和 URL；返回启动结果 |

优先验证随应用分发、按需启动的独立助手。具体采用嵌入式 XPC 服务还是其他系统支持的连接方式，须先在隔离探针中证明生命周期和实际沙盒状态；本提案不声称某种嵌入方式天然具备所需能力。不注册登录项或系统守护进程，不提供通用文件读写接口。

**权限变化：助手若不受 App Sandbox 限制，就具有普通用户进程的文件访问能力。** 限制调用接口不能代替操作系统的文件隔离。主应用和扩展保留沙盒也不能消除这个新增边界，因此须先由用户确认，再实施探针和产品助手。

## 调用契约

- 请求包含一次性标识、应用条目标识、配置版本或摘要、准确应用 URL、原始目标 URL 数组、参数数组、环境字典和新实例选项。
- 不接收 Shell 命令字符串；不通过拼接命令或 `eval` 执行；参数的空格、中文、百分号及空值保持结构化语义。
- 主应用在提交时重新核对条目存在、启用且内容未改变；助手再次检查结构、长度及数量上限，拒绝远程 URL 和不是应用包的目标。
- 调用方身份需由系统提供的进程身份和签名要求验证，不能只相信请求中的应用名称或 bundle ID。具体认证方式必须有拒绝伪造调用方的实验依据。
- 连接只接受本应用的有效主进程；没有公开本地 HTTP 端口，不从通用共享目录执行启动指令。
- 连接失败、超时或返回结果不确定时，不自动重试启动，避免重复应用实例。重新操作需用户再次触发。
- 诊断只记录结果类别，不记录参数、环境变量值或私人路径。凭据不进入工程、日志、示例或版本控制。

## 启动与结果

选择的应用位置必须保持准确：关闭系统对另一安装位置的运行实例替换。新实例选项表示向系统请求新进程，不保证目标应用产生新窗口。

结果至少区分：启动请求失败、创建新进程、复用已有进程、结果未知。仅有系统回调不能证明参数或环境到达；实际接收器分别验证。对已有进程不接受启动参数的情况，必须清楚提示；不声称运行中的进程环境已改变。

文件 URL 仍经主应用现有目标与授权检查。安全作用域如何传给接收应用、何时可释放，以及助手退出后的读取行为，均为探针验收项；不得假定非沙盒助手可替代用户授权。

## 实施与退出条件

1. 用户确认权限边界；记录批准日期和范围后才能加入助手代码。
2. 隔离探针验证实际签名、沙盒状态、调用方认证、按需启动与退出；失败时重新评审方案。
3. 接收器核对多 URL、特殊字符、空参数、环境变量、新实例及已有实例，确认值实际到达。
4. 验证关闭/修改条目、目标失效、伪造调用方、重复请求、连接中断和超时；不得自动扩大执行范围。
5. 将助手纳入本地内嵌签名、升级替换和卸载验证；不泄露签名身份，不提前发布。
6. 更新当前限制提示；只有实机证据通过才将 FR-02 标为已验收。

若用户不接受新增进程权限，需要重新决定高级启动架构或明确调整需求；代理不能自行把这一能力移出 V1。

## Implementation update — 2026-09-30

The embedded XPC service is implemented and integrated for application entries with arguments or environment variables. Both ends enforce the same signing team and exact peer identifier using [Apple's code-signing requirement API](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)). The existing host request handler retains file scopes while waiting. Unknown outcomes are not retried automatically.

Native probe and Finder evidence, including the corrected Swift 6 error-callback assertion, are recorded in the [verification log](../development/v1-verification.md). Untested acceptance items remain open.
