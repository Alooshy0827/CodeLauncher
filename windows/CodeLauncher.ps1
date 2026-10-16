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
$script:WarningFileName = '!缺少工具链.md'

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

# ── 向导的一步 ──
# 对应 macOS 版的主按钮 / 上一步 / 取消 三键布局。
# 返回值: @{ Nav = 'next'|'back'|'cancel'; Value = 控件当前值 }
function Show-WizardStep {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Prompt,
        [System.Windows.Forms.Control]$Accessory,
        [string]$NextText = '下一步',
        [switch]$AllowBack
    )

    $form = New-Object System.Windows.Forms.Form
    try {
        $form.Text            = $Title
        $form.ClientSize      = New-Object System.Drawing.Size(420, 210)
        $form.StartPosition   = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox     = $false
        $form.MinimizeBox     = $false
        $form.Font            = $script:UiFont

        $label = New-Object System.Windows.Forms.Label
        $label.Text     = $Prompt
        $label.Location = New-Object System.Drawing.Point(18, 16)
        $label.Size     = New-Object System.Drawing.Size(384, 68)
        $form.Controls.Add($label)

        if ($Accessory) {
            $Accessory.Location = New-Object System.Drawing.Point(18, 92)
            $Accessory.Size     = New-Object System.Drawing.Size(384, 26)
            $form.Controls.Add($Accessory)
        }

        # 按钮从右往左排：主按钮最右，取消最左
        $btnY = 158
        $next = New-Object System.Windows.Forms.Button
        $next.Text         = $NextText
        $next.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $next.Size         = New-Object System.Drawing.Size(88, 30)
        $next.Location     = New-Object System.Drawing.Point(314, $btnY)
        $form.Controls.Add($next)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text         = '取消'
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $cancel.Size         = New-Object System.Drawing.Size(88, 30)
        $cancel.Location     = New-Object System.Drawing.Point(218, $btnY)
        $form.Controls.Add($cancel)

        if ($AllowBack) {
            $back = New-Object System.Windows.Forms.Button
            $back.Text         = '上一步'
            # 借用 Retry 表示「上一步」，和 OK / Cancel 区分开
            $back.DialogResult = [System.Windows.Forms.DialogResult]::Retry
            $back.Size         = New-Object System.Drawing.Size(88, 30)
            $back.Location     = New-Object System.Drawing.Point(122, $btnY)
            $form.Controls.Add($back)
        }

        $form.AcceptButton = $next
        $form.CancelButton = $cancel

        if ($Accessory -is [System.Windows.Forms.TextBox]) {
            $form.Add_Shown({ $Accessory.SelectAll(); $Accessory.Focus() })
        }

        $result = $form.ShowDialog()

        $nav = 'cancel'
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $nav = 'next' }
        elseif ($AllowBack -and $result -eq [System.Windows.Forms.DialogResult]::Retry) { $nav = 'back' }

        # 值必须在 Dispose 之前取出来，否则控件已经没了
        $value = $null
        if ($Accessory -is [System.Windows.Forms.ComboBox]) {
            if ($Accessory.SelectedItem) { $value = $Accessory.SelectedItem.ToString() }
        }
        elseif ($Accessory -is [System.Windows.Forms.TextBox]) {
            $value = $Accessory.Text.Trim()
        }

        return [pscustomobject]@{ Nav = $nav; Value = $value }
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

# ══════════════════════════════════════════════════════════
#  脚手架发现
#
#  不写死环境列表，而是扫描目录里所有 new-*.ps1，
#  从脚本开头的 "# @label XXX" 读取显示名。
#  加新环境 = 丢一个脚本进去，这个文件一行都不用改。
# ══════════════════════════════════════════════════════════

