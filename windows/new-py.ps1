#Requires -Version 5.1
# @label Python
<#
    new-py —— 一键新建 Python 项目（Windows 版）
    用法: new-py 项目名

    自动创建虚拟环境（.venv），并配好 VS Code 解释器路径与自动激活。
#>

param(
    [Parameter(Position = 0)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

if (-not $Name) {
    Write-Host '用法: new-py 项目名'
    Write-Host '例如: new-py 我的脚本'
    exit 1
}

if ($Name -match '[\\/:*?"<>|]') {
    Write-Host "❌ 项目名不能包含这些字符: \ / : * ? `" < > |"
    exit 1
}

$Root = Join-Path $env:USERPROFILE 'VS Code'
$Dir  = Join-Path $Root $Name

if (Test-Path -LiteralPath $Dir) {
    Write-Host "❌ 项目 '$Name' 已存在: $Dir"
    exit 1
}

# ══════════════════════════════════════════════════════════
#  找 Python
# ══════════════════════════════════════════════════════════

function Find-Tool {
    param([Parameter(Mandatory)][string]$Tool)
    $c = Get-Command $Tool -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

$pyLauncher = Find-Tool 'py'
$python     = Find-Tool 'python'

if ($pyLauncher) {
    # py 启动器最可靠，能正确处理商店版 Python 的别名问题
    $pyExe  = $pyLauncher
    $pyArgs = @('-3')
}
elseif ($python) {
    $pyExe  = $python
    $pyArgs = @()
}
else {
    # 没装 Python 也照常建项目，只是跳过虚拟环境，并在项目里留强提示
    $pyExe  = $null
    $pyArgs = @()
    Write-Host '⚠️  没有检测到 Python，将跳过虚拟环境创建。' -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════
#  建目录
# ══════════════════════════════════════════════════════════

New-Item -ItemType Directory -Path (Join-Path $Dir '.vscode') -Force | Out-Null

# ── 创建虚拟环境 ──
$venvDir = Join-Path $Dir '.venv'
$venvOk  = $false
if ($pyExe) {
    Write-Host '正在创建虚拟环境（几秒钟）...'
    & $pyExe @pyArgs -m venv $venvDir
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $venvDir 'Scripts/python.exe'))) {
        Write-Host '  ✅ 虚拟环境已建好'
        $venvOk = $true
    }
    else {
        Write-Host '  ⚠️  虚拟环境创建失败' -ForegroundColor Yellow
    }
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Text {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

# ── main.py ──
$mainPy = @'
def main():
    print("你好，Python！")


if __name__ == "__main__":
    main()
'@
Write-Text (Join-Path $Dir 'main.py') $mainPy

# ── .vscode/settings.json（指定解释器 + 自动激活 venv）──
$settings = @'
{
    "python.defaultInterpreterPath": "${workspaceFolder}/.venv/Scripts/python.exe",
    "python.terminal.activateEnvironment": true
}
'@
Write-Text (Join-Path $Dir '.vscode/settings.json') $settings

# ── 工具链缺失时的项目内强提示 ──
if (-not $venvOk) {
    $notice = @'
# ⚠️ 这个项目现在跑不起来

缺少 **Python 3**，所以虚拟环境没能创建。

## 怎么装（推荐）

在 PowerShell 里运行：

```powershell
winget install --id Python.Python.3.12
```

也可以到 https://www.python.org/downloads/ 下载安装包。

> ⚠️ 安装时务必勾选 **Add python.exe to PATH**，否则命令行里找不到 python。

## 装完之后

**重开一个终端**（PATH 才会生效），在项目目录里手动补上虚拟环境：

```powershell
cd "本项目所在目录"
python -m venv .venv
```

然后：

1. **删掉本文件**
2. 回到 VS Code，按 `F5` 运行，或在终端里执行 `python main.py`

> 项目结构本身是完整的，只是少了 `.venv` 那一层虚拟环境。
'@
    Write-Text (Join-Path $Dir '!缺少工具链.md') $notice
}

Write-Host ''
Write-Host "✅ 项目创建成功: $Dir"
Write-Host ''
Write-Host '结构:'
Write-Host "  $Name/"
Write-Host '  ├── main.py         ← 在这里写代码'
if ($venvOk) {
    Write-Host '  ├── .venv/          ← Python 虚拟环境（已建好）'
}
else {
    Write-Host '  ├── .venv/          ← ⚠️ 未创建（缺 Python）' -ForegroundColor Yellow
}
Write-Host '  └── .vscode/        ← 配置'
Write-Host ''

if ($venvOk) {
    Write-Host '下一步:'
    Write-Host "  code `"$Dir`"          用 VS Code 打开"
    Write-Host '  然后按 F5 运行，或者终端里 python main.py'
}
else {
    Write-Host '⚠️  没有检测到 Python，虚拟环境未创建。' -ForegroundColor Yellow
    Write-Host '   已在项目里生成 !缺少工具链.md，打开它看安装方法。' -ForegroundColor Yellow
}
