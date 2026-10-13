#Requires -Version 5.1
<#
    CodeLauncher —— 环境启动器（Windows 版）

    弹出一个面板，选择想要的环境，自动在 VS Code 新窗口打开。
    本文件是 macOS 版（Swift / Cocoa）的 Windows 移植版本。

    依赖：Windows 自带的 PowerShell 5.1 + .NET WinForms，无需安装任何东西。
    用法：双击 CodeLauncher.cmd，或运行  powershell -File CodeLauncher.ps1
#>

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()

# ══════════════════════════════════════════════════════════
#  配置
# ══════════════════════════════════════════════════════════

$script:AppTitle      = 'CodeLauncher'
$script:Root          = Join-Path $env:USERPROFILE 'VS Code'
$script:WorkspaceFile = Join-Path $script:Root 'c-projects.code-workspace'
$script:UiFont        = [System.Drawing.SystemFonts]::MessageBoxFont

# ══════════════════════════════════════════════════════════
#  工具函数
# ══════════════════════════════════════════════════════════

# 定位 VS Code 的 code 命令
function Get-VSCodeCommand {
    $cmd = Get-Command code -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA)  { $candidates.Add((Join-Path $env:LOCALAPPDATA  'Programs\Microsoft VS Code\bin\code.cmd')) }
    if ($env:ProgramFiles)  { $candidates.Add((Join-Path $env:ProgramFiles  'Microsoft VS Code\bin\code.cmd')) }
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86)              { $candidates.Add((Join-Path $pf86              'Microsoft VS Code\bin\code.cmd')) }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

# 统一的提示框
function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = $script:AppTitle,
        [string]$Icon  = 'Information'
    )
    [void][System.Windows.Forms.MessageBox]::Show(
        $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    )
}

# 下拉选择框（对应 macOS 版的 NSAlert + NSPopUpButton）
function Show-ListDialog {
    param(
        [Parameter(Mandatory)][string]  $Title,
        [Parameter(Mandatory)][string]  $Prompt,
        [Parameter(Mandatory)][string[]]$Items,
        [string]$OkText = '确定'
    )

    $form = New-Object System.Windows.Forms.Form
    try {
        $form.Text            = $Title
        $form.ClientSize      = New-Object System.Drawing.Size(400, 158)
        $form.StartPosition   = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox     = $false
        $form.MinimizeBox     = $false
        $form.Font            = $script:UiFont

        $label = New-Object System.Windows.Forms.Label
        $label.Text     = $Prompt
        $label.Location = New-Object System.Drawing.Point(18, 20)
        $label.Size     = New-Object System.Drawing.Size(364, 20)
        $form.Controls.Add($label)

        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.DropDownStyle = 'DropDownList'
        $combo.Location      = New-Object System.Drawing.Point(18, 48)
        $combo.Size          = New-Object System.Drawing.Size(364, 25)
        [void]$combo.Items.AddRange([object[]]$Items)
        if ($Items.Count -gt 0) { $combo.SelectedIndex = 0 }
        $form.Controls.Add($combo)

        $ok = New-Object System.Windows.Forms.Button
        $ok.Text         = $OkText
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $ok.Location     = New-Object System.Drawing.Point(212, 102)
        $ok.Size         = New-Object System.Drawing.Size(80, 30)
        $form.Controls.Add($ok)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text         = '取消'
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $cancel.Location     = New-Object System.Drawing.Point(302, 102)
        $cancel.Size         = New-Object System.Drawing.Size(80, 30)
        $form.Controls.Add($cancel)

        $form.AcceptButton = $ok
        $form.CancelButton = $cancel

        if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            if ($combo.SelectedItem) { return $combo.SelectedItem.ToString() }
        }
        return $null
    }
    finally {
        $form.Dispose()
    }
}

# 文本输入框（对应 macOS 版的 NSAlert + NSTextField）
function Show-InputDialog {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$DefaultValue = '',
        [string]$OkText       = '创建'
    )

    $form = New-Object System.Windows.Forms.Form
    try {
        $form.Text            = $Title
        $form.ClientSize      = New-Object System.Drawing.Size(400, 158)
        $form.StartPosition   = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox     = $false
        $form.MinimizeBox     = $false
        $form.Font            = $script:UiFont

        $label = New-Object System.Windows.Forms.Label
        $label.Text     = $Prompt
        $label.Location = New-Object System.Drawing.Point(18, 20)
        $label.Size     = New-Object System.Drawing.Size(364, 20)
        $form.Controls.Add($label)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point(18, 48)
        $box.Size     = New-Object System.Drawing.Size(364, 25)
        $box.Text     = $DefaultValue
        $form.Controls.Add($box)

        $ok = New-Object System.Windows.Forms.Button
        $ok.Text         = $OkText
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $ok.Location     = New-Object System.Drawing.Point(212, 102)
        $ok.Size         = New-Object System.Drawing.Size(80, 30)
        $form.Controls.Add($ok)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text         = '取消'
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $cancel.Location     = New-Object System.Drawing.Point(302, 102)
        $cancel.Size         = New-Object System.Drawing.Size(80, 30)
        $form.Controls.Add($cancel)

        $form.AcceptButton = $ok
        $form.CancelButton = $cancel
        $form.Add_Shown({ $box.SelectAll(); $box.Focus() })

        if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $t = $box.Text.Trim()
            if ($t) { return $t }
        }
        return $null
    }
    finally {
        $form.Dispose()
    }
}

