import Cocoa

// ── 找 VS Code 的 code 命令 ──
let codePath = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

func runShell(_ cmd: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-lc", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// ── 在主线程跑一段代码并取回结果（让面板在前台）──
func onMain(_ body: () -> Void) {
    if Thread.isMainThread { body() }
    else { DispatchQueue.main.sync(execute: body) }
}

// ── 面板 1：选择环境 ──
func chooseEnvironment() -> String? {
    var result: String? = nil
    onMain {
        let alert = NSAlert()
        alert.messageText = "环境启动器"
        alert.informativeText = "选择要创建或打开的环境："
        alert.addButton(withTitle: "下一步")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 25), pullsDown: false)
        popup.addItems(withTitles: [
            "新建 C 项目",
            "新建 Python 项目",
            "打开已有项目",
            "打开多项目工作区"
        ])
        alert.accessoryView = popup
        NSApp.activate(ignoringOtherApps: true)

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            result = popup.titleOfSelectedItem
        }
    }
    return result
}

// ── 面板 2：输入项目名 ──
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

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            let t = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            result = t.isEmpty ? nil : t
        }
    }
    return result
}

// ── 面板 3：从列表选择 ──
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

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
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

func openInVSCode(_ path: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: codePath)
    p.arguments = ["-n", path]
    // 清掉 ELECTRON_RUN_AS_NODE，否则 code 会以 node 模式运行
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "ELECTRON_RUN_AS_NODE")
    p.environment = env
    try? p.run()
}

// ══ 主流程 ══
let home = FileManager.default.homeDirectoryForCurrentUser.path
let root = "\(home)/VS Code"

guard let choice = chooseEnvironment() else { exit(0) }

if choice == "新建 C 项目" || choice == "新建 Python 项目" {
    guard let name = askName(defaultName: "我的新项目") else { exit(0) }
    let dir = "\(root)/\(name)"

    if FileManager.default.fileExists(atPath: dir) {
        onMain {
            let a = NSAlert()
            a.messageText = "项目已存在"
            a.informativeText = "「\(name)」已经存在了。"
            a.addButton(withTitle: "知道了")
            a.runModal()
        }
        exit(1)
    }

    let tool = (choice == "新建 C 项目") ? "new-c" : "new-py"
    _ = runShell("/opt/homebrew/bin/\(tool) '\(name)'")

    if FileManager.default.fileExists(atPath: dir) {
        openInVSCode(dir)
        notify("✅ \(name)", "已在新窗口打开")
    } else {
        onMain {
            let a = NSAlert()
            a.messageText = "创建失败"
            a.informativeText = "请检查 new-c / new-py 命令是否可用。"
            a.addButton(withTitle: "知道了")
            a.runModal()
        }
    }
    exit(0)
}

if choice == "打开多项目工作区" {
    let ws = "\(root)/c-projects.code-workspace"
    if FileManager.default.fileExists(atPath: ws) {
        openInVSCode(ws)
    } else {
        onMain {
            let a = NSAlert()
            a.messageText = "工作区不存在"
            a.informativeText = "找不到 c-projects.code-workspace"
            a.addButton(withTitle: "知道了")
            a.runModal()
        }
    }
    exit(0)
}

// 打开已有项目
let fm = FileManager.default
let contents = (try? fm.contentsOfDirectory(atPath: root)) ?? []
let projects = contents.filter { name in
    var isDir: ObjCBool = false
    let full = "\(root)/\(name)"
    return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue && !name.hasPrefix(".")
}.sorted()

if projects.isEmpty {
    onMain {
        let a = NSAlert()
        a.messageText = "还没有项目"
        a.informativeText = "先新建一个 C 或 Python 项目吧。"
        a.addButton(withTitle: "知道了")
        a.runModal()
    }
    exit(0)
}

if let sel = chooseFromList(title: "打开项目", prompt: "选择要打开的项目：", items: projects) {
    openInVSCode("\(root)/\(sel)")
}
