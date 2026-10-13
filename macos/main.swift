import Cocoa

// ══════════════════════════════════════════════════════════
//  基础工具
// ══════════════════════════════════════════════════════════

// 用户的登录 shell —— macOS 默认是 zsh，PATH 通常配在 zsh 的配置文件里，
// 写死 bash 会漏掉用户的 PATH 设置。
func loginShell() -> String {
    if let s = ProcessInfo.processInfo.environment["SHELL"],
       !s.isEmpty,
       FileManager.default.isExecutableFile(atPath: s) {
        return s
    }
    return "/bin/zsh"
}

func runShell(_ cmd: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: loginShell())
    p.arguments = ["-lc", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// 在主线程跑一段代码并取回结果（让面板在前台）
func onMain(_ body: () -> Void) {
    if Thread.isMainThread { body() }
    else { DispatchQueue.main.sync(execute: body) }
}

// 单引号转义，避免项目名里的特殊字符破坏 shell 命令
func shQuote(_ s: String) -> String {
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func alertBox(_ title: String, _ text: String) {
    onMain {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "知道了")
        a.runModal()
    }
}

// ══════════════════════════════════════════════════════════
//  脚手架发现
//
//  启动器不写死环境列表，而是扫描目录里所有 new-* 可执行文件，
//  从每个脚本开头的 "# @label XXX" 读取显示名。
//  加新环境 = 丢一个脚本进去，这个文件一行都不用改。
// ══════════════════════════════════════════════════════════

struct Scaffold {
    let id: String      // new-cpp
    let label: String   // C++
    let path: String
}

let home = FileManager.default.homeDirectoryForCurrentUser.path

func searchDirs() -> [String] {
    // 顺序即优先级：用户自己的 → PATH 里的 → App 自带的兜底副本
    var dirs = ["\(home)/bin"]
    dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":").map(String.init)
    if let res = Bundle.main.resourcePath {
        dirs.append("\(res)/scripts")
    }
    var seen = Set<String>()
    return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
}

func readLabel(_ path: String, fallback: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return fallback }
    for raw in text.split(separator: "\n").prefix(20) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("# @label") else { continue }
        let value = line.replacingOccurrences(of: "# @label", with: "")
            .trimmingCharacters(in: .whitespaces)
        if !value.isEmpty { return value }
    }
    return fallback
}

func discoverScaffolds() -> [Scaffold] {
    let fm = FileManager.default
    var found: [String: Scaffold] = [:]
    var order: [String] = []

    for dir in searchDirs() {
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
        for name in entries.sorted() where name.hasPrefix("new-") {
            guard found[name] == nil else { continue }          // 先找到的优先
            let full = "\(dir)/\(name)"
            guard fm.isExecutableFile(atPath: full) else { continue }
            // 没有 @label 时回退到文件名（new-py → Py），首字母大写好看一点
            let fallback = name.hasPrefix("new-")
                ? String(name.dropFirst(4)).capitalized
                : name
            found[name] = Scaffold(id: name,
                                   label: readLabel(full, fallback: fallback),
                                   path: full)
            order.append(name)
        }
    }
    return order.compactMap { found[$0] }
}

// ══════════════════════════════════════════════════════════
//  面板
// ══════════════════════════════════════════════════════════

enum Choice {
    case create(Scaffold)
    case openExisting
    case openWorkspace
}

func chooseEnvironment(_ scaffolds: [Scaffold]) -> Choice? {
    var titles = scaffolds.map { "新建 \($0.label) 项目" }
    titles.append("打开已有项目")
    titles.append("打开多项目工作区")

    var index = -1
    onMain {
        let alert = NSAlert()
        alert.messageText = "环境启动器"
        alert.informativeText = "选择要创建或打开的环境："
        alert.addButton(withTitle: "下一步")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 25), pullsDown: false)
        popup.addItems(withTitles: titles)
        alert.accessoryView = popup
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            index = popup.indexOfSelectedItem
        }
    }

    guard index >= 0 else { return nil }
    if index < scaffolds.count { return .create(scaffolds[index]) }
    return index == scaffolds.count ? .openExisting : .openWorkspace
}

func askName(defaultName: String) -> String? {
    var result: String? = nil
    onMain {
        let alert = NSAlert()
        alert.messageText = "新建项目"
        alert.informativeText = "给项目起个名字："
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultName
        field.placeholderString = "项目名"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            let t = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            result = t.isEmpty ? nil : t
        }
    }
    return result
}

