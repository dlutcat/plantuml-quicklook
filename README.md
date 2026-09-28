# PlantUML Preview for macOS

An offline PlantUML viewer and Finder Quick Look extension for macOS. Render diagrams locally, browse multiple diagrams, and export PNG or SVG without Java or a rendering server.

在 Finder 中选择 PlantUML 源文件，按空格查看渲染后的图表。配套的应用也可以直接打开文件。

参考 [plantuml-for-github](https://github.com/plantuml/plantuml-for-github) 的实现：将 TeaVM 编译的 PlantUML JavaScript 引擎与标准库打包到原生 Quick Look 扩展中，用 WebKit 本地渲染 SVG。无需 Java、Graphviz、Docker 或渲染服务器，预览时不下载依赖、不发送源码。

## 构建

要求 macOS 13+、Apple Command Line Tools（包含 Swift 和 macOS SDK）、Python 3。无需完整 Xcode。生成当前电脑架构的本地应用；可通过 `ARCH=arm64` 或 `ARCH=x86_64` 交叉构建。

```bash
git clone https://github.com/dlutcat/plantuml-quicklook.git
cd plantuml-quicklook
python3 scripts/build.py
```

输出：`dist/PlantUML Preview.app`，其内包含 `PlantUMLPreview.appex`。构建会校验 `vendor-lock.json` 中的上游 SHA-256，默认使用 ad-hoc 本地签名。指定 `SIGN_IDENTITY` 可使用已有签名身份；此脚本不做公证或 App Store 发布。

## 安装与使用

```bash
bash scripts/install.sh
```

安装到 `~/Applications/PlantUML Preview.app`，注册文件类型并启用扩展。更新时备份同标识的旧应用，不改默认编辑器。

如果安装过开源前的本地版本，请先将旧应用移到其他位置，再安装；公开版本使用新的应用标识，安装脚本会拒绝覆盖不同标识的应用。

1. 打开安装后的 **PlantUML Preview**。
2. 如系统未自动启用，在 **系统设置 → 通用 → 登录项与扩展 → 快速查看** 中启用 **PlantUML Preview**；不同 macOS 版本路径可能不同，可搜索“扩展”。
3. Finder 中选择 `.puml` 文件，按空格；也可通过应用“文件 → 打开”查看。
4. 工具条可切换适合窗口／原始大小、查看源码、多图选择。触控板捏合可缩放。
5. 选择 **PNG** 或 **SVG**，点击 **下载图片**，在系统保存窗口选择位置。默认导出 PNG；多图文件只导出当前选中的图，文件名附带图序号。

图片按完整图表导出，不受窗口大小、缩放或源码查看影响。PNG 使用当前预览背景色，通常为 2 倍分辨率，超大图会限制到 1600 万像素／单边 16384 像素；SVG 保留矢量内容。尚未渲染完成或图表出错时，下载按钮不可用。

这是 Finder Quick Look 扩展，不会改变 Apple“预览”App 支持的文件类型。

## 支持范围

- `.puml`、`.plantuml`、`.pu`、`.wsd`、`.iuml`；UTF-8、带 BOM 的 UTF-16；中文。
- 渲染能力随固定的上游 TeaVM 引擎版本，包含常见时序图、类图、活动图等。
- 同一文件中的多个 `@start…` / `@end…` 图表可通过下拉框选择。
- 内置标准库：adaml、archimate、azure、c4、classy、classy-c4、cloudinsight、cloudogu、domainstory、edgy、eip、elastic、gcp、k8s、kubernetes、osa2。
- 支持浅色／深色系统外观，错误提示和源码查看。

明确限制：

- 首版不解析本地相邻文件或网络 `!include`，需要先展开引用；标准库形式如 `!include <C4/C4_Context>` 可直接使用。
- 未打包的 AWS、Material、Office 等大型库不支持。外部图片、远程字体、链接跳转被禁用。
- `.iuml` 若只是没有开始／结束标记的代码片段，会显示缺少图表标记的提示。
- 每个源文件最多 1 MB；单次渲染有 20 秒 JavaScript 和 25 秒原生超时。
- 这是本地签名构建，不能冒充经过 Apple 公证的分发版本。跨机器分发应准备正式签名与公证。

## 验证

纯源码处理测试：

```bash
node --test Tests/source.test.cjs
```

原生 WebKit 渲染测试（须在已登录的 macOS 图形会话中运行）：

```bash
"dist/PlantUML Preview.app/Contents/MacOS/PlantUMLPreview" \
  --smoke-test "$PWD/Examples" "$PWD/.build/smoke"
```

输出结果位于 `.build/smoke/results.json`，并保留 SVG、PNG 导出文件和预览截图。测试与 Quick Look 扩展共享同一个 Swift 预览控制器、WebKit 配置和渲染页面；Finder 注册与空格预览仍应单独验证。

当前公开示例均为虚构的图书馆和通用交互内容。可复核 [验证结果](Tests/verified-results.json)，其中列出测试平台、检查项及验证范围。Finder 注册、空格预览和系统保存面板需要在目标电脑上单独验证；其他 macOS 版本和 Intel Mac 尚未实机验证。

可查询注册状态：

```bash
pluginkit -m -v -i io.github.dlutcat.PlantUMLPreview.Preview
```

## 实现位置

- `Sources/PreviewViewController.swift`：Quick Look 协议入口。
- `Sources/RendererViewController.swift`：受限文件读取、WebKit 资源加载、原生保存面板和超时。
- `Resources/Web/preview.js`：本地渲染、SVG 收敛检测、交互和错误展示。
- `Resources/Web/source.js`：多图拆分与 include 检查。
- `Sources/App.swift`：安装说明、文件查看器和原生冒烟测试入口。
- `scripts/build.py`：编译、打包、文件类型声明与签名。

上游版本和授权边界见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目源码按 GPL-3.0-or-later 提供，第三方组件保留各自授权与声明。
