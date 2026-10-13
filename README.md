# CodeLauncher

选好环境，自动在 VS Code 新窗口打开 —— 目录结构、编译与调试配置一次生成，不用再手动建目录、配 `tasks.json`、敲命令。

**适配环境**　C ｜ Python

**已适配软件**　<img src="assets/vscode.png" width="20"> Visual Studio Code

## 安装

**macOS**

```bash
git clone https://github.com/Alooshy0827/CodeLauncher.git
cd CodeLauncher/macos && ./build.sh --install
cp new-c new-py ~/bin/
```

**Windows**

下载本仓库 → 右键 `windows/install.ps1` → 使用 PowerShell 运行

## 依赖

- [VS Code](https://code.visualstudio.com/)
- C 项目：C 编译器（MinGW / clang / MSVC 自动检测）
- Python 项目：Python 3

## License

[MIT](LICENSE)