function Get-ScaffoldDirs {
    # 顺序即优先级：用户自己的 → PATH 里的 → 与本脚本同目录的兜底副本
    $dirs = New-Object System.Collections.Generic.List[string]
    $dirs.Add((Join-Path $env:USERPROFILE 'bin'))
    if ($env:PATH) {
        foreach ($d in ($env:PATH -split ';')) {
            if ($d -and $d.Trim()) { $dirs.Add($d.Trim()) }
        }
    }
    if ($PSScriptRoot) { $dirs.Add($PSScriptRoot) }

    $seen = @{}
    $out  = New-Object System.Collections.Generic.List[string]
    foreach ($d in $dirs) {
        if ($seen.ContainsKey($d)) { continue }
        $seen[$d] = $true
        $out.Add($d)
    }
    return $out
}

function Get-Scaffolds {
    $found = @{}
    $order = New-Object System.Collections.Generic.List[string]

    foreach ($dir in (Get-ScaffoldDirs)) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $files = Get-ChildItem -LiteralPath $dir -Filter 'new-*.ps1' -File -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $id = $f.BaseName
            if ($found.ContainsKey($id)) { continue }   # 先找到的优先

            $label = $null
            $head = Get-Content -LiteralPath $f.FullName -TotalCount 20 -ErrorAction SilentlyContinue
            foreach ($line in $head) {
                if ($line -match '^\s*#\s*@label\s+(.+?)\s*$') { $label = $Matches[1]; break }
            }
            if (-not $label) {
                # 没有 @label 时回退到文件名（new-py → Py）
                $label = (Get-Culture).TextInfo.ToTitleCase(($id -replace '^new-', ''))
            }

            $found[$id] = [pscustomobject]@{ Id = $id; Label = $label; Path = $f.FullName }
            $order.Add($id)
        }
    }
    return @($order | ForEach-Object { $found[$_] } | Sort-Object Label)
}

