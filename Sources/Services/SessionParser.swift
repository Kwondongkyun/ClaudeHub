import Foundation

enum SessionParser {
    static func parse(fileURL: URL, isPinned: Bool) -> Session? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { handle.closeFile() }

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

            if sessionId == nil {
                sessionId = json["sessionId"] as? String
                cwd = json["cwd"] as? String
                gitBranch = json["gitBranch"] as? String
                version = json["version"] as? String
            }

            if firstUserMessage == nil,
               let message = json["message"] as? [String: Any],
               let role = message["role"] as? String,
               role == "user" {
                // content가 배열인 경우
                if let contentArray = message["content"] as? [[String: Any]] {
                    for block in contentArray {
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
                // content가 문자열인 경우
                else if let contentStr = message["content"] as? String {
                    let cleaned = contentStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        firstUserMessage = String(cleaned.prefix(80))
                    }
                }
            }

            if sessionId != nil && firstUserMessage != nil { break }
        }

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
