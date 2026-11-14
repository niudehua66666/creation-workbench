# 创作工作台

给 Mac 做的创作小工具：截图先收进暂存栏，标好重点后多选拖走；看动效参考时圈出一小段，循环播放并整理动作说明。

这是创作工作台的独立源码项目。包含桌面主程序、截录暂存，以及主程序必需的原生组件。没有个人网站、个人录屏、参考视频、登录信息和历史任务数据。

## 下载与安装

[下载 Mac 测试版](https://github.com/niudehua66666/creation-workbench/releases) · [安装说明](INSTALL.md)

支持 Apple Silicon、macOS 15+。截图与录屏助手已内置；关窗后可常驻菜单栏，可选登录后启动。0.6.1 尚未进行 Apple Developer ID 签名与公证，首次启动可能被系统阻止。

## 功能

- 截图暂存、区域截图、箭头和高亮标注、裁剪、保存副本、多文件拖出。
- 暂存栏贴边、小三角恢复与悬浮球。
- 屏幕录制、录制回看与本机剪裁。
- 参考视频分类、双端点选段、区间循环、简短动作说明与本机导出。
- 可选高级动效复刻、Eagle 入库、内置触控板与键盘工具。

## 源码结构

| 目录 | 在本软件中的用途 |
| --- | --- |
| `motion-reference-mac/` | Electron 桌面主程序与动效拆解 |
| `light-recorder-mac/` | 截录暂存和录屏组件 |
| `screenshot-editor-mac/` | 截录暂存使用的图片编辑库 |
| `recent-files-mac/` | 仅保留截图监听库及其核心依赖，不含原独立应用 |
| `trackpad-lock-mac/` | 主程序调用和内置的触控板及键盘助手 |

这些目录共同构成本软件的可构建源码，不需要复制作者其他工作目录。

## 开发环境

- Apple Silicon Mac；截录暂存要求 macOS 15 或更新版本。
- Xcode Command Line Tools；测试使用 Swift 6 的 Testing 框架，本次验证为 Swift 6.3.3。
- Node.js 26；JavaScript 依赖版本由 lockfile 固定。
- 本机 FFmpeg（需支持 drawtext）、yt-dlp。准备脚本会下载 Remotion 所需的无头 Chromium。
- AI 分类和动作说明使用你自己的 Codex 登录与额度；截图、录屏、循环和本机导出不因此获得或需要作者的账户。
- Eagle 为可选集成，需要自行安装。

## 构建

先在仓库根目录构建截图组件。以下命令仅生成应用，不启动应用、不改系统权限。

```sh
cd light-recorder-mac
./scripts/test.sh
./scripts/build-app.sh
cd ../motion-reference-mac
npm ci
npm run check
npm run prepare:runtime
npm test
npm run build
```

如果 FFmpeg 或 yt-dlp 不在 PATH 中，使用 `WORKBENCH_FFMPEG` 和 `WORKBENCH_YTDLP` 指定可执行文件的绝对路径。准备脚本不再依赖作者电脑的路径。

`npm run build` 会同时构建并内置截录暂存和触控板助手，不需要另外安装。在 `motion-reference-mac` 中执行 `npm start` 会打开桌面应用，并可能启动已安装的截录助手；请在准备使用时执行。

制作发行包：

```sh
python3 scripts/prepare-distribution.py
npm run check
npm test
npm run package
node scripts/smoke-package.mjs "release/mac-arm64/创作工作台.app"
node scripts/create-dmg.mjs
```

`prepare-distribution.py` 从固定版本源码编译 FFmpeg 和依赖，校验 yt-dlp 官方 SHA-256，并准备运行时、许可证和媒体组件源码附件。首次编译需要数分钟。`create-dmg.mjs` 生成拖拽安装磁盘映像，不启动应用。当前使用 ad-hoc 签名；签名、公证及实机验收状态见安装说明。

## 数据与权限

截图与录屏保存在使用者本机。系统会按功能请求屏幕录制、麦克风、指定文件夹或输入监控权限。AI 分析会把抽取的参考画面提交给使用者登录的 Codex 服务。请只导入你有权处理的素材。

动效任务与作者、搜索记录等保存在 `~/Library/Application Support/动效拆解/`。截录助手使用自己的 `LightRecorder` 数据目录。上述个人数据不属于源码包。

## 许可证

本项目自有源码使用 [MIT](LICENSE)。第三方依赖、运行库和用户导入的素材保留各自许可证，详见 [第三方说明](THIRD_PARTY.md)。本仓库不捆绑 Node、FFmpeg、yt-dlp、Chromium、Codex、第三方参考视频或作者的账号。
