# DMG 遗留说明

Show Codex IQ beta 使用 DMG 分发。仓库保留 `build_dmg.sh`、`build_portable_dmg.sh`、`package_dmg.sh`、`verify_dmg.sh` 和历史 Finder 背景，用于复现和审计已发布 beta，不再是 Codex Toolbox 的发布入口。

v1.0.0 起固定使用安装到 `/Applications/Codex Toolbox.app` 的 Universal 2 PKG。主流程为：

```text
build_pkg.sh → package_pkg.sh → verify_pkg.sh → notarize_pkg.sh
```

DMG 的拖拽安装无法在改名后安全、原子地删除旧名应用，因此不得将旧 DMG 脚本用于正式 Codex Toolbox Release。
