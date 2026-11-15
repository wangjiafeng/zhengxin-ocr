param([string]$Dotnet = 'dotnet')
$ErrorActionPreference = 'Stop'
# Developer build only. End users need neither Python nor .NET installed.
python (Join-Path $PSScriptRoot 'build.py') --dotnet $Dotnet
if ($LASTEXITCODE -ne 0) { throw 'Windows 安装包构建失败' }
