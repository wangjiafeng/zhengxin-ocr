# 正心OCR Windows 通用安装版

首个工程候选版本 1.0，面向 Windows 11 x64。只有一个安装 EXE，首次启动自动准备 Python、锁定的 OCR 依赖及模型。应用和安装器使用自包含 .NET 发布，用户不需要预装 .NET 或 Python。

## 当前实现

- WPF 主界面：文件与输出目录、三种模式、进度计数、结果目录、环境检查/修复、帮助。
- 独立 Python 后端：从当前 Mac 通用版同步 core.py，通过 Windows 适配层替换模型选择、进程管理、路径与能力检测。
- 普通扫描保留原生文字快速路径、隐藏文字层回退、延迟加载、350 DPI 和单页处理策略。
- 单任务运行；每个任务使用独立结果子目录。关闭窗口可以继续后台识别，重新打开接回；取消验证 PID 创建时间后终止任务进程树。
- 首次自动准备：uv 复用兼容 Python 3.11 或下载受管理解释器，在新环境安装并自检后切换 runtime.json。缺少 C++ 运行库时下载官方签名安装程序，必要时触发系统管理员授权。
- CPU 后端支持普通/复杂/古籍的候选配置；模型逐模式实际调用预测后才标记可用。GPU 仅探测，不自动切换尚未验证的加速环境。
- Python 依赖完整版本及发行文件哈希锁定；模型首次准备后记录本机文件 SHA-256 清单，后续启动校验，缺失/损坏重跑对应准备。
- CLI、STDIO MCP 与 Windows 帮助。
- 单 EXE 用户级安装器：复制应用、开始菜单快捷方式和卸载登记；卸载保留模型、环境、任务和用户输出。

## 构建

开发机需要 Python 3、.NET 8 SDK 和网络，macOS 可交叉编译，Windows 可运行 build.ps1。

```sh
python3 build.py --dotnet /path/to/dotnet
```

脚本自动同步 Mac 后端、发布 win-x64 自包含主程序、下载并校验固定版本 uv、嵌入应用载荷并发布单 EXE 安装器。产物位于工作区 outputs/ZhengxinOCR-Windows-Setup-1.0-test.exe。

后续重构 Mac 后端时必须运行 Windows 回归；core-source.json 记录本次同步来源及哈希，不能认为上游改变天然兼容适配层。

## 开发测试

```sh
python3 -m unittest discover -s tests -v
```

测试需要 psutil 和 PyMuPDF，覆盖原生文字提取、隐藏文字层、输出隔离、路径约束、模型文件校验、取消标志和指定进程取消。macOS 沙箱可能限制进程枚举，须在允许读取测试子进程信息的环境执行。

## MCP

配置 MCP 客户端使用 powershell.exe 及以下参数（替换实际用户路径）：

```text
-NoProfile -ExecutionPolicy Bypass -File C:\Users\用户名\AppData\Local\Programs\ZhengxinOCR\resources\cli.ps1 -Mcp
```

先打开应用完成准备。MCP 只返回任务元数据与本地路径，不返回全文；ocr_submit 默认普通扫描，可指定 complex 或 ancient。

## 已知限制与发布门槛

此版本是测试候选，不代表已通过 Windows 实机验收。必须在 Windows 测试首次安装、UAC、PowerShell、uv、Paddle DLL 加载、普通/复杂/古籍预测、断网识别、界面、取消进程树和卸载。

依赖解析与 WPF 编译通过不等于 OCR 模型兼容；原生 PaddleOCR-VL CPU 配置可能失败或速度较慢，失败会禁用该模式并保留日志。仍需真实古籍样本验收。首发不承诺 NVIDIA 加速、Windows ARM、AMD 或 Intel GPU。

模型清单目前记录首次准备时实际下载的文件，尚未冻结统一发行用的模型修订。模型来源版本和离线可用性、第三方分发许可清单、代码签名，以及安装器真实行为均为正式发布前待办。

环境准备期间不允许关闭主窗口；当前不提供暂停/手动续跑任务 UI、批量导入、全文搜索或格式转换。这些没有列为本次已实现功能。
