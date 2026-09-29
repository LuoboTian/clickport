# 软件交付规范

## 流程

产品定义 → 需求澄清 → 需求/UI 评审 → 技术评审 → 开发 → 代码评审 → 测试 → 产品验收 → 发布评审。批准记录见 docs/reviews；禁止跳过关卡或将沉默视为批准。

## 分支

main 保持可交付；短期分支使用 docs/<topic>、feat/<requirement>-<topic>、fix/<issue>-<topic>、test/<topic>、chore/<topic>。例如 feat/fr-10-status-menu。避免长期 develop 分支；必要时 release/1.0.x。分支不得含个人或组织标识。

## Commit

格式：type(scope): 简述；type 为 docs/feat/fix/refactor/test/ci/chore。每次提交聚焦一个目的，正文按需写需求编号、行为变更和验证。示例：docs(product): define v1 requirements and review gates。

禁止把凭证、个人目录、用户身份、无关来源信息写进 diff、提交信息和 PR。提交前检查 git diff --cached 与 git var GIT_AUTHOR_IDENT；提交者身份尚未确认时不擅自代填或修改全局配置。

## PR 与合并

PR 包含问题、最终行为、需求编号、验证、风险/回滚及 UI 变化截图。未运行检查明确写“未运行”和原因。至少一次人工评审；作者或代理不得替代产品批准。目标为 squash merge，提交保留需求追踪。分支保护和必需检查在远端创建后配置，目前仅规划。

版本采用 0.x 原型与 1.0.0 首版；破坏配置兼容时增加迁移方案。发布说明面向用户，不写内部对话记录。
