# 正心OCR 通用安装版

通用安装版采用 Universal 2 原生 AppKit 外壳，可在 Intel 与 Apple Silicon Mac 上启动。APP 本体不封装 Python、OCR 依赖或模型。首次运行会优先复用架构和版本均兼容的本机 Python，只在未找到兼容版本时由内置、已校验的 `uv` 安装器补充 Python 3.11，然后安装对应依赖和模型。

运行环境位于：

```text
~/Library/Application Support/ZhengxinOCRUniversal/
```

## 芯片差异

- Apple Silicon：PaddlePaddle 3.2.2、PaddleOCR 3.7.0、MLX-VLM 0.7.1；支持普通扫描、PP-StructureV3 和 PaddleOCR-VL 1.6 古籍模式。
- Intel：PaddlePaddle 2.6.2、PaddleOCR 2.8.1；支持普通扫描和 PP-Structure 2.x。PaddlePaddle 当前 macOS 版本不再发布 Intel wheel，MLX 也不支持 Intel，因此不能提供与 Apple Silicon 相同的古籍 VL 模式。

## 首次运行

1. 点击“安装运行环境”，检测并复用兼容的本机 Python，安装 OCR 依赖；没有兼容版本时才下载 Python 3.11。
2. 点击“安装/更新模型”，下载当前芯片支持的模型。
3. 模型安装完成后可以断网识别。

构建命令：

```bash
chmod +x build.sh Resources/bin/* Resources/tools/*
./build.sh
```

构建脚本使用 Xcode `actool` 编译 Icon Composer 工程，同时输出现代 `Assets.car` 与兼容用 `AppIcon.icns`。
