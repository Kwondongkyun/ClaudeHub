import Foundation
import AppKit

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iterm2 = "iTerm"
    case warp = "Warp"
    case ghostty = "Ghostty"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal.app"
        case .iterm2: return "iTerm2"
        case .warp: return "Warp"
        case .ghostty: return "Ghostty"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) != nil
    }

    private var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        case .ghostty: return "com.mitchellh.ghostty"
        }
    }
}

enum TerminalLauncher {
    static func resumeSession(
        sessionId: String,
        projectPath: String,
        terminal: TerminalApp
    ) {
        let ep = shellEscape(projectPath)
        let ei = shellEscape(sessionId)
        let command = "unset CLAUDECODE && cd \(ep) 2>/dev/null; claude --resume \(ei)"

        switch terminal {
        case .terminal:
            launchTerminalApp(command: command)
        case .iterm2:
            launchITerm2(command: command)
        case .warp:
            launchViaShellScript(command: command, projectPath: projectPath, appName: "Warp")
        case .ghostty:
            launchViaShellScript(command: command, projectPath: projectPath, appName: "Ghostty")
        }
    }

    private static func launchTerminalApp(command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapeAppleScript(command))"
        end tell
        """
        runAppleScript(script)
    }

    private static func launchITerm2(command: String) {
        let script = """
        tell application "iTerm"
            activate
            tell current window
                create tab with default profile
                tell current session
                    write text "\(escapeAppleScript(command))"
                end tell
            end tell
        end tell
        """
        runAppleScript(script)
    }

    /// 프로젝트 디렉토리에 임시 셸 스크립트 생성 후 open -a 로 실행
    private static func launchViaShellScript(command: String, projectPath: String, appName: String) {
        let scriptPath = "\(projectPath)/.claudehub_resume.sh"
        // 스크립트 실행 후 자기 자신 삭제
        let scriptContent = "#!/bin/bash\nrm -f \(shellEscape(scriptPath))\nclear\n\(command)\n"

        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptPath
            )
        } catch {
            print("Failed to write script: \(error)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appName, scriptPath]

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    print("open -a \(appName) failed: exit \(process.terminationStatus)")
                }
            } catch {
                print("open launch error: \(error)")
            }
        }
    }

    // MARK: - Script Runners

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }

    /// Process로 /usr/bin/osascript 실행 — NSAppleScript 샌드박스 제한 우회
    private static func runOsascript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let stdinPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = []
            process.standardInput = stdinPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                // stdin으로 스크립트 전달
                stdinPipe.fileHandleForWriting.write(source.data(using: .utf8)!)
                stdinPipe.fileHandleForWriting.closeFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(decoding: errData, as: UTF8.self)
                    print("osascript error: \(errStr)")
                }
            } catch {
                print("osascript launch error: \(error)")
            }
        }
    }

    private static func escapeAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
