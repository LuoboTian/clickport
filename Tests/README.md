# 验证入口

共享业务单测：`Scripts/test.sh`，源码位于 `Packages/ClickportCore/Tests`。

真实 Finder 已完成多项文件、多选、窗口空白处、新建、隐藏及宿主恢复验证；不能据此标记全部 FR-01–FR-09 通过。桌面空白处、受限环境及其他剩余项目，以 [逐项验收清单](../docs/development/v1-verification.md) 为准。所有写入和删除验收只使用专用临时夹具。

安全关卡：永久删除默认关闭、空白处不提供删除、执行前显示数量和不可恢复说明；隐藏子项只处理一层；新建文件不覆盖已有文件；导入失败保留原配置；导出不带环境变量值和授权。

单测或构建通过不代表以上实机流程通过。

## AppKit 共享生命周期（FR-06 / FR-11）

运行 `bash Scripts/test-appkit.sh`，构建共享包后直接编译产品的 `SystemActions` 与模拟共享服务。检查共享请求结束前不释放文件授权，成功和失败回调只释放一次，重复服务不会覆盖已有会话，服务不可用或拒绝目标时授权仍归调用者。该测试不展示共享面板、不访问真实文件，也不传输数据；不能代替真实 AirDrop 面板及取消流程验收。

## 应用启动接收器（FR-01 / FR-02）

运行 `bash Scripts/build-launch-receiver.sh` 生成 `build/test-fixtures/LaunchReceiver.app`。在打开方式中临时添加它，填写测试参数及 `CLICKPORT_TEST_VALUE`，通过真实 Finder 菜单打开隔离文件。接收器将进程 ID、启动参数、该指定测试变量及收到的 URL 写入同目录 `receiver-<pid>.json`。不记录其他环境变量，不随产品打包；仅传入隔离测试数据。

当前实测 5 个选中 URL 全部到达，但沙盒宿主的参数及环境变量未到达。AppKit `NSWorkspaceOpenConfiguration.arguments` 头文件明确说明沙盒调用者的参数会被忽略。高级启动尚未通过，需要先确定非沙盒启动组件的架构边界；不可通过删除验收要求宣称完成。
