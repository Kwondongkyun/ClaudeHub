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
