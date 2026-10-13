#Requires -Version 5.1
# @label Java
<#
    new-java —— 一键新建 Java 项目（Windows 版）
    用法: new-java 项目名

    自动检测 JDK，生成可直接编译运行的 .vscode 配置。
#>

param(
    [Parameter(Position = 0)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

if (-not $Name) {
    Write-Host '用法: new-java 项目名'
    Write-Host '例如: new-java 我的程序'
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
#  检测 JDK
# ══════════════════════════════════════════════════════════

function Find-Tool {
    param([Parameter(Mandatory)][string]$Tool)
    $c = Get-Command $Tool -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

# 光找到 javac 不算数 —— JDK 卸载后 Oracle 的 javapath 里可能残留坏存根，
# 所以必须真的跑一次，确认输出的是 javac 版本号。
function Test-Javac {
    param([string]$Exe)
    if (-not $Exe) { return $false }
    try {
        $out = & $Exe -version 2>&1 | Out-String
        return ($out -match 'javac\s+\d')
    }
    catch { return $false }
}

$javacRaw = Find-Tool 'javac'
$javac = if (Test-Javac $javacRaw) { $javacRaw } else { $null }
$java  = Find-Tool 'java'

# ══════════════════════════════════════════════════════════
#  建目录
# ══════════════════════════════════════════════════════════

New-Item -ItemType Directory -Path (Join-Path $Dir 'src')     -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Dir 'bin')     -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Dir '.vscode') -Force | Out-Null

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Text {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

# ── src/Main.java ──
$mainJava = @'
public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, Java!");
    }
}
'@
Write-Text (Join-Path $Dir 'src/Main.java') $mainJava

# ── .vscode/settings.json（给 Java 扩展用）──
$settings = @'
{
    "java.project.sourcePaths": ["src"],
    "java.project.outputPath": "bin",
    "java.configuration.updateBuildConfiguration": "automatic"
}
'@
Write-Text (Join-Path $Dir '.vscode/settings.json') $settings

# ── .vscode/tasks.json（不依赖任何扩展，javac + java 直接可用）──
$tasks = @'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "编译",
            "type": "shell",
            "command": "javac",
            "args": [
                "-encoding", "UTF-8",
                "-d", "${workspaceFolder}/bin",
                "${workspaceFolder}/src/Main.java"
            ],
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": ["$javac"],
            "group": { "kind": "build", "isDefault": true },
            "detail": "Ctrl+Shift+B：编译 src/Main.java"
        },
        {
            "label": "运行",
            "type": "shell",
            "command": "java",
            "args": ["-cp", "${workspaceFolder}/bin", "Main"],
            "dependsOn": "编译",
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": [],
            "detail": "先编译再运行"
        }
    ]
}
'@
Write-Text (Join-Path $Dir '.vscode/tasks.json') $tasks

# ── .vscode/launch.json（配合 Extension Pack for Java）──
$launch = @'
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "java",
            "name": "调试 (F5)",
            "request": "launch",
            "mainClass": "Main",
            "projectName": "__PROJECT__",
            "cwd": "${workspaceFolder}"
        }
    ]
}
'@
Write-Text (Join-Path $Dir '.vscode/launch.json') ($launch.Replace('__PROJECT__', $Name))

# ══════════════════════════════════════════════════════════
#  工具链缺失时的项目内强提示
# ══════════════════════════════════════════════════════════

if (-not $javac) {
    $notice = @'
# ⚠️ 这个项目现在还编译不了

缺少 **JDK**（找不到可用的 `javac`）。

注意：光有 `java` 不够 —— 运行 Java 只要 JRE，但**编译**需要 JDK。

## 怎么装（推荐）

在 PowerShell 里运行：

```powershell
winget install --id Microsoft.OpenJDK.21
```

或者用 Eclipse Temurin：

```powershell
winget install --id EclipseAdoptium.Temurin.21.JDK
```

也可以到 https://adoptium.net 下载 `.msi` 安装包，双击一路下一步。

## 怎么确认装好了

**重开一个终端**（PATH 才会生效），运行：

```powershell
javac -version
```

能输出版本号就成了。

## 装完之后

1. **删掉本文件**
2. 回到 VS Code，按 `Ctrl+Shift+B` 编译

## 建议

顺手装上 VS Code 扩展 **Extension Pack for Java**，
装好后 `Main.java` 里 `main` 上方会出现 Run / Debug 按钮，`F5` 也能直接调试。

> 项目本身不用重建 —— JDK 装好，这个项目直接就能用。
> 如果 `Ctrl+Shift+B` 报错说找不到 javac，重启一次 VS Code 让它重新读取 PATH。
'@
    Write-Text (Join-Path $Dir '!缺少工具链.md') $notice
}

# ══════════════════════════════════════════════════════════
#  汇报
# ══════════════════════════════════════════════════════════

Write-Host ''
Write-Host "✅ 项目创建成功: $Dir"
Write-Host ''
Write-Host '结构:'
Write-Host "  $Name/"
Write-Host '  ├── src/Main.java   ← 在这里写代码'
Write-Host '  ├── .vscode/        ← 配置（已配好，不用管）'
Write-Host '  └── bin/            ← 编译产物'
Write-Host ''

if ($javac) {
    $ver = (& $javac -version 2>&1 | Select-Object -First 1)
    Write-Host "JDK: $javac"
    Write-Host "     $ver"
}
else {
    Write-Host '⚠️  没有检测到 JDK，现在还不能编译。' -ForegroundColor Yellow
    Write-Host '   已在项目里生成 !缺少工具链.md，打开它看安装方法。' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '下一步:'
Write-Host "  code `"$Dir`"          用 VS Code 打开"
Write-Host "  然后按 Ctrl+Shift+B 编译，F5 调试运行"