# 扫描已有项目
function Get-Projects {
    if (-not (Test-Path -LiteralPath $script:Root)) { return @() }
    $items = Get-ChildItem -LiteralPath $script:Root -Directory -ErrorAction SilentlyContinue |
             Where-Object { -not $_.Name.StartsWith('.') } |
             Sort-Object Name |
             Select-Object -ExpandProperty Name
    return @($items)
}

# 在 VS Code 新窗口打开（-n 强制新窗口）
function Open-InVSCode {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$CodeCmd
    )
    Start-Process -FilePath $CodeCmd -ArgumentList @('-n', "`"$Path`"") | Out-Null
}

# 调用 new-c.ps1 / new-py.ps1 建项目
function Invoke-Scaffold {
    param(
        [Parameter(Mandatory)][ValidateSet('c', 'py')][string]$Kind,
        [Parameter(Mandatory)][string]$Name
    )

    $fileName = if ($Kind -eq 'c') { 'new-c.ps1' } else { 'new-py.ps1' }

    # 1) 优先用与本脚本同目录的脚手架
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot $fileName
        if (Test-Path -LiteralPath $local) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $local $Name | Out-Null
            return
        }
    }

    # 2) 其次找 PATH 里的同名命令
    $bare = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $cmd  = Get-Command $bare -ErrorAction SilentlyContinue
    if ($cmd) {
        & $cmd.Source $Name | Out-Null
        return
    }

    throw "找不到 $fileName，请先运行 install.ps1 安装脚手架命令。"
}

# ══════════════════════════════════════════════════════════
#  主流程
# ══════════════════════════════════════════════════════════

try {
    $codeCmd = Get-VSCodeCommand
    if (-not $codeCmd) {
        Show-Message -Icon Error -Title '找不到 VS Code' -Text @"
没有找到 VS Code 的 code 命令。

请确认已安装 VS Code，并在其中按 Ctrl+Shift+P，
运行 “Shell Command: Install 'code' command in PATH”。

"@
        exit 1
    }

    if (-not (Test-Path -LiteralPath $script:Root)) {
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
    }

    # ── 面板 1：选择环境 ──
    $choice = Show-ListDialog -Title $script:AppTitle `
                              -Prompt '选择要创建或打开的环境：' `
                              -Items @('新建 C 项目', '新建 Python 项目', '打开已有项目', '打开多项目工作区')
    if (-not $choice) { exit 0 }

    # ── 新建项目 ──
    if ($choice -eq '新建 C 项目' -or $choice -eq '新建 Python 项目') {
        $name = Show-InputDialog -Title '新建项目' -Prompt '给项目起个名字：' -DefaultValue '我的新项目'
        if (-not $name) { exit 0 }

        if ($name -match '[\\/:*?"<>|]') {
            Show-Message -Icon Warning -Title '名字不合法' -Text "项目名不能包含这些字符： \ / : * ? `" < > |"
            exit 1
        }

        $dir = Join-Path $script:Root $name
        if (Test-Path -LiteralPath $dir) {
            Show-Message -Icon Warning -Title '项目已存在' -Text "「$name」已经存在了。`n`n$dir"
            exit 1
        }

        $kind = if ($choice -eq '新建 C 项目') { 'c' } else { 'py' }
        try {
            Invoke-Scaffold -Kind $kind -Name $name
        }
        catch {
            Show-Message -Icon Error -Title '创建失败' -Text $_.Exception.Message
            exit 1
        }

        if (Test-Path -LiteralPath $dir) {
            Open-InVSCode -Path $dir -CodeCmd $codeCmd
        }
        else {
            Show-Message -Icon Error -Title '创建失败' -Text @"
脚手架执行完了，但没有生成目录：

$dir

请检查 new-c / new-py 是否可用（运行 install.ps1 安装）。
"@
            exit 1
        }
        exit 0
    }

    # ── 多项目工作区 ──
    if ($choice -eq '打开多项目工作区') {
        if (Test-Path -LiteralPath $script:WorkspaceFile) {
            Open-InVSCode -Path $script:WorkspaceFile -CodeCmd $codeCmd
        }
        else {
            Show-Message -Icon Warning -Title '工作区不存在' -Text @"
找不到工作区文件：

$script:WorkspaceFile

可以在 VS Code 里用 “文件 → 将文件夹添加到工作区”
自己建一个，另存为该路径即可。
"@
        }
        exit 0
    }

    # ── 打开已有项目 ──
    $projects = Get-Projects
    if ($projects.Count -eq 0) {
        Show-Message -Icon Information -Title '还没有项目' -Text "先新建一个 C 或 Python 项目吧。`n`n项目目录：$script:Root"
        exit 0
    }

    $sel = Show-ListDialog -Title '打开项目' -Prompt '选择要打开的项目：' -Items $projects -OkText '打开'
    if ($sel) {
        Open-InVSCode -Path (Join-Path $script:Root $sel) -CodeCmd $codeCmd
    }
    exit 0
}
catch {
    Show-Message -Icon Error -Title "$script:AppTitle 出错了" -Text $_.Exception.Message
    exit 1
}
