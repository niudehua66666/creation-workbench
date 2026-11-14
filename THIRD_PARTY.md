# 第三方组件

根目录 MIT 许可证仅覆盖本项目自有代码，不改变下列组件的授权。精确 JavaScript 版本见 `motion-reference-mac/package-lock.json`，安装后应保留各包的许可证文件。

| 组件 | 用途 | 官方信息 |
| --- | --- | --- |
| Electron | 桌面运行环境 | https://github.com/electron/electron/blob/main/LICENSE |
| React | 界面 | https://github.com/facebook/react/blob/main/LICENSE |
| Remotion | 可选动效工程与渲染 | https://www.remotion.dev/docs/license |
| Node.js | 运行时 | https://github.com/nodejs/node/blob/main/LICENSE |
| FFmpeg | 本机媒体处理 | https://ffmpeg.org/legal.html |
| yt-dlp | 链接下载 | https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE |
| Chromium | 无头渲染 | https://www.chromium.org/chromium-os/licenses/ |

Remotion 使用其自身许可条款，不能将全部依赖统称为 MIT。FFmpeg 的具体发行义务取决于构建配置。源码仓库不提交这些预编译运行库；制作可下载安装包时需单独核对所用二进制的来源、动态依赖和随附声明。

Apple SDK、Codex 账户与 Eagle 由使用者自行取得和使用。本仓库没有附带第三方参考视频，导入素材的权利由使用者负责。

## 0.6.1 测试版二进制

- 本机媒体处理使用源码构建的 FFmpeg 8.1.1（GPL-2.0-or-later），包含 x264、FreeType、HarfBuzz；未启用 nonfree。固定来源与哈希见 `motion-reference-mac/scripts/media/sources.json`，构建命令见 `scripts/build-media.py`。发布附件 `CreationWorkbench-MediaSources.tar.gz` 提供所用源码与构建说明。
- 图形场景使用 Remotion/Chromium 生成帧，再用上述 FFmpeg 编码；发行包移除未使用的 Remotion 原生 compositor/FFmpeg 二进制。生成的场景不包含音频、原视频或 OffthreadVideo。
- yt-dlp 2026.10.26 使用官方 macOS 二进制并验证官方 SHA-256；运行时附其 LICENSE 和完整 THIRD_PARTY_LICENSES（含其打包依赖）。源码：https://github.com/yt-dlp/yt-dlp/tree/2026.10.26 。
- Node、Chromium、Remotion 和 JavaScript 依赖的许可证保留在包内。`runtime/licenses/runtime-manifest.json` 记录独立运行时的版本与哈希。

本项目自己的 MIT 授权不替代 Remotion 或上述第三方许可。
