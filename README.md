# Mac Right

Mac Right 是一个原生 macOS 文件效率工具，目标是把快速新建文件、常用目录、复制/移动和常用 Finder 操作集中到一个轻量入口。

## 当前功能

- 管理文件格式：启用/停用、编辑显示名称和后缀、选择 Finder 右键菜单中的新建格式、调整顺序、重置默认项。
- 添加自定义文件格式，并创建带对应后缀的空白文件。
- 选择多个文件或文件夹，复制或移动到目标目录；同名项目会自动生成不冲突的名称。
- 保存常用目录，快速从应用内打开或作为复制/移动目标。
- Finder 扩展提供“新建文件”和“打开方式”。新建文件菜单只显示同时启用并勾选“Finder 右键”的格式；选择格式后输入文件名，在当前目录创建。
- 主应用的“Finder 菜单”页面检测终端和 Visual Studio Code 是否已安装，并可分别设置是否在 Finder 右键菜单显示。
- 从菜单栏快速新建文件和打开常用目录；主应用不显示在 Dock 中。
- 记住新文件保存目录，并提供图标显示与提示音偏好设置。

目录访问通过 macOS 文件选择器和安全书签授权，应用与 Finder 扩展通过 App Group 共享设置。安装并首次打开应用后，可在设置窗口底部点击“启用 Finder 扩展”，然后按系统提示在扩展管理中开启 Mac Right。

如果 Finder 扩展无法写入当前目录，新建文件时可以通过出现的文件夹选择器授权目录并重试。Finder 扩展由系统单独管理，关闭主应用后右键菜单仍可使用。

当前可为任意后缀创建空白文件；RTF 和 XML 使用基础文档头，其它 Office、WPS、iWork、Ai 和 PSD 格式尚未生成可直接编辑的原生文档。修改隐藏文件显示状态以及第三方格式模板仍在计划中。

## 环境要求

- macOS 27.0 或更新版本（当前 Xcode 工程部署目标）
- Xcode 27 或兼容版本

## 打开项目

在 Xcode 中打开 `my-mac-right.xcodeproj`，选择 `my-mac-right` scheme 后运行。项目使用 SwiftUI 和 AppKit，不依赖外部 Swift Package。

也可以在终端构建：

```sh
xcodebuild -project my-mac-right.xcodeproj -scheme my-mac-right -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build
```

## 规划与进度

实施阶段和未完成事项记录在本地 `PLAN.md` 与 `PROGRESS.md` 中。这两个文件按项目约定被 Git 忽略；它们不会进入提交记录。
