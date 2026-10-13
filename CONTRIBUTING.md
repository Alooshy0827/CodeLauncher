# 开发注意

## ⚠️ `windows/*.ps1` 必须保留 UTF-8 BOM

Windows PowerShell 5.1（系统自带那个）读取**没有 BOM** 的 `.ps1` 时，会按系统 ANSI 码页（中文系统是 GBK）解析，脚本里所有中文都会变成乱码 —— 界面文字全废。

这个坑尤其隐蔽：BOM 被抹掉后，**本地和远程是一致地坏**，`git status`、`git diff`、和远程对比都看不出来。

所以 `windows/*.ps1` **必须**以 `EF BB BF` 开头。很多编辑器（包括各种 AI 编程工具）保存时会悄悄抹掉 BOM，改完记得确认：

```bash
head -c 3 windows/new-c.ps1 | xxd -p    # 应输出 efbbbf
```

批量补 BOM：

```bash
python3 -c "
import glob
BOM = b'\xef\xbb\xbf'
for f in glob.glob('windows/*.ps1'):
    raw = open(f,'rb').read()
    if not raw.startswith(BOM):
        open(f,'wb').write(BOM + raw); print('fixed', f)
"
```

## 改完 PowerShell 脚本建议校验语法

不用真的跑到 Windows 上，用 PowerShell 自带的 AST 解析器就能查出语法错误：

```bash
pwsh -Command "
\$e=\$null
[System.Management.Automation.Language.Parser]::ParseFile('windows/new-c.ps1',[ref]\$null,[ref]\$e)
if(\$e.Count){ \$e | %{ \$_.Message } } else { 'OK' }
"
```

## 构建 macOS 版

```bash
cd macos
./build.sh            # 构建到 ./dist/
./build.sh --install  # 构建并安装到 ~/Applications/
```

源码只有 `main.swift` 一个文件，用系统自带的 `swiftc` 编译，无第三方依赖。

## 目录约定

- 项目根目录路径目前是写死的：macOS 是 `~/VS Code/`，Windows 是 `%USERPROFILE%\VS Code\`
- 要改的话，编辑 `macos/main.swift` 顶部的 `root` 和 `windows/CodeLauncher.ps1` 顶部的 `$script:Root`

## README 标题图标的对齐方式

`assets/` 下有两个图标，用途不同：

| 文件 | 用途 |
|---|---|
| `appicon.png` | 干净的方形图标原图（256×256） |
| `appicon-title.png` | README 标题专用（256×316，底部多 60px 透明边距） |

标题用的是后者，配合 `align="absmiddle"`：

```html
# <img src="assets/appicon-title.png" width="36" align="absmiddle"> CodeLauncher
```

**为什么要留白**：GitHub 会把 `style` 和 `class` 属性清洗掉，只剩 `align` 可用来控制垂直对齐。而 `align="absmiddle"` 是把整张图（含透明区）在行内居中 —— 底部那 60px 透明区会把可见图标往上顶约 3px，正好抵消掉默认的偏低。实测偏差从 +3.5px 收敛到 −0.5px。

改图标时记得**重新导出这两个文件**：先出方形原图，再在底部补 60px 透明边距。

> 别用 `align="middle"` —— 实测偏低 11.5px，比默认的偏高 6.5px 还糟。

## 怎么加一个新环境

启动器**不存环境列表**。它扫描目录里所有 `new-*` 脚本，从脚本开头的
`# @label XXX` 读取显示名，菜单是运行时生成的。所以加环境只需要两步：

**1. 写脚手架脚本**

- macOS：`macos/new-xxx`（bash，记得 `chmod +x`）
- Windows：`windows/new-xxx.ps1`（PowerShell，**必须带 UTF-8 BOM**）

脚本第一行注释声明显示名：

```bash
#!/bin/bash
# @label Rust
```

```powershell
#Requires -Version 5.1
# @label Rust
```

没有 `@label` 也能用，会回退成文件名首字母大写（`new-rust` → `Rust`）。

**2. 完事**

`build.sh` 和 `install.ps1` 都是按 `new-*` 通配收录的，不用改。
把脚本放进 `~/bin`（macOS）或 `%USERPROFILE%\bin`（Windows）即可生效。

### 脚手架约定

- 项目建到 `~/VS Code/<名字>`（Windows 是 `%USERPROFILE%\VS Code\`）
- **检测工具链时要真的执行一次**，不能只看 `command -v` / `Get-Command`。
  macOS 没装 JDK 时 `/usr/bin/javac` 也存在，但那只是个占位存根；
  Windows 上 Oracle 的 `javapath` 在 JDK 卸载后也会留坏存根。
- 工具链缺失时**照常建项目**，但在项目根目录写一个 `!缺少工具链.md`，
  里面写清楚缺什么、怎么装。启动器会检测到这个文件并额外弹窗提醒。

### 排查「我的环境没出现在菜单里」

```bash
CODELAUNCHER_LIST=1 ~/Applications/环境启动器.app/Contents/MacOS/launcher
```

会直接列出发现到的环境、标签和来源路径，不开面板。
