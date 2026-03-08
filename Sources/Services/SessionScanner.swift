import Foundation
import Combine

// 순수 함수들 — actor isolation 없음
private enum ScanHelper {
    static let skipFolders: Set<String> = ["-", ".DS_Store"]

    static func folderNameToPath(_ folderName: String) -> String {
        guard folderName.hasPrefix("-") else { return folderName }
        let parts = String(folderName.dropFirst()).components(separatedBy: "-")
        return rebuildPath(from: parts)
    }

    /// 파츠를 하이픈으로 이어붙이면서 실제 존재하는 경로를 탐욕적으로 매칭
    private static func rebuildPath(from parts: [String]) -> String {
        let fm = FileManager.default
        var currentPath = ""
        var i = 0

        while i < parts.count {
            var matched = false
            // 남은 파츠를 최대한 많이 이어붙여서(탐욕) 존재하는 경로를 찾음
            for j in stride(from: parts.count - 1, through: i, by: -1) {
                let candidate = parts[i...j].joined(separator: "-")
                let testPath = currentPath.isEmpty ? "/\(candidate)" : "\(currentPath)/\(candidate)"
                if fm.fileExists(atPath: testPath) {
                    currentPath = testPath
                    i = j + 1
                    matched = true
                    break
                }
            }
            if !matched {
                // 매치 실패 시 단일 파트 사용
                let part = parts[i]
                currentPath = currentPath.isEmpty ? "/\(part)" : "\(currentPath)/\(part)"
                i += 1
            }
        }

        return currentPath
    }

    static func extractDisplayName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func scanProjects(at projectsDir: URL, pinned: Set<String>) -> [Project] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var newProjects: [Project] = []

        for dir in projectDirs {
            let folderName = dir.lastPathComponent

            if skipFolders.contains(folderName) { continue }
            if folderName.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
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

            // JSONL의 cwd에서 실제 경로를 가져옴 (폴더명 복원은 fallback)
            let cwdPath = sessions.first(where: { !$0.projectPath.isEmpty })?.projectPath
            let fullPath = cwdPath ?? folderNameToPath(folderName)
            let displayName = extractDisplayName(from: fullPath)

            newProjects.append(Project(
                id: folderName,
                displayName: displayName,
                fullPath: fullPath,
                sessions: sessions
            ))
        }

        return newProjects.sorted { lhs, rhs in
            let lhsLatest = lhs.sessions.map(\.lastModified).max() ?? .distantPast
            let rhsLatest = rhs.sessions.map(\.lastModified).max() ?? .distantPast
            return lhsLatest > rhsLatest
        }
    }
}

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

    func startAutoRefresh(interval: TimeInterval = 10) {
        cancellables.removeAll()
        guard interval > 0 else { return }
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.scan() }
            }
            .store(in: &cancellables)
    }

    func scan() async {
        isLoading = true

        let pinned = pinnedSessionIds
        let dir = projectsDir

        let result = await Task.detached(priority: .userInitiated) {
            ScanHelper.scanProjects(at: dir, pinned: pinned)
        }.value

        projects = result
        isLoading = false
    }

    // MARK: - Pin

    func togglePin(sessionId: String) {
        var pinned = pinnedSessionIds
        if pinned.contains(sessionId) {
            pinned.remove(sessionId)
        } else {
            pinned.insert(sessionId)
        }
        pinnedSessionIds = pinned

        for i in projects.indices {
            for j in projects[i].sessions.indices {
                if projects[i].sessions[j].id == sessionId {
                    projects[i].sessions[j].isPinned = pinned.contains(sessionId)
                }
            }
        }
    }

    // MARK: - Delete

    func deleteSession(sessionId: String, in project: Project) {
        let dir = projectsDir.appendingPathComponent(project.id)
        let jsonlFile = dir.appendingPathComponent("\(sessionId).jsonl")
        let relatedDir = dir.appendingPathComponent(sessionId)

        try? FileManager.default.removeItem(at: jsonlFile)
        if FileManager.default.fileExists(atPath: relatedDir.path) {
            try? FileManager.default.removeItem(at: relatedDir)
        }

        var pinned = pinnedSessionIds
        pinned.remove(sessionId)
        pinnedSessionIds = pinned

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
}
