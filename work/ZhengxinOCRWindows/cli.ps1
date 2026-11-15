param([switch]$Mcp, [Parameter(ValueFromRemainingArguments=$true)][string[]]$CliArguments)
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$root = Join-Path $env:LOCALAPPDATA 'ZhengxinOCR'
try {
    $runtime = Get-Content -Raw (Join-Path $root 'runtime.json') | ConvertFrom-Json
    $script = if ($Mcp) { 'mcp.py' } else { 'windows_backend.py' }
    & $runtime.python (Join-Path $PSScriptRoot "backend\$script") @CliArguments
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine('请先启动正心OCR完成运行环境准备：' + $_.Exception.Message)
    exit 1
}
