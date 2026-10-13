#Requires -Version 5.1
# @label C++
<#
    new-cpp —— 一键新建 C++ 项目（Windows 版）
    用法: new-cpp 项目名

    自动检测本机 C++ 工具链（MinGW-w64 g++ / LLVM clang++ / MSVC cl），
    生成对应的 .vscode 配置，开箱即可编译（Ctrl+Shift+B）和调试（F5）。
#>

param(
    [Parameter(Position = 0)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

if (-not $Name) {
    Write-Host '用法: new-cpp 项目名'
    Write-Host '例如: new-cpp 我的程序'
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
#  工具链检测
# ══════════════════════════════════════════════════════════

function Find-Tool {
    param([Parameter(Mandatory)][string]$Tool)
    $c = Get-Command $Tool -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

# 光找到还不够 —— 必须真的跑一次能输出版本号，才算可用
function Test-Compiler {
    param([string]$Exe)
    if (-not $Exe) { return $false }
    try {
        $out = & $Exe --version 2>&1 | Out-String
        return [bool]($out -match '\S')
    }
    catch { return $false }
}

$gppRaw     = Find-Tool 'g++'
$clangppRaw = Find-Tool 'clang++'
$gpp     = if (Test-Compiler $gppRaw)     { $gppRaw }     else { $null }
$clangpp = if (Test-Compiler $clangppRaw) { $clangppRaw } else { $null }
$cl      = Find-Tool 'cl'
$gdb     = Find-Tool 'gdb'
$lldb    = Find-Tool 'lldb'

if ($gpp) {
    $toolchain = 'mingw'; $cc = $gpp; $debugger = $gdb; $intellisense = 'windows-gcc-x64'
}
elseif ($clangpp) {
    $toolchain = 'clang'; $cc = $clangpp; $debugger = $lldb; $intellisense = 'windows-clang-x64'
}
elseif ($cl) {
    $toolchain = 'msvc'; $cc = $cl; $debugger = $null; $intellisense = 'windows-msvc-x64'
}
else {
    $toolchain = 'none'; $cc = 'g++'; $debugger = $null; $intellisense = 'windows-gcc-x64'
}

# ══════════════════════════════════════════════════════════
#  建目录
# ══════════════════════════════════════════════════════════

New-Item -ItemType Directory -Path (Join-Path $Dir 'src')     -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Dir 'build')   -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Dir '.vscode') -Force | Out-Null

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Text {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}
function To-Slash { param([string]$Path) if (-not $Path) { return $null } return ($Path -replace '\\', '/') }

$ccJson = To-Slash $cc

# ══════════════════════════════════════════════════════════
#  .vscode 配置
# ══════════════════════════════════════════════════════════

if ($toolchain -eq 'msvc') {

    $props = @'
{
    "version": 4,
    "configurations": [
        {
            "name": "Win-C++ (MSVC)",
            "includePath": [
                "${workspaceFolder}/src/**"
            ],
            "defines": [
                "_CRT_SECURE_NO_WARNINGS"
            ],
            "compilerPath": "__COMPILER__",
            "cppStandard": "c++17",
            "intelliSenseMode": "windows-msvc-x64"
        }
    ]
}
'@

    $tasks = @'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "编译",
            "type": "shell",
            "command": "cmd.exe",
            "args": [
                "/c",
                "\"\"${config:msvc.vcvars}\" && cl.exe /nologo /std:c++17 /EHsc /W4 /Zi /Fe:\"${workspaceFolder}/build/main.exe\" /Fo:\"${workspaceFolder}/build/\" \"${workspaceFolder}/src/main.cpp\"\""
            ],
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": ["$msCompile"],
            "group": { "kind": "build", "isDefault": true },
            "detail": "Ctrl+Shift+B：用 MSVC 编译 src/main.cpp"
        },
        {
            "label": "运行",
            "type": "shell",
            "command": "${workspaceFolder}/build/main.exe",
            "dependsOn": "编译",
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": [],
            "detail": "先编译再运行"
        }
    ]
}
'@

    $launch = @'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "调试 (F5)",
            "type": "cppvsdbg",
            "request": "launch",
            "program": "${workspaceFolder}/build/main.exe",
            "args": [],
            "stopAtEntry": false,
            "cwd": "${workspaceFolder}",
            "environment": [],
            "console": "externalTerminal",
            "preLaunchTask": "编译"
        }
    ]
}
'@

    $settings = @'
{
    "msvc.vcvars": "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat"
}
'@
    Write-Text (Join-Path $Dir '.vscode/settings.json') $settings
}
else {

    $props = @'
{
    "version": 4,
    "configurations": [
        {
            "name": "Win-C++",
            "includePath": [
                "${workspaceFolder}/src/**"
            ],
            "defines": [],
            "compilerPath": "__COMPILER__",
            "cppStandard": "c++17",
            "cStandard": "c17",
            "intelliSenseMode": "__INTELLISENSE__"
        }
    ]
}
'@

    $tasks = @'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "编译",
            "type": "shell",
            "command": "__COMPILER__",
            "args": [
                "-std=c++17", "-Wall", "-Wextra", "-g", "-O0",
                "-o", "${workspaceFolder}/build/main.exe",
                "${workspaceFolder}/src/main.cpp"
            ],
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": ["$gcc"],
            "group": { "kind": "build", "isDefault": true },
            "detail": "Ctrl+Shift+B：编译 src/main.cpp"
        },
        {
            "label": "运行",
            "type": "shell",
            "command": "${workspaceFolder}/build/main.exe",
            "dependsOn": "编译",
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": [],
            "detail": "先编译再运行"
        }
    ]
}
'@

    $mimode = if ($toolchain -eq 'clang' -and $lldb) { 'lldb' } else { 'gdb' }

    $launch = @'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "调试 (F5)",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/build/main.exe",
            "args": [],
            "stopAtEntry": false,
            "cwd": "${workspaceFolder}",
            "environment": [],
            "externalConsole": true,
            "MIMode": "__MIMODE__",
            "miDebuggerPath": "__DEBUGGER__",
            "preLaunchTask": "编译",
            "setupCommands": [
                {
                    "description": "启用整齐打印",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }
            ]
        }
    ]
}
'@
}