# 调用指定的脚手架脚本建项目
function Invoke-Scaffold {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path $Name | Out-Null
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

    # 注意：这里**不**预建 $script:Root 目录。
    # 根目录推迟到第 3 步真正创建项目时才建，这样用户在前面任何一步
    # 取消，磁盘上都不会留下任何东西（Get-Projects 对目录不存在是安全的）。

    # ══════════════════════════════════════════════════════
    #  三步向导
    #
    #  第 1 步选环境、第 2 步填名字、第 3 步确认。
    #  前两步**不碰磁盘**，只有第 3 步点「创建」才真正执行脚手架 ——
    #  中途随时可以「上一步」改回去，或者「取消」走人，
    #  不会留下一个建完就后悔的项目白占空间。
    # ══════════════════════════════════════════════════════

    $scaffolds = Get-Scaffolds
    $menu = @()
    foreach ($s in $scaffolds) { $menu += "新建 $($s.Label) 项目" }
    $menu += '打开已有项目'
    $menu += '打开多项目工作区'

    $stage    = 0
    $picked   = $null
    $name     = ''
    $envIndex = 0

    # 注意：PowerShell 里 switch 内的 continue 等价于跳出 switch（而不是
    # 跳过 while 的剩余部分）。这里 switch 之后没有别的语句，所以「留在当前
    # 步骤」的效果正好成立。若以后要在 switch 后面加代码，记得改成显式判断。
    while ($true) {
        switch ($stage) {

        # ── 第 1 步：选环境 ──
        0 {
            $combo = New-Object System.Windows.Forms.ComboBox
            $combo.DropDownStyle = 'DropDownList'
            [void]$combo.Items.AddRange([object[]]$menu)
            if ($menu.Count -gt 0) {
                $combo.SelectedIndex = if ($envIndex -ge 0 -and $envIndex -lt $menu.Count) { $envIndex } else { 0 }
            }

            $r = Show-WizardStep -Title '环境启动器 · 第 1 步，共 3 步' `
                                 -Prompt '选择要创建或打开的环境：' `
                                 -Accessory $combo
            if ($r.Nav -eq 'cancel') { exit 0 }

            if ($combo.SelectedIndex -ge 0) { $envIndex = $combo.SelectedIndex }
            $choice = $r.Value

            $picked = $scaffolds | Where-Object { "新建 $($_.Label) 项目" -eq $choice } | Select-Object -First 1

            if ($picked) {
                $stage = 1
            }
            elseif ($choice -eq '打开多项目工作区') {
                # 只读操作，不写磁盘
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
            else {
                $projects = Get-Projects
                if ($projects.Count -eq 0) {
                    Show-Message -Icon Information -Title '还没有项目' -Text "先新建一个项目吧。`n`n项目目录：$script:Root"
                }
                else {
                    $sel = Show-ListDialog -Title '打开项目' -Prompt '选择要打开的项目：' -Items $projects -OkText '打开'
                    if ($sel) { Open-InVSCode -Path (Join-Path $script:Root $sel) -CodeCmd $codeCmd }
                }
                exit 0
            }
        }

        # ── 第 2 步：填项目名 ──
        1 {
            $box = New-Object System.Windows.Forms.TextBox
            $box.Text = if ($name) { $name } else { '我的新项目' }

            $r = Show-WizardStep -Title '环境启动器 · 第 2 步，共 3 步' `
                                 -Prompt "给「$($picked.Label)」项目起个名字：" `
                                 -Accessory $box -AllowBack
            if ($r.Nav -eq 'cancel') { exit 0 }
            if ($r.Nav -eq 'back') { $stage = 0; continue }

            $name = $r.Value

            # 校验不过就留在本步让用户改，而不是建到一半才报错
            if (-not $name) {
                Show-Message -Icon Warning -Title '名字不能为空' -Text '请给项目起个名字。'
                continue
            }
            if ($name -match '[\\/:*?"<>|]') {
                Show-Message -Icon Warning -Title '名字不合法' -Text "项目名不能包含这些字符： \ / : * ? `" < > |"
                continue
            }
            if (Test-Path -LiteralPath (Join-Path $script:Root $name)) {
                Show-Message -Icon Warning -Title '项目已存在' -Text "「$name」已经存在了。`n`n换个名字吧。"
                continue
            }
            $stage = 2
        }

        # ── 第 3 步：确认后才真正创建 ──
        2 {
            $dir = Join-Path $script:Root $name

            $r = Show-WizardStep -Title '环境启动器 · 第 3 步，共 3 步' `
                                 -Prompt "环境：$($picked.Label)`n名称：$name`n位置：$dir" `
                                 -NextText '创建' -AllowBack
            if ($r.Nav -eq 'cancel') { exit 0 }
            if ($r.Nav -eq 'back') { $stage = 1; continue }

            # ★★★ 整个程序里唯一产生副作用的地方 ★★★
            if (-not (Test-Path -LiteralPath $script:Root)) {
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
            }
            try {
                Invoke-Scaffold -Path $picked.Path -Name $name
            }
            catch {
                Show-Message -Icon Error -Title '创建失败' -Text $_.Exception.Message
                exit 1
            }

            if (-not (Test-Path -LiteralPath $dir)) {
                Show-Message -Icon Error -Title '创建失败' -Text @"
脚手架执行完了，但没有生成目录：

$dir

可以在 PowerShell 里手动跑一次看报错：
$($picked.Path) $name
"@
                exit 1
            }

            Open-InVSCode -Path $dir -CodeCmd $codeCmd

            # 脚手架发现缺工具链时会在项目里留下提示文件，这里再强提醒一次
            if (Test-Path -LiteralPath (Join-Path $dir $script:WarningFileName)) {
                Show-Message -Icon Warning -Title '⚠️ 缺少工具链' -Text @"
项目已创建，但本机缺少它需要的工具链，现在还不能编译。

已在项目里生成「$($script:WarningFileName)」，里面有安装方法。
"@
            }
            exit 0
        }

        default { exit 0 }
        }
    }
}
catch {
    Show-Message -Icon Error -Title "$script:AppTitle 出错了" -Text $_.Exception.Message
    exit 1
}
