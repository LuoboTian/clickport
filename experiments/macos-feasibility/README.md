# 隔离可行性探针

2026-09-29 用户授权。不是产品实现。

APIProbe.swift 仅检查 SwiftUI/Finder Sync/启动配置 API，不注册扩展或启动应用。FileProbe.swift 仅操作自身创建的临时目录，完成后清理。

```sh
xcrun swiftc -swift-version 6 -target arm64-apple-macosx15.0 -typecheck experiments/macos-feasibility/APIProbe.swift
xcrun swiftc -swift-version 6 -target x86_64-apple-macosx15.0 -typecheck experiments/macos-feasibility/APIProbe.swift
xcrun swift -swift-version 6 experiments/macos-feasibility/FileProbe.swift
```

完整结果和未验证项目见 docs/reviews/003-macos-feasibility.md。
