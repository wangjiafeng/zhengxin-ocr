# 正心OCR.app 完整离线版

这是一个仅支持 Apple Silicon、macOS 26 的完整离线 OCR 应用。应用不封装 Python 解释器，但内置 PaddleOCR、MLX-VLM、相关 Python 第三方依赖、OCR 模型和中文可视化字体。当前版本为 v1.0。

运行时只调用本机的 Python 3.13。任务状态和日志写入：

`~/Library/Application Support/AncientOCR/`

## 构建

```bash
chmod +x build.sh Resources/bin/*
./build.sh
```

不需要完整 Xcode，使用 macOS Command Line Tools 中的 Clang 编译原生 AppKit 界面。

## 首次使用

1. 将 `正心OCR.app` 拖入 `/Applications`。
2. 首次打开如果被 Gatekeeper 阻止，在 Finder 中右键应用并选择“打开”。
3. 点击“验证内置依赖”和“验证内置模型”（可选）。
4. 选择 PDF、识别模式与输出目录，开始识别。

无需另行下载依赖或模型，可以断网识别。

PDF 会先读取总页数，然后按“渲染一页、识别一页”的顺序处理。界面分别显示当前页、累计渲染页、成功识别页和失败页；成功处理后的中间 PNG 会立即删除，避免长篇 PDF 在识别前占用大量临时空间。

## Codex MCP

在 `~/.codex/config.toml` 添加：

```toml
[mcp_servers.local_ocr]
command = "/Applications/正心OCR.app/Contents/Resources/bin/localocr-mcp"
startup_timeout_sec = 20
tool_timeout_sec = 45
enabled = true
```

技能文件位于应用包的 `Contents/Resources/skill`。可复制到个人 Codex 技能目录并重新启动 Codex。

MCP 默认只返回任务元数据和本地路径，不返回 OCR 正文。应用生成逐页原始结果，并在可提取时合并为输出目录中的 `document.md` 或 `document.txt`。

## 限制

- 当前为可运行的第一版任务壳，重点验证 Apple M5、Python 3.13、PaddleOCR-VL 1.6 与 MLX-VLM 的实际兼容性。
- 无 Apple Developer 账号，应用使用本机临时签名，未做 Apple 公证。
- 16GB 统一内存固定为单任务、单页、单并发。

## 普通扫描速度优化（v1.0）

普通扫描对可用的纯文字 PDF 页面直接提取可见文字，并延迟至首次扫描页才加载 OCR 模型。图像页、混排页、隐藏文字层和异常字符映射继续 OCR。扫描路径保留 PP-OCRv6 medium 模型、350 DPI 原图和两种方向检测，关闭 UVDoc 去弯曲并限制检测图最长边；裁出的文字行仍来自原图。输出 performance.json 记录逐页路径和耗时。对比脚本与证据位于 work/modern-speed-test，测试报告位于 outputs/普通扫描优化测试。
