# 正心OCR 帮助

## 关于正心OCR

正心OCR 是一款面向 macOS 的本地文献识别工具，用于处理扫描文献、复杂排版 PDF 和中文古籍，支持 Apple Silicon 与 Intel 芯片。

软件使用 AppKit 开发，基于以下组件构建：

- **PaddleOCR**：用于文字检测、文字识别和文档解析，按照 Apache License 2.0 授权。
- **PP-Structure**：用于复杂版面、表格、公式和图文混排内容的结构分析，属于 PaddleOCR 文档解析能力。
- **PaddleOCR-VL 与 MLX-VLM**：用于 Apple Silicon 上的古籍和复杂文献识别，相关代码与模型按照各自随附的许可和使用条款提供。

正心OCR 是独立开发的软件，并非 PaddleOCR 官方产品。除第三方组件外，正心OCR 的界面、功能设计及相关软件成果版权归北京正笔正心文化发展有限公司所有。

## 版本区别

### 1. 通用安装版

支持 Apple Silicon 与 Intel Mac。APP 本体较小，首次运行需要联网安装 OCR 依赖和模型。Apple Silicon 支持普通扫描、复杂排版和古籍正本；Intel 支持普通扫描和复杂排版。

### 2. 完整离线版

仅支持 Apple Silicon Mac。APP 已包含 OCR 依赖、模型和相关资源，但不包含 Python 解释器。安装后可以直接离线识别，并支持三种识别模式。

## 如何使用

### 1. 准备运行环境

**安装说明**

通用安装版可由 APP 自动下载并安装所需运行环境和模型：首次使用时，依次点击“安装运行环境”和“安装/更新模型”即可。如果 APP 未能自动完成安装，请按照下面的“下载安装”或“终端安装”办法手动完成。

完整离线版已包含依赖和模型，APP 会提供验证功能。所需的 Python 3.13 解释器仍须手动安装。

<details>
<summary>所需环境与下载地址</summary>

