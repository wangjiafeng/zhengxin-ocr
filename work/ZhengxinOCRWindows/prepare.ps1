param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$env:PYTHONUTF8 = '1'
$root = Join-Path $env:LOCALAPPDATA 'ZhengxinOCR'
$env:ZHENGXIN_OCR_SUPPORT = $root
$env:UV_PYTHON_INSTALL_DIR = Join-Path $root 'python'
$env:UV_CACHE_DIR = Join-Path $root 'cache\uv'
$env:PADDLE_PDX_CACHE_HOME = Join-Path $root 'models\paddlex'
$env:HF_HOME = Join-Path $root 'models\huggingface'
$backend = Join-Path $PSScriptRoot 'backend\windows_backend.py'
$requirements = Join-Path $PSScriptRoot 'backend\requirements-cpu.lock'
$uv = Join-Path $PSScriptRoot 'tools\uv.exe'
$pointer = Join-Path $root 'runtime.json'
$lock = $null
New-Item -ItemType Directory -Force $root | Out-Null
function Run-Native([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "执行失败（$LASTEXITCODE）：$Program" }
}
function Save-Json([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -Force $temporary $Path
}
try {
    $lock = [IO.File]::Open((Join-Path $root 'prepare.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') {
        throw '当前安装程序支持 Windows x64。'
    }
    if (-not (Test-Path $uv)) { throw '安装文件缺少 uv.exe，请重新安装程序。' }
    if (-not (Test-Path (Join-Path $env:SystemRoot 'System32\msvcp140.dll')) -or -not (Test-Path (Join-Path $env:SystemRoot 'System32\vcruntime140.dll'))) {
        Write-Output '检测到缺少 Microsoft C++ 运行库，正在下载官方安装程序；系统可能请求管理员授权。'
        $cache = Join-Path $root 'cache'
        New-Item -ItemType Directory -Force $cache | Out-Null
        $redist = Join-Path $cache 'vc_redist.x64.exe'
        Invoke-WebRequest -UseBasicParsing 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $redist
        $signature = Get-AuthenticodeSignature $redist
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Microsoft C++ 运行库签名校验失败' }
        $install = Start-Process $redist -ArgumentList '/install','/quiet','/norestart' -Verb RunAs -Wait -PassThru
        if ($install.ExitCode -notin @(0, 1638, 3010)) { throw "Microsoft C++ 运行库安装失败：$($install.ExitCode)" }
        if ($install.ExitCode -eq 3010) { throw 'Microsoft C++ 运行库需要重启 Windows，重启后打开正心OCR将自动继续。' }
    }
    $hash = (Get-FileHash $requirements -Algorithm SHA256).Hash.ToLowerInvariant()
    $python = $null
    if (Test-Path $pointer) {
        try {
            $old = Get-Content -Raw $pointer | ConvertFrom-Json
            if ($old.config_hash -eq $hash -and (Test-Path $old.python) -and -not $Repair) {
                & $old.python -c 'import paddle,paddleocr,pymupdf,PIL,psutil; paddle.utils.run_check()'
                if ($LASTEXITCODE -eq 0) { $python = $old.python }
            }
        } catch { Write-Output '旧环境记录不可用，将自动建立新环境。' }
    }
    if (-not $python) {
        # Never clear the active environment. Build, verify, then switch a small pointer.
        $candidate = Join-Path $root ('runtime\' + [Guid]::NewGuid().ToString('N'))
        Write-Output '[1/4] 检测兼容 Python；缺少时自动安装 Python 3.11'
        Run-Native $uv @('venv', '--python', '3.11', $candidate)
        $python = Join-Path $candidate 'Scripts\python.exe'
        Write-Output '[2/4] 安装应用专用 OCR 依赖'
        Run-Native $uv @('pip', 'install', '--python', $python, '--require-hashes', '--only-binary', ':all:', '--requirements', $requirements)
        Run-Native $python @('-c', 'import paddle,paddleocr,pymupdf,PIL,psutil; paddle.utils.run_check()')
        Save-Json $pointer @{python=$python; config_hash=$hash; backend='cpu'; installed_at=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
    }
    Write-Output '[3/4] 检测硬件（本候选版使用 CPU，NVIDIA 加速尚待实机验证）'
    $gpu = @()
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $gpu = @(& nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>$null)
    }
    Save-Json (Join-Path $root 'hardware.json') @{nvidia=$gpu; selected_backend='cpu'}
    Write-Output '[4/4] 自动下载模型并逐模式执行识别自检；首次可能耗时较长'
    $ready = 0
    foreach ($mode in @('modern', 'complex', 'ancient')) {
        $marker = Join-Path $root "models\$mode.json"
        $skip = $false
        if ((Test-Path $marker) -and -not $Repair) {
            & $python $backend check-mode $mode
            $skip = $LASTEXITCODE -eq 0
        }
        if (-not $skip) {
            Write-Output "准备模式：$mode"
            & $python $backend prepare-mode $mode
            if ($LASTEXITCODE -ne 0) { Write-Output "模式 $mode 自检失败，保留其他可用模式；详情见准备日志。"; continue }
        }
        $ready++
    }
    if ($ready -eq 0) { throw '所有模式自检失败，请查看准备日志并点击修复重试。' }
    Write-Output "准备完成，$ready 种模式可用。"
    exit 0
} catch {
    Write-Output "准备失败：$($_.Exception.Message)"
    exit 1
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
