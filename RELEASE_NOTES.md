创作工作台 0.6.1 测试版，适用于 Apple Silicon、macOS 15 及以上。

下载 `.dmg` 后打开，将「创作工作台」拖入 Applications。截图暂存、标注、录屏和键盘/触控板助手已内置；关闭窗口后继续在菜单栏运行，可以自行开启登录后启动。

修复：新用户缺少截录助手；关窗后的返回入口；短视频抽帧失败与重试混入旧帧；超时处理误报成功；未安装 Codex 时的提示。视频处理运行库改为固定源码构建，并附源码、许可证与校验值。

本版本使用 ad-hoc 签名，尚未经过 Apple Developer ID 签名和公证，macOS 可能阻止首次打开。跨机器首次授权、实际截图录屏、实体快捷键和拖入第三方应用仍需实机验收。因此本次发布为测试版，不承诺所有机器直接启动。

截图、标注、录屏和本机裁剪不需要作者账户。AI 功能需要使用者自己的 Codex 安装、登录与额度；Eagle 为可选组件。

- `CreationWorkbench-0.6.1-macOS-arm64.dmg`：安装包。
- `CreationWorkbench-MediaSources.tar.gz`：随包 FFmpeg 与依赖的对应源码及构建说明。
- `SHA256SUMS.txt`：下载校验值。

[安装说明](https://github.com/niudehua66666/creation-workbench/blob/main/INSTALL.md) · [第三方说明](https://github.com/niudehua66666/creation-workbench/blob/main/THIRD_PARTY.md)
