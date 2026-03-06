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
