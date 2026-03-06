# ClaudeHub Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** macOS 메뉴바 앱으로 Claude Code 세션을 통합 관리하고 클릭 한 번으로 resume하는 도구 구현

**Architecture:** Swift + SwiftUI 메뉴바 앱. `~/.claude/projects/`의 JSONL 세션 파일을 파싱하여 프로젝트별로 분류하고, 좌/우 분할 레이아웃(30:70)으로 표시. 카드 클릭 시 AppleScript로 선택된 터미널에서 resume 실행.

**Tech Stack:** Swift 5.9+, SwiftUI, MenuBarExtra, Foundation (외부 의존성 없음)

---

## Task 1: 프로젝트 스캐폴딩

**Files:**
- Create: `ClaudeHub/Package.swift`
- Create: `ClaudeHub/Sources/ClaudeHubApp.swift`

**Step 1: Package.swift 생성**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeHub",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeHub",
            path: "Sources"
        )
    ]
)
```

**Step 2: 최소 앱 엔트리포인트 생성**

```swift
import SwiftUI

@main
struct ClaudeHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Text("ClaudeHub - Coming Soon")
                .padding()
        } label: {
            Image(systemName: "bubble.left.and.text.bubble.right")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

**Step 3: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 4: 커밋**

```bash
git add ClaudeHub/Package.swift ClaudeHub/Sources/ClaudeHubApp.swift
git commit -m "feat: ClaudeHub 프로젝트 스캐폴딩 — 메뉴바 앱 기본 구조"
```

---

## Task 2: 데이터 모델 (Session, Project)

**Files:**
- Create: `ClaudeHub/Sources/Models/Session.swift`
- Create: `ClaudeHub/Sources/Models/Project.swift`

**Step 1: Session 모델 생성**

```swift
import Foundation

struct Session: Identifiable, Hashable {
    let id: String
    let projectPath: String
    let title: String
    let lastModified: Date
    let gitBranch: String?
    let claudeVersion: String?
    var isPinned: Bool

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}
```

**Step 2: Project 모델 생성**

```swift
import Foundation

struct Project: Identifiable, Hashable {
    let id: String
    let displayName: String
    let fullPath: String
    var sessions: [Session]

    var sessionCount: Int { sessions.count }
    var pinnedCount: Int { sessions.filter(\.isPinned).count }

    var sortedSessions: [Session] {
        sessions.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastModified > rhs.lastModified
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }
}
```

**Step 3: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 4: 커밋**

```bash
git add ClaudeHub/Sources/Models/
git commit -m "feat: Session, Project 데이터 모델 추가"
```

---

## Task 3: JSONL 세션 파서

**Files:**
- Create: `ClaudeHub/Sources/Services/SessionParser.swift`

**Step 1: SessionParser 구현**

`~/.claude/projects/` 하위의 JSONL 파일을 파싱하여 세션 메타데이터를 추출한다. 성능을 위해 파일의 앞부분만 읽는다.

```swift
import Foundation

enum SessionParser {
    static func parse(fileURL: URL, isPinned: Bool) -> Session? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { handle.closeFile() }

        // 앞부분 64KB만 읽기 (성능)
        let data = handle.readData(ofLength: 65536)
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n")

        var sessionId: String?
        var cwd: String?
        var gitBranch: String?
        var version: String?
        var firstUserMessage: String?

        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            // 첫 번째 줄에서 메타데이터 추출
            if sessionId == nil {
                sessionId = json["sessionId"] as? String
                cwd = json["cwd"] as? String
                gitBranch = json["gitBranch"] as? String
                version = json["version"] as? String
            }

            // 첫 번째 사용자 메시지 찾기
            if firstUserMessage == nil,
               let message = json["message"] as? [String: Any],
               let role = message["role"] as? String,
               role == "user",
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let type = block["type"] as? String,
                       type == "text",
                       let text = block["text"] as? String {
                        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            firstUserMessage = String(cleaned.prefix(80))
                            break
                        }
                    }
                }
            }

            // 둘 다 찾았으면 종료
            if sessionId != nil && firstUserMessage != nil { break }
        }

        // sessionId가 없으면 파일명에서 추출
        let fileSessionId = sessionId ?? fileURL.deletingPathExtension().lastPathComponent

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modified = attributes?[.modificationDate] as? Date ?? Date.distantPast

        return Session(
            id: fileSessionId,
            projectPath: cwd ?? "",
            title: firstUserMessage ?? "(제목 없음)",
            lastModified: modified,
            gitBranch: gitBranch,
            claudeVersion: version,
            isPinned: isPinned
        )
    }
}
```

**Step 2: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 3: 커밋**

```bash
git add ClaudeHub/Sources/Services/SessionParser.swift
git commit -m "feat: JSONL 세션 파서 — 메타데이터 및 첫 사용자 메시지 추출"
```

---

## Task 4: 세션 스캐너 (프로젝트 디렉토리 탐색)

**Files:**
- Create: `ClaudeHub/Sources/Services/SessionScanner.swift`

**Step 1: SessionScanner 구현**

`~/.claude/projects/` 디렉토리를 스캔하여 프로젝트별 세션 목록을 생성한다.

```swift
import Foundation
import Combine

@MainActor
class SessionScanner: ObservableObject {
    @Published var projects: [Project] = []
    @Published var isLoading = false

    private var pinnedSessionIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "pinnedSessions") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "pinnedSessions") }
    }

    private let projectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    private var cancellables = Set<AnyCancellable>()
    private var refreshInterval: TimeInterval = 10

    func startAutoRefresh() {
        Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.scan() }
            }
            .store(in: &cancellables)
    }

    func scan() async {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let pinned = pinnedSessionIds

        var newProjects: [Project] = []

        for dir in projectDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let folderName = dir.lastPathComponent
            let fullPath = Self.folderNameToPath(folderName)
            let displayName = Self.extractDisplayName(from: fullPath)

            // .jsonl 파일 수집
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: []
            ) else { continue }

            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }
            guard !jsonlFiles.isEmpty else { continue }

            var sessions: [Session] = []
            for file in jsonlFiles {
                let sessionId = file.deletingPathExtension().lastPathComponent
                if let session = SessionParser.parse(
                    fileURL: file,
                    isPinned: pinned.contains(sessionId)
                ) {
                    sessions.append(session)
                }
            }

            guard !sessions.isEmpty else { continue }

            let project = Project(
                id: folderName,
                displayName: displayName,
                fullPath: fullPath,
                sessions: sessions
            )
            newProjects.append(project)
        }

        // 프로젝트를 최신 세션 기준 정렬
        projects = newProjects.sorted { lhs, rhs in
            let lhsLatest = lhs.sessions.map(\.lastModified).max() ?? .distantPast
            let rhsLatest = rhs.sessions.map(\.lastModified).max() ?? .distantPast
            return lhsLatest > rhsLatest
        }
    }

    // MARK: - Pin Management

    func togglePin(sessionId: String) {
        var pinned = pinnedSessionIds
        if pinned.contains(sessionId) {
            pinned.remove(sessionId)
        } else {
            pinned.insert(sessionId)
        }
        pinnedSessionIds = pinned

        // projects 내 해당 세션의 isPinned 업데이트
        for i in projects.indices {
            for j in projects[i].sessions.indices {
                if projects[i].sessions[j].id == sessionId {
                    projects[i].sessions[j].isPinned = pinned.contains(sessionId)
                }
            }
        }
    }

    // MARK: - Session Deletion

    func deleteSession(sessionId: String, in project: Project) {
        let dir = projectsDir.appendingPathComponent(project.id)
        let jsonlFile = dir.appendingPathComponent("\(sessionId).jsonl")
        let relatedDir = dir.appendingPathComponent(sessionId)

        try? FileManager.default.removeItem(at: jsonlFile)
        if FileManager.default.fileExists(atPath: relatedDir.path) {
            try? FileManager.default.removeItem(at: relatedDir)
        }

        // 핀 상태 정리
        var pinned = pinnedSessionIds
        pinned.remove(sessionId)
        pinnedSessionIds = pinned

        // 메모리에서도 제거
        for i in projects.indices {
            if projects[i].id == project.id {
                projects[i].sessions.removeAll { $0.id == sessionId }
                if projects[i].sessions.isEmpty {
                    projects.remove(at: i)
                }
                break
            }
        }
    }

    // MARK: - Helpers

    static func folderNameToPath(_ folderName: String) -> String {
        // "-Users-kwondong-kyun-Desktop-Claude-Code"
        // → "/Users/kwondong-kyun/Desktop/Claude-Code"
        guard folderName.hasPrefix("-") else { return folderName }
        return "/" + folderName.dropFirst().replacingOccurrences(of: "-", with: "/")
    }

    static func extractDisplayName(from path: String) -> String {
        // "/Users/kwondong-kyun/Desktop/Claude-Code" → "Claude-Code"
        (path as NSString).lastPathComponent
    }
}
```

**Step 2: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 3: 커밋**

```bash
git add ClaudeHub/Sources/Services/SessionScanner.swift
git commit -m "feat: 세션 스캐너 — 프로젝트 디렉토리 탐색, 핀, 삭제 기능"
```

---

## Task 5: 터미널 런처

**Files:**
- Create: `ClaudeHub/Sources/Services/TerminalLauncher.swift`

**Step 1: TerminalLauncher 구현**

AppleScript를 사용하여 선택된 터미널에서 `claude --resume` 명령을 실행한다.

```swift
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
        let command = "cd \(shellEscape(projectPath)) && claude --resume \(shellEscape(sessionId))"

        switch terminal {
        case .terminal:
            launchTerminalApp(command: command)
        case .iterm2:
            launchITerm2(command: command)
        case .warp:
            launchWarp(command: command)
        case .ghostty:
            launchGhostty(command: command)
        }
    }

    // MARK: - Terminal.app

    private static func launchTerminalApp(command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapeAppleScript(command))"
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - iTerm2

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

    // MARK: - Warp

    private static func launchWarp(command: String) {
        let script = """
        tell application "Warp"
            activate
        end tell
        delay 0.5
        tell application "System Events"
            tell process "Warp"
                keystroke "t" using command down
                delay 0.3
                keystroke "\(escapeAppleScript(command))"
                key code 36
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Ghostty

    private static func launchGhostty(command: String) {
        let script = """
        tell application "Ghostty"
            activate
        end tell
        delay 0.5
        tell application "System Events"
            tell process "Ghostty"
                keystroke "t" using command down
                delay 0.3
                keystroke "\(escapeAppleScript(command))"
                key code 36
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Helpers

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
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
```

**Step 2: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 3: 커밋**

```bash
git add ClaudeHub/Sources/Services/TerminalLauncher.swift
git commit -m "feat: 터미널 런처 — Terminal/iTerm2/Warp/Ghostty 지원"
```

---

## Task 6: 설정 관리

**Files:**
- Create: `ClaudeHub/Sources/Services/AppSettings.swift`

**Step 1: AppSettings 구현**

```swift
import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("selectedTerminal") var selectedTerminal: String = TerminalApp.terminal.rawValue
    @AppStorage("refreshInterval") var refreshInterval: Double = 10
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    var terminal: TerminalApp {
        get { TerminalApp(rawValue: selectedTerminal) ?? .terminal }
        set { selectedTerminal = newValue.rawValue }
    }

    var availableTerminals: [TerminalApp] {
        TerminalApp.allCases.filter(\.isInstalled)
    }
}
```

**Step 2: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 3: 커밋**

```bash
git add ClaudeHub/Sources/Services/AppSettings.swift
git commit -m "feat: 앱 설정 관리 — 터미널 선택, 새로고침 간격"
```

---

## Task 7: 세션 카드 뷰

**Files:**
- Create: `ClaudeHub/Sources/Views/SessionCardView.swift`

**Step 1: SessionCardView 구현**

```swift
import SwiftUI

struct SessionCardView: View {
    let session: Session
    let onResume: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onCopyId: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 상단: 핀 + 제목
            HStack(alignment: .top, spacing: 6) {
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }

            // 하단: 브랜치 + 시간
            HStack(spacing: 6) {
                if let branch = session.gitBranch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(branch)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(session.relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color(.selectedContentBackgroundColor).opacity(0.3) : Color(.quaternarySystemFill))
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { onResume() }
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(
                    session.isPinned ? "핀 해제" : "핀 고정",
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }

            Button {
                onCopyId()
            } label: {
                Label("세션 ID 복사", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("세션 삭제", systemImage: "trash")
            }
        }
    }
}
```

**Step 2: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 3: 커밋**

```bash
git add ClaudeHub/Sources/Views/SessionCardView.swift
git commit -m "feat: 세션 카드 뷰 — 호버, 컨텍스트 메뉴, 핀 표시"
```

---

## Task 8: 프로젝트 사이드바 뷰

**Files:**
- Create: `ClaudeHub/Sources/Views/ProjectSidebar.swift`

**Step 1: ProjectSidebar 구현**

```swift
import SwiftUI

struct ProjectSidebar: View {
    let projects: [Project]
    @Binding var selectedProjectId: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(projects) { project in
                    ProjectRow(
                        project: project,
                        isSelected: selectedProjectId == project.id
                    )
                    .onTapGesture {
                        selectedProjectId = project.id
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Text("\(project.sessionCount)개 세션")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color.accentColor
                        : (isHovered ? Color(.quaternarySystemFill) : .clear)
                )
        )
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}
```

**Step 2: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 3: 커밋**

```bash
git add ClaudeHub/Sources/Views/ProjectSidebar.swift
git commit -m "feat: 프로젝트 사이드바 — 선택 하이라이트, 호버 효과"
```

---

## Task 9: 설정 뷰

**Files:**
- Create: `ClaudeHub/Sources/Views/SettingsView.swift`

**Step 1: SettingsView 구현**

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 헤더
            HStack {
                Text("설정")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 터미널 선택
            VStack(alignment: .leading, spacing: 6) {
                Text("기본 터미널")
                    .font(.system(size: 12, weight: .medium))

                Picker("", selection: $settings.selectedTerminal) {
                    ForEach(settings.availableTerminals) { terminal in
                        Text(terminal.displayName).tag(terminal.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // 새로고침 간격
            VStack(alignment: .leading, spacing: 6) {
                Text("자동 새로고침 간격")
                    .font(.system(size: 12, weight: .medium))

                Picker("", selection: $settings.refreshInterval) {
                    Text("5초").tag(5.0)
                    Text("10초").tag(10.0)
                    Text("30초").tag(30.0)
                    Text("수동").tag(0.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 320, height: 200)
    }
}
```

**Step 2: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 3: 커밋**

```bash
git add ClaudeHub/Sources/Views/SettingsView.swift
git commit -m "feat: 설정 뷰 — 터미널 선택, 새로고침 간격"
```

---

## Task 10: 메인 뷰 (전체 조립)

**Files:**
- Create: `ClaudeHub/Sources/Views/MainView.swift`
- Modify: `ClaudeHub/Sources/ClaudeHubApp.swift`

**Step 1: MainView 구현**

```swift
import SwiftUI

struct MainView: View {
    @StateObject private var scanner = SessionScanner()
    @StateObject private var settings = AppSettings.shared
    @State private var selectedProjectId: String?
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var showDeleteConfirm = false
    @State private var sessionToDelete: (Session, Project)?

    private var selectedProject: Project? {
        projects.first { $0.id == selectedProjectId }
    }

    private var projects: [Project] {
        if searchText.isEmpty {
            return scanner.projects
        }
        let query = searchText.lowercased()
        return scanner.projects.compactMap { project in
            let filtered = project.sessions.filter {
                $0.title.lowercased().contains(query) ||
                project.displayName.lowercased().contains(query)
            }
            guard !filtered.isEmpty else { return nil }
            var p = project
            p.sessions = filtered
            return p
        }
    }

    private var displaySessions: [Session] {
        selectedProject?.sortedSessions ?? []
    }

    private var totalSessionCount: Int {
        scanner.projects.reduce(0) { $0 + $1.sessionCount }
    }

    private var totalPinnedCount: Int {
        scanner.projects.reduce(0) { $0 + $1.pinnedCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                ProjectSidebar(
                    projects: projects,
                    selectedProjectId: $selectedProjectId
                )
                .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)

                sessionList
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .task {
            await scanner.scan()
            if selectedProjectId == nil {
                selectedProjectId = scanner.projects.first?.id
            }
            scanner.startAutoRefresh()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .alert("세션 삭제", isPresented: $showDeleteConfirm) {
            Button("취소", role: .cancel) { sessionToDelete = nil }
            Button("삭제", role: .destructive) {
                if let (session, project) = sessionToDelete {
                    scanner.deleteSession(sessionId: session.id, in: project)
                    sessionToDelete = nil
                }
            }
        } message: {
            if let (session, _) = sessionToDelete {
                Text("'\(session.title)' 세션을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("세션 검색...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 16)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Session List

    private var sessionList: some View {
        Group {
            if displaySessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("세션 없음")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(displaySessions) { session in
                            SessionCardView(
                                session: session,
                                onResume: {
                                    TerminalLauncher.resumeSession(
                                        sessionId: session.id,
                                        projectPath: selectedProject?.fullPath ?? session.projectPath,
                                        terminal: settings.terminal
                                    )
                                },
                                onTogglePin: {
                                    scanner.togglePin(sessionId: session.id)
                                },
                                onDelete: {
                                    if let project = selectedProject {
                                        sessionToDelete = (session, project)
                                        showDeleteConfirm = true
                                    }
                                },
                                onCopyId: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.id, forType: .string)
                                }
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("전체 \(totalSessionCount)개 세션")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if totalPinnedCount > 0 {
                Text("· 핀 \(totalPinnedCount)개")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if scanner.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button {
                Task { await scanner.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(scanner.isLoading)

            Divider().frame(height: 12)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("종료")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
```

**Step 2: ClaudeHubApp.swift 업데이트**

`ClaudeHubApp.swift`의 `MenuBarExtra` body를 `Text("...")`에서 `MainView()`로 변경:

```swift
import SwiftUI

@main
struct ClaudeHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MainView()
        } label: {
            Image(systemName: "bubble.left.and.text.bubble.right")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

**Step 3: 빌드 확인**

Run: `cd ClaudeHub && swift build 2>&1`
Expected: Build Succeeded

**Step 4: 실행 테스트**

Run: `cd ClaudeHub && swift run 2>&1 &`
Expected: 메뉴바에 아이콘이 나타나고, 클릭하면 프로젝트 목록과 세션 카드가 표시됨

**Step 5: 커밋**

```bash
git add ClaudeHub/Sources/Views/MainView.swift ClaudeHub/Sources/ClaudeHubApp.swift
git commit -m "feat: 메인 뷰 조립 — 검색, 사이드바, 세션 리스트, 풋터 통합"
```

---

## Task 11: build.sh 빌드 스크립트

**Files:**
- Create: `ClaudeHub/build.sh`

**Step 1: build.sh 생성**

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="ClaudeHub"
BUNDLE_ID="com.claudehub.app"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "=== ClaudeHub Build ==="
echo ""

# [1/5] Release 빌드
echo "[1/5] Building release binary..."
swift build -c release 2>&1
BINARY="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    BINARY="$BUILD_DIR/release/$APP_NAME"
fi

# [2/5] .app 번들 생성
echo "[2/5] Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# [3/5] Ad-hoc 코드 서명
echo "[3/5] Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1

# [4/5] DMG 생성
echo "[4/5] Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_STAGING"

# [5/5] 설치 여부
echo ""
echo "[5/5] Done!"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
echo ""
read -p "Install to /Applications? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "Installed to /Applications/$APP_NAME.app"
fi
```

**Step 2: 실행 권한 부여**

Run: `chmod +x ClaudeHub/build.sh`

**Step 3: 커밋**

```bash
git add ClaudeHub/build.sh
git commit -m "feat: build.sh — 빌드/번들/서명/DMG 자동화 스크립트"
```

---

## Task 12: 최종 빌드 & 실행 테스트

**Step 1: Release 빌드**

Run: `cd ClaudeHub && swift build -c release 2>&1`
Expected: Build Succeeded

**Step 2: 실행 테스트**

Run: `cd ClaudeHub && swift run &`

검증 체크리스트:
- [ ] 메뉴바에 아이콘 표시됨
- [ ] 클릭하면 팝오버 열림
- [ ] 좌측에 프로젝트 목록 표시됨
- [ ] 프로젝트 클릭 시 우측에 세션 카드 표시됨
- [ ] 세션 카드에 제목, 브랜치, 시간 표시됨
- [ ] 세션 카드 클릭 시 터미널에서 resume 실행됨
- [ ] 검색 작동함
- [ ] 우클릭 컨텍스트 메뉴 (핀, 삭제, ID 복사) 작동함
- [ ] 설정에서 터미널 변경 가능
- [ ] 종료 버튼 작동함

**Step 3: DMG 빌드 (선택)**

Run: `cd ClaudeHub && bash build.sh`
Expected: .build/ClaudeHub.dmg 생성됨

**Step 4: 최종 커밋**

```bash
git add -A ClaudeHub/
git commit -m "feat: ClaudeHub v1.0.0 — Claude Code 세션 관리 macOS 메뉴바 앱"
```
