import Foundation

struct Session: Identifiable, Hashable {
    let id: String
    let projectPath: String
    let title: String
    let description: String?
    let lastModified: Date
    let gitBranch: String?
    let claudeVersion: String?
    let messageCount: Int
    let duration: TimeInterval?
    let totalInputTokens: Int
    let totalOutputTokens: Int
    var isPinned: Bool

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }

    var formattedDuration: String? {
        guard let d = duration, d > 0 else { return nil }
        let minutes = Int(d) / 60
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return mins > 0 ? "\(hours)시간 \(mins)분" : "\(hours)시간"
        }
        return minutes > 0 ? "\(mins)분" : "\(Int(d))초"
    }

    var formattedTokens: String? {
        let total = totalInputTokens + totalOutputTokens
        guard total > 0 else { return nil }
        return formatTokenCount(total)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK tokens", Double(count) / 1_000)
        }
        return "\(count) tokens"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}
