#Requires -Version 5.1
# @label C
<#
    new-c —— 一键新建 C 项目（Windows 版）
    用法: new-c 项目名

    自动检测本机 C 工具链（MinGW-w64 / LLVM clang / MSVC），
    生成对应的 .vscode 配置，开箱即可编译（Ctrl+Shift+B）和调试（F5）。
#>

param(
    [Parameter(Position = 0)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

if (-not $Name) {
    Write-Host '用法: new-c 项目名'
    Write-Host '例如: new-c 我的程序'
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

$gcc   = Find-Tool 'gcc'
$clang = Find-Tool 'clang'
$cl    = Find-Tool 'cl'
$gdb   = Find-Tool 'gdb'
$lldb  = Find-Tool 'lldb'

if ($gcc) {
    $toolchain = 'mingw'
    $cc        = $gcc
    $debugger  = $gdb
    $intellisense = 'windows-gcc-x64'
}
elseif ($clang) {
    $toolchain = 'clang'
    $cc        = $clang
    $debugger  = $lldb
    $intellisense = 'windows-clang-x64'
}
elseif ($cl) {
    $toolchain = 'msvc'
    $cc        = $cl
    $debugger  = $null
    $intellisense = 'windows-msvc-x64'
}
else {
    $toolchain = 'none'
    $cc        = 'gcc'
    $debugger  = $null
    $intellisense = 'windows-gcc-x64'
}

# ══════════════════════════════════════════════════════════
#  建目录
# ══════════════════════════════════════════════════════════

New-Item -ItemType Directory -Path (Join-Path $Dir 'src')     -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Dir 'build')   -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Dir '.vscode') -Force | Out-Null

# 写文件工具：一律 UTF-8 无 BOM（JSON / 源码通用）
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Text {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

# 把路径转成 JSON 友好的正斜杠形式
function To-Slash {
    param([string]$Path)
    if (-not $Path) { return $null }
    return ($Path -replace '\\', '/')
}

# ══════════════════════════════════════════════════════════
#  .vscode 配置
# ══════════════════════════════════════════════════════════

$ccJson = To-Slash $cc

if ($toolchain -eq 'msvc') {

    # MSVC：cl.exe 需要 VS 开发者环境，用 cmd 先加载 vcvars64.bat
    $props = @'
{
    "version": 4,
    "configurations": [
        {
            "name": "Win-C (MSVC)",
            "includePath": [
                "${workspaceFolder}/src/**"
            ],
            "defines": [
                "_CRT_SECURE_NO_WARNINGS"
            ],
            "compilerPath": "__COMPILER__",
            "cStandard": "c17",
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
                "\"\"${config:msvc.vcvars}\" && cl.exe /nologo /std:c17 /W4 /Zi /Fe:\"${workspaceFolder}/build/main.exe\" /Fo:\"${workspaceFolder}/build/\" \"${workspaceFolder}/src/main.c\"\""
            ],
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": ["$msCompile"],
            "group": { "kind": "build", "isDefault": true },
            "detail": "Ctrl+Shift+B：用 MSVC 编译 src/main.c"
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

    # MinGW / clang：gcc 风格命令行
    $props = @'
{
    "version": 4,
    "configurations": [
        {
            "name": "Win-C",
            "includePath": [
                "${workspaceFolder}/src/**"
            ],
            "defines": [],
            "compilerPath": "__COMPILER__",
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
                "-std=c17", "-Wall", "-Wextra", "-g", "-O0",
                "-o", "${workspaceFolder}/build/main.exe",
                "${workspaceFolder}/src/main.c"
            ],
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": ["$gcc"],
            "group": { "kind": "build", "isDefault": true },
            "detail": "Ctrl+Shift+B：编译 src/main.c"
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
        # 没找到调试器时，整行删掉；留空的 miDebuggerPath 会让 cppdbg 启动失败
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

$mainC = @'
#include <stdio.h>

int main(void)
{

    return 0;
}
'@
Write-Text (Join-Path $Dir 'src/main.c') $mainC

# ══════════════════════════════════════════════════════════
#  汇报
# ══════════════════════════════════════════════════════════

$toolName = switch ($toolchain) {
    'mingw' { "MinGW-w64 gcc  ($cc)" }
    'clang' { "LLVM clang      ($cc)" }
    'msvc'  { "MSVC cl.exe     ($cc)" }
    default { '未检测到（需要手动安装）' }
}

Write-Host ''
Write-Host "✅ 项目创建成功: $Dir"
Write-Host ''
Write-Host '结构:'
Write-Host "  $Name/"
Write-Host '  ├── src/main.c      ← 在这里写代码'
Write-Host '  ├── .vscode/        ← 配置（已配好，不用管）'
Write-Host '  └── build/          ← 编译产物'
Write-Host ''
Write-Host "工具链: $toolName"
Write-Host ''

if ($toolchain -eq 'none') {
    Write-Host '⚠️  没有检测到 C 编译器，现在还不能编译。' -ForegroundColor Yellow
    Write-Host '   推荐安装 MinGW-w64（任选其一）:' -ForegroundColor Yellow
    Write-Host '     winget install --id BrechtSanders.WinLibs.POSIX.UCRT' -ForegroundColor Yellow
    Write-Host '     或到 https://www.msys2.org 安装 MSYS2 后: pacman -S mingw-w64-ucrt-x86_64-gcc' -ForegroundColor Yellow
    Write-Host '   装完重开终端，这个项目无需重建，直接就能编译。' -ForegroundColor Yellow
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