$props = $props.Replace('__COMPILER__', $ccJson).Replace('__INTELLISENSE__', $intellisense)
$tasks = $tasks.Replace('__COMPILER__', $ccJson)

if ($toolchain -ne 'msvc') {
    $dbgJson = To-Slash $debugger
    if ($dbgJson) {
        $launch = $launch.Replace('__MIMODE__', $mimode).Replace('__DEBUGGER__', $dbgJson)
    }
    else {
        # 没找到调试器时整行删掉；留空的 miDebuggerPath 会让 cppdbg 启动失败
        $launch = $launch -replace '(?m)^\s*"miDebuggerPath": "__DEBUGGER__",\r?\n', ''
        $launch = $launch.Replace('__MIMODE__', $mimode)
    }
}

Write-Text (Join-Path $Dir '.vscode/c_cpp_properties.json') $props
Write-Text (Join-Path $Dir '.vscode/tasks.json')           $tasks
Write-Text (Join-Path $Dir '.vscode/launch.json')          $launch

# ══════════════════════════════════════════════════════════
#  源码骨架
# ══════════════════════════════════════════════════════════

$mainCpp = @'
#include <iostream>

int main()
{
    std::cout << "Hello, C++!" << std::endl;
    return 0;
}
'@
Write-Text (Join-Path $Dir 'src/main.cpp') $mainCpp

# ══════════════════════════════════════════════════════════
#  工具链缺失时的项目内强提示
# ══════════════════════════════════════════════════════════

if ($toolchain -eq 'none') {
    $notice = @'
# ⚠️ 这个项目现在还编译不了

缺少 **C++ 编译器**（`g++`、`clang++`、`cl` 都没找到）。

## 怎么装（推荐 MinGW-w64）

在 PowerShell 里运行：

```powershell
winget install --id BrechtSanders.WinLibs.POSIX.UCRT
```

装完**重开一个终端**（PATH 才会生效）。

也可以用 MSYS2：

```powershell
winget install --id MSYS2.MSYS2
# 然后打开 MSYS2 终端运行：
# pacman -S mingw-w64-ucrt-x86_64-gcc
```

## 怎么确认装好了

重开终端后运行：

```powershell
g++ --version
```

能输出版本号就成了。

## 装完之后

1. **删掉本文件**
2. 回到 VS Code，按 `Ctrl+Shift+B` 编译，`F5` 调试

> 项目本身不用重建 —— 编译器装好，这个项目直接就能用。
> 如果 `Ctrl+Shift+B` 报错说找不到 g++，重启一次 VS Code 让它重新读取 PATH。
'@
    Write-Text (Join-Path $Dir '!缺少工具链.md') $notice
}

# ══════════════════════════════════════════════════════════
#  汇报
# ══════════════════════════════════════════════════════════

$toolName = switch ($toolchain) {
    'mingw' { "MinGW-w64 g++  ($cc)" }
    'clang' { "LLVM clang++   ($cc)" }
    'msvc'  { "MSVC cl.exe    ($cc)" }
    default { '未检测到（需要手动安装）' }
}

Write-Host ''
Write-Host "✅ 项目创建成功: $Dir"
Write-Host ''
Write-Host '结构:'
Write-Host "  $Name/"
Write-Host '  ├── src/main.cpp    ← 在这里写代码'
Write-Host '  ├── .vscode/        ← 配置（已配好，不用管）'
Write-Host '  └── build/          ← 编译产物'
Write-Host ''
Write-Host "工具链: $toolName"
Write-Host ''

if ($toolchain -eq 'none') {
    Write-Host '⚠️  没有检测到 C++ 编译器，现在还不能编译。' -ForegroundColor Yellow
    Write-Host '   已在项目里生成 !缺少工具链.md，打开它看安装方法。' -ForegroundColor Yellow
    Write-Host ''
}

if ($toolchain -eq 'msvc') {
    Write-Host 'ℹ️  检测到 MSVC。若编译报错，请打开 .vscode/settings.json' -ForegroundColor Cyan
    Write-Host '   把 msvc.vcvars 改成你机器上 vcvars64.bat 的真实路径。' -ForegroundColor Cyan
    Write-Host ''
}

Write-Host '下一步:'
Write-Host "  code `"$Dir`"          用 VS Code 打开"
Write-Host '  然后按 Ctrl+Shift+B 编译，F5 调试运行'