- **通用安装版**：Apple Silicon 使用原生 arm64 Python 3.10—3.13；Intel 使用 x86_64 Python 3.10—3.12。未找到兼容版本时，APP 会通过内置 uv 自动安装 Python 3.11，无须先安装 Homebrew。
- **完整离线版**：仅支持 Apple Silicon，内置依赖按 Python 3.13 构建，请安装标准版 Python 3.13 的 macOS universal2 安装包，以原生 arm64 运行。Python 3.14、3.15 或实验性自由线程版本不适用于当前内置依赖。
- **Python 下载**：[macOS 官方下载页](https://www.python.org/downloads/macos/)。完整离线版可使用 [Python 3.13.17 安装包下载页](https://www.python.org/downloads/release/python-31317/)，点击“macOS installer”；通用版 Intel 用户手动安装时请选择 3.11 或 3.12 系列。
- **OCR 依赖**：[PaddlePaddle 下载与安装](https://www.paddlepaddle.org.cn/install/quick)、[PaddleOCR 下载](https://pypi.org/project/paddleocr/)、[MLX-VLM 下载](https://pypi.org/project/mlx-vlm/)、[uv 安装说明](https://docs.astral.sh/uv/)。通用版安装器会按芯片选择版本，并安装 PyMuPDF、Pillow 等配套依赖；MLX-VLM 仅用于 Apple Silicon。依赖包应由 APP 安装器安装到专用环境。

</details>

<details>
<summary>所需模型与下载地址</summary>

- **普通扫描**：Apple Silicon 使用 PP-OCRv6，下载入口为 [PP-OCRv6 官方模型合集](https://huggingface.co/collections/PaddlePaddle/pp-ocrv6)；检测、识别、方向等配套模型由安装器按实际配置下载。
- **复杂排版**：Apple Silicon 使用 PP-StructureV3，下载入口为 [PP-StructureV3 官方模型合集](https://huggingface.co/collections/PaddlePaddle/pp-structurev3)；安装器会下载版面、表格、公式等所需子模型。
- **古籍正本**：Apple Silicon 使用 [PaddleOCR-VL-1.6 官方下载页](https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6)，在“Files”中可查看权重、配置和分词器文件。
- **Intel**：使用 PaddleOCR 2.x 的中文 OCR 与 PP-Structure 配套模型，下载入口为 [PaddleOCR 2.8 官方模型列表](https://github.com/PaddlePaddle/PaddleOCR/blob/release/2.8/doc/doc_ch/models_list.md)。安装器自动选择兼容模型；不安装古籍正本模型。

</details>

<details>
<summary>办法一：下载安装（通过界面完成）</summary>

- **通用安装版**：从[正心OCR 下载页](https://ocr.zhengxinshushe.com/download.php)下载安装 APP。打开后先点击“安装运行环境”，等待完成，再点击“安装/更新模型”。这两个步骤会自动下载 Python（如有需要）、依赖和模型；显示“运行环境：已就绪”和“模型：已就绪”后即可识别。若已手动下载安装兼容 Python，安装器会优先复用。
- **完整离线版**：下载并安装完整离线 APP，再从上述 Python 下载页下载 Python 3.13 的 macOS 安装包，双击 .pkg，按提示完成安装。重新打开 APP，点击“验证内置依赖”和“验证内置模型”。依赖和模型已随 APP 提供，无须重复下载。
- **手动下载模型**：通用版通常直接使用“安装/更新模型”。如需用浏览器预先下载古籍模型，请在 PaddleOCR-VL-1.6 的“Files”中下载完整仓库文件，保留子目录结构，将文件放入下述 PaddleOCR-VL-1.6 目录，确保配置和权重直接位于该目录中。随后仍须点击“安装/更新模型”，补齐其他模型并完成初始化。普通扫描、复杂排版及 Intel 的多个配套模型由此按钮统一安装，单独下载一个权重文件不足以完成安装。

通用版模型根目录（访达中按 Shift+Command+G，粘贴此路径）：

```text
~/Library/Application Support/ZhengxinOCRUniversal/models/
```

古籍模型目录：

```text
~/Library/Application Support/ZhengxinOCRUniversal/models/PaddleOCR-VL-1.6/
```

完整离线版的模型位于 APP 包内，由“验证内置模型”检查；如缺失，请重新下载完整离线版。

</details>

<details>
<summary>办法二：终端安装</summary>

以下命令假定 APP 已放入“应用程序”文件夹；若放在其他位置，请将命令中的 APP 路径替换为实际位置。打开“终端”，按顺序逐段复制执行，上一段成功后再执行下一段。首次安装和模型下载需要联网。

**通用安装版：安装运行环境。** 自动检测芯片、复用兼容 Python，或自动下载 Python 3.11，再安装配套依赖：

```sh
"/Applications/正心OCR-通用安装版.app/Contents/Resources/bin/localocr" setup-runtime
```

**通用安装版：下载并初始化模型。** 自动下载当前芯片支持的普通扫描、复杂排版及古籍模型：

```sh
"/Applications/正心OCR-通用安装版.app/Contents/Resources/bin/localocr" setup-models
```

**通用安装版：检查安装结果。** 输出中的 runtime_ready 与 models_ready 均为 true 后，重新打开 APP 即可：

```sh
"/Applications/正心OCR-通用安装版.app/Contents/Resources/bin/localocr" doctor --json
```

**完整离线版：安装 Python。** 先从 Python 3.13.17 下载页下载 macOS 安装包到“下载”文件夹，再用以下命令安装。sudo 会要求输入 Mac 管理员密码，输入时终端不显示字符；如安装包文件名不同，请替换为实际文件名：

```sh
sudo /usr/sbin/installer -pkg "$HOME/Downloads/python-3.13.17-macos11.pkg" -target /
```

**完整离线版：确认 Python 版本和架构。** 应显示 Python 3.13.x 与 arm64：

```sh
/Library/Frameworks/Python.framework/Versions/3.13/bin/python3 -c 'import platform; print(platform.python_version(), platform.machine())'
```

**完整离线版：验证内置依赖、模型和就绪状态。** 这里的 setup 命令仅作检查，不会重新下载模型：

```sh
"/Applications/正心OCR.app/Contents/Resources/bin/localocr" setup-runtime
"/Applications/正心OCR.app/Contents/Resources/bin/localocr" setup-models
"/Applications/正心OCR.app/Contents/Resources/bin/localocr" doctor --json
```

依赖或模型下载失败时，请先确认相应下载站点可以访问，再重试对应步骤，并查看 APP 日志中的报错。安装和验证完成后即可断网识别。

</details>

### 2. 选择输入文件

点击“输入文件”右侧的“选择……”按钮，选择需要识别的 PDF、PNG、JPEG 或 TIFF 文件。

### 3. 设置输出位置

点击“输出目录”右侧的“选择……”按钮，指定识别结果的保存位置。程序不会覆盖原始文件。

### 4. 选择识别模式

- **普通扫描**：适合现代横排印刷体和版面规整的扫描件。对没有图片、文字映射正常的可见文字 PDF 页面，直接提取原生文字；扫描页、图文混排页、隐藏文字层和文字映射异常的页面仍进行 OCR。保留原有识别模型与方向检测，平整扫描页默认关闭去弯曲处理，并限制检测图尺寸；识别文字裁图仍使用原始分辨率。弯曲书页可使用复杂排版模式。
- **复杂排版**：适合多栏、表格、公式、图片与正文混排的文献。
- **古籍正本**：适合竖排、夹注、生僻字、印章和残损页面，仅在 Apple Silicon 上提供。

### 5. 开始识别

点击“开始识别”执行任务。长篇 PDF 会按页处理，界面显示当前页、已渲染页、已识别页和失败页，并保留已经完成的结果。

### 6. 检查识别结果

任务完成后点击“显示结果”，可在访达中打开输出目录。结果可能包含逐页 JSON、Markdown、文本、可视化图片以及自动合并的文档。

原生文字直接提取的页面不生成中间图片，因此“已渲染页”可以小于“已识别页”。输出目录中的 `performance.json` 记录逐页处理方式和耗时，可用于检查识别速度。

古籍、异体字、避讳字、夹注顺序、漫漶和虫蛀文字仍需人工校勘。正式出版或对外使用前，请核对原始页面。

### 7. 退出正在运行的任务

识别任务运行时按 Command+Q，程序会询问继续识别并退出、取消任务并退出，或者返回程序。

## 升级、更新与反馈

正心OCR 的产品信息、版本更新和技术支持由正心OCR官网提供。

- [正心OCR 官网](https://ocr.zhengxinshushe.com)
- [获取更新与支持](https://ocr.zhengxinshushe.com/download.php)
- [反馈问题](https://ocr.zhengxinshushe.com/download.php#feedback)

反馈问题时，建议同时提供正心OCR版本号、macOS版本、芯片类型、输入文件类型、识别模式、错误提示或任务日志，以及能够复现问题的操作步骤。

请勿提交包含个人隐私、未公开资料或无权传播内容的原始文档。

© 北京正笔正心文化发展有限公司
