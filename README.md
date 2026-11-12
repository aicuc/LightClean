# 轻舟清理 · LightClean

[![Stars](https://img.shields.io/github/stars/aicuc/LightClean?style=social)](https://github.com/aicuc/LightClean/stargazers)
[![Forks](https://img.shields.io/github/forks/aicuc/LightClean?style=social)](https://github.com/aicuc/LightClean/forks)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

轻量、原生、在本机运行的 Mac 清理工具。支持缓存、日志、大文件、开发工具缓存及微信附件专项扫描，清理前由你逐项确认。

**[下载最新版本](https://github.com/aicuc/LightClean/releases/latest)** · **[提交问题](https://github.com/aicuc/LightClean/issues)** · **[Fork 项目](https://github.com/aicuc/LightClean/fork)**

如果它帮你腾出了空间，欢迎点一个 **Star ⭐**；也欢迎 Fork、修复问题和贡献改进。

## 下载与安装

前往 Releases 下载与你的 Mac 架构对应的 ZIP，解压后将「轻舟清理.app」拖入「应用程序」。当前预编译包面向 Apple Silicon（arm64）；Intel 用户可按下文从源码构建。

需要 macOS 14 或更新版本。应用为本机临时签名，尚未经过 Apple 公证；macOS 可能阻止首次打开。确认下载来源后，可按系统提示在「系统设置 → 隐私与安全性」中允许打开。

原生 macOS 14+ 清理工具，SwiftUI 编写，所有数据仅在本机处理。

## 使用

打开 `dist/轻舟清理.app`。选择应用缓存、运行日志或大文件，点击开始扫描。查看结果并勾选项目，点击移入废纸篓并确认。每一项可通过右侧按钮在 Finder 中查看。大文件模式先选择文件夹，只列出 100 MB 及以上文件，跳过隐藏文件、应用包与符号链接。

缓存扫描当前用户的 `~/Library/Caches`，日志扫描 `~/Library/Logs`；每个直接子项作为一个可选项目，目录会整体移入废纸篓。先退出相关应用；缓存可能包含离线资源或会话信息，日志可能用于排错。大文件不是垃圾，请逐项核对。清理可从废纸篓恢复，不会自动清空废纸篓。

部分不可访问目录会计入跳过数量。根据 macOS 提示授予所选文件夹的读取权限；本应用不获取管理员权限。取消扫描会显示已经发现的部分结果。文件大小为逻辑大小，不代表实际可释放的物理空间；APFS、硬链接、压缩和可回收空间会造成差异。移入同一磁盘废纸篓后通常不会立即释放空间。

## 构建与测试

需要 Swift 6 与 macOS Command Line Tools。

```sh
./scripts/test.sh
./scripts/build-app.sh
open dist/轻舟清理.app
```

应用使用本机临时签名，未经过 Apple 公证。本版本不提供重复文件、卸载应用或系统优化功能。扫描及删除期间侧栏不可切换。


## 深度清理（1.1）

- **深度清理**：汇总用户缓存、运行日志、Xcode DerivedData、npm 下载缓存和日志、Gradle 缓存与分发包、Cargo registry 下载缓存、默认路径下的 pip 缓存；uv 缓存只分析。扫描明确列出的默认位置，不保证覆盖自定义位置。
- **安装包与归档**：递归检查 Downloads 内的 dmg/pkg/iso/zip/7z/rar/tar/gz/bz2/xz，跳过隐藏项、符号链接和包内容。不会推断安装状态，不会把归档当作垃圾；压缩包可能是唯一副本。
- **应用数据分析**：统计 `~/Library/Application Support` 各直接子目录，仅分析和 Finder 定位，无法勾选删除。不根据文件夹名称判断卸载残留。
- 每项右侧 **ⓘ** 展示用途、清理影响、完整路径和修改时间。可按分类筛选，或仅看至少 30 天未修改的项目；修改时间不代表最后使用时间。筛选不会取消其他已选项目，底部选中总数涵盖所有分类。
- 每次扫描仍默认不选择任何项目。清理前重新检查规则范围、路径和符号链接；整个选中目录会移入废纸篓。停止相关应用、安装及构建任务后再操作。

开发工具参考：[Apple Xcode 生成文件位置](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html)、[npm 缓存](https://docs.npmjs.com/cli/v7/commands/npm-cache/)、[pip 缓存](https://pip.pypa.io/en/stable/topics/caching/)。

## 1.2.0 · 微信与项目专项

- 微信专项支持当前用户新版 `xwechat_files`：按月份/附件组扫描 cache、temp、msg/video、msg/file、msg/attach，只处理用户选中的分组。运行中的微信会阻止专项清理。
- 聊天数据库、联系人、收藏、登录配置及迁移数据不列入清理。大文件模式也禁止绕过微信边界删除数据库。
- 项目构建缓存：选择项目或工作目录，最多检查五层，只有旁边存在 Package.swift 的 .build 才列入，源码、dist 和无标识目录保留。
- 默认仍为移入废纸篓；可切换永久删除，经单独确认执行，不提供自动清空整个废纸篓。删除媒体后本地附件可能无法再打开或重新下载。
- 文件操作在后台，逐项显示进度。展示当前实际可用空间；永久删除后展示容量变化（受其他系统活动影响），不将逻辑大小承诺为可释放容量。
- 应用数据分析新增 Containers，提供完全磁盘访问设置入口。权限不足时只统计可访问部分。

测试仅使用独立合成目录验证微信数据库保护、媒体删除、符号链接、只读项目和源码保护，不清理真实用户文件。

## 参与贡献

欢迎通过 Issue 提交问题与建议，或 Fork 后提交 Pull Request。请参阅 [贡献指南](CONTRIBUTING.md)。发布前会使用合成目录验证清理边界，贡献代码也应保留这一约束。

## License

[MIT](LICENSE)
