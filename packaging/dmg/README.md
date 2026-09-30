# DMG

使用 `Scripts/package-dmg.sh Release` 生成本地测试镜像。内容为 `Clickport.app` 与 `/Applications` 链接。

正式发布需独立完成 Developer ID 签名、公证、staple、Gatekeeper 和安装升级验收。当前不上传或发布。

## Homebrew 准备（FR-13）

`Scripts/generate-cask.py` 根据 DMG 实际内容计算 SHA-256，生成本地 Cask。使用方式：

```bash
python3 Scripts/generate-cask.py \
  --dmg build/packages/Clickport-VERSION.dmg \
  --version 0.1.0 \
  --download-url https://example.invalid/releases/Clickport-0.1.0.dmg \
  --homepage https://example.invalid/clickport
ruby -c build/homebrew/clickport.rb
```

示例地址不可下载，需在获准发布后替换为实际地址。生成器不联网、不安装、不上传；版本号必须与 DMG 中应用版本一致，由发行验收核对。当前产物只支持 Apple Silicon，最低系统声明为 macOS 15，尚待最低版本实测。

Cask 字段依据 [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)。卸载声明退出应用，保留用户设置与模板；没有自动删除用户数据的 `zap`。本地语法检查不等于安装、升级或 Gatekeeper 验收。稳定后再确定公开下载地址及 Homebrew tap，并进行实际安装验证。
