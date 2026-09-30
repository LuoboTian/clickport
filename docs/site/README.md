# 官网与交互演示

关联 FR-13（产品介绍与发行入口）、FR-01–FR-12（交互演示）。官网介绍当前本地试用状态，设计稿保持示例数据，不执行原生文件操作。

## 本地预览

在仓库根目录运行：

```sh
bash Scripts/build-site.sh
python3 -m http.server 8766 --directory build/site --bind 127.0.0.1
```

打开 `http://localhost:8766/` 查看官网，`http://localhost:8766/demo/` 查看设计稿。按 `Ctrl+C` 停止服务。

源文件为 `docs/site/index.html`、`docs/site/style.css` 和 `docs/ui/wireframes.html`。打包时复制现有设计稿，无需维护两份。站点使用相对链接，支持 GitHub Pages 项目子路径。

## GitHub Pages 上线

当前仅准备站点与发布配置，尚未启用 Pages 或发布公网地址。

1. 确认仓库套餐支持 Pages：GitHub Free 支持公开仓库；私有仓库需要符合条件的付费套餐。不要为了部署擅自把源码仓库改为公开。也可以另建公开的纯站点仓库，仅放置 `build/site/` 内容。
2. 审阅页面，确认愿意公开这些产品文案和模拟界面。私有源码仓库不代表 Pages 网站也私有。
3. 将已评审的站点分支合并到 `main`。在仓库 **Settings → Pages → Source** 选择 **GitHub Actions**。
4. 在 **Actions → Website preview and Pages → Run workflow** 选择 `main` 手动发布。PR 只构建；推送不会自动上线；其他分支的手动运行也只构建。
5. 成功后的站点地址显示在 `github-pages` environment 中。检查首页、演示、移动端布局，再将实际地址补到 README 的导航与仓库 About / Website。

默认地址形式为 `https://<owner>.github.io/<repository>/`；后续可以绑定自己的域名。完整规则见 [GitHub Pages 官方说明](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)。

## 发布边界

发布目录严格限定为：首页、样式、交互设计稿与 `.nojekyll`。站点 workflow 仅上传这份静态网站，不上传 DMG、应用构建、证书、配置、日志或其他工程文档。源码 CI 与站点发布分别运行。

当前没有正式下载链接、Homebrew 安装命令、分析统计或外部字体。下载入口仅在正式发行获批准并具备有效地址后添加。官网介绍和设计稿是产品资料，不代替原生实机验收。