func chooseFromList(title: String, prompt: String, items: [String]) -> String? {
    var result: String? = nil
    onMain {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: "打开")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 25), pullsDown: false)
        popup.addItems(withTitles: items)
        alert.accessoryView = popup
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            result = popup.titleOfSelectedItem
        }
    }
    return result
}

func notify(_ title: String, _ text: String) {
    onMain {
        let n = NSUserNotification()
        n.title = title
        n.informativeText = text
        NSUserNotificationCenter.default.deliver(n)
    }
}

// ══════════════════════════════════════════════════════════
//  VS Code
// ══════════════════════════════════════════════════════════

func findVSCode() -> String? {
    let candidates = [
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        "\(home)/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    ]
    for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
    let found = runShell("command -v code")
    return found.isEmpty ? nil : found
}

func openInVSCode(_ path: String, _ codePath: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: codePath)
    p.arguments = ["-n", path]
    // 清掉 ELECTRON_RUN_AS_NODE，否则 code 会以 node 模式运行而不是开窗口
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "ELECTRON_RUN_AS_NODE")
    p.environment = env
    try? p.run()
}

// ══════════════════════════════════════════════════════════
//  主流程
// ══════════════════════════════════════════════════════════

let root = "\(home)/VS Code"
let warningFileName = "!缺少工具链.md"

let scaffolds = discoverScaffolds()

// 调试开关：CODELAUNCHER_LIST=1 时只列出发现到的环境然后退出，不开面板。
// 排查「为什么我新加的环境没出现在菜单里」时很有用：
//   CODELAUNCHER_LIST=1 /Applications/环境启动器.app/Contents/MacOS/launcher
if ProcessInfo.processInfo.environment["CODELAUNCHER_LIST"] == "1" {
    for s in scaffolds { print("\(s.id)\t\(s.label)\t\(s.path)") }
    exit(0)
}

guard let codePath = findVSCode() else {
    alertBox("找不到 VS Code",
             "没能定位到 code 命令。\n\n请确认已安装 VS Code，并在其中按 Cmd+Shift+P 运行：\nShell Command: Install 'code' command in PATH")
    exit(1)
}

guard let choice = chooseEnvironment(scaffolds) else { exit(0) }

switch choice {

case .create(let scaffold):
    guard let name = askName(defaultName: "我的新项目") else { exit(0) }
    let dir = "\(root)/\(name)"

    if FileManager.default.fileExists(atPath: dir) {
        alertBox("项目已存在", "「\(name)」已经存在了。")
        exit(1)
    }

    _ = runShell("\(shQuote(scaffold.path)) \(shQuote(name))")

    guard FileManager.default.fileExists(atPath: dir) else {
        alertBox("创建失败",
                 "脚手架 \(scaffold.id) 没有生成项目目录。\n\n可以在「终端」里手动跑一次看报错：\n\(scaffold.path) \(name)")
        exit(1)
    }

    openInVSCode(dir, codePath)

    // 脚手架发现缺工具链时会在项目里留下一个提示文件，这里再强提醒一次
    if FileManager.default.fileExists(atPath: "\(dir)/\(warningFileName)") {
        alertBox("⚠️ 缺少工具链",
                 "项目已创建，但本机缺少它需要的工具链，现在还不能编译。\n\n已在项目里生成「\(warningFileName)」，里面有安装方法。")
    } else {
        notify("✅ \(name)", "已在新窗口打开")
    }
    exit(0)

case .openWorkspace:
    let ws = "\(root)/c-projects.code-workspace"
    if FileManager.default.fileExists(atPath: ws) {
        openInVSCode(ws, codePath)
    } else {
        alertBox("工作区不存在",
                 "找不到：\(ws)\n\n可以在 VS Code 里用「文件 → 将文件夹添加到工作区」自己建一个，另存为该路径。")
    }
    exit(0)

case .openExisting:
    let fm = FileManager.default
    let contents = (try? fm.contentsOfDirectory(atPath: root)) ?? []
    let projects = contents.filter { n in
        var isDir: ObjCBool = false
        let full = "\(root)/\(n)"
        return fm.fileExists(atPath: full, isDirectory: &isDir)
            && isDir.boolValue
            && !n.hasPrefix(".")
    }.sorted()

    if projects.isEmpty {
        alertBox("还没有项目", "先新建一个项目吧。\n\n项目目录：\(root)")
        exit(0)
    }

    if let sel = chooseFromList(title: "打开项目", prompt: "选择要打开的项目：", items: projects) {
        openInVSCode("\(root)/\(sel)", codePath)
    }
    exit(0)
}
