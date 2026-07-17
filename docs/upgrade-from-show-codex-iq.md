# 从 Show Codex IQ 升级

Codex Toolbox 更改了产品名和应用文件名，但保留 Bundle ID `io.github.zzzzzzjw.ShowCodexIQ` 与原 UserDefaults 键。这使得已有设置与登录项状态可继续使用。

## PKG 的无感迁移

1. `preinstall` 只检查 `/Applications/Show Codex IQ.app` 与 `/Applications/Codex Toolbox.app`，验证 Bundle ID 后请求运行中的应用退出。
2. 15 秒内未退出则安全中止安装，不强制终止进程。
3. 新应用安装到 `/Applications/Codex Toolbox.app`。
4. `postinstall` 依次验证目标路径不是符号链接、Bundle ID 正确、代码签名完整，且主程序包含 arm64 和 x86_64。
5. 只有全部验证成功后，才会在旧路径不是符号链接且 Bundle ID 匹配时删除该精确路径。

安装脚本不扫描、不修改任何用户主目录，也不删除其他同名文件。

## 设置、缓存与登录启动

- UserDefaults 因 Bundle ID 不变而自动继承。
- 首次启动验证旧 `latest.json` 可解码后，原子复制到 `Application Support/CodexToolbox/`。旧文件在 v1.0.0 中保留。
- 如原来启用了登录时启动，新应用在从 `/Applications` 首次启动时会重新注册 `SMAppService.mainApp`。失败时保留重试标记，不伪造已启用状态。

## 回滚

v1.0.0 保留旧 Application Support 快照。如必须回滚，可重新安装最后一个 Show Codex IQ beta；新版 Token 账本与重置卡缓存不会被旧应用读取。
