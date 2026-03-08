import Foundation

enum SessionParser {
    /// 시스템 태그+내용 제거 패턴 (예: <local-command-caveat>...</local-command-caveat>)
    private static let tagPatterns: [String] = [
        "<local-command-caveat>[\\s\\S]*?</local-command-caveat>",
        "<system-reminder>[\\s\\S]*?</system-reminder>",
        "<[^>]+>"  // 남은 단독 태그
    ]

    /// 의미없는 시스템 프리픽스들
    private static let junkPrefixes = [
        "Caveat:",
        "The messages below were generated",
    ]

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
                if let contentArray = message["content"] as? [[String: Any]] {
                    for block in contentArray {
                        if let type = block["type"] as? String,
                           type == "text",
                           let text = block["text"] as? String {
                            let cleaned = cleanMessage(text)
                            if !cleaned.isEmpty {
                                firstUserMessage = cleaned
                                break
                            }
                        }
                    }
                } else if let contentStr = message["content"] as? String {
                    let cleaned = cleanMessage(contentStr)
                    if !cleaned.isEmpty {
                        firstUserMessage = cleaned
                    }
                }
            }

            if sessionId != nil && firstUserMessage != nil { break }
        }

        let fileSessionId = sessionId ?? fileURL.deletingPathExtension().lastPathComponent

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modified = attributes?[.modificationDate] as? Date ?? Date.distantPast

        // 제목과 설명 분리
        let title: String
        let description: String?
        if let msg = firstUserMessage {
            let shortTitle = extractTitle(from: msg)
            title = shortTitle
            // 제목과 전체 메시지가 같으면 설명 생략
            description = msg.count > shortTitle.count + 5 ? String(msg.prefix(120)) : nil
        } else {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ko_KR")
            df.dateFormat = "M월 d일 HH:mm 세션"
            title = df.string(from: modified)
            description = nil
        }

        return Session(
            id: fileSessionId,
            projectPath: cwd ?? "",
            title: title,
            description: description,
            lastModified: modified,
            gitBranch: gitBranch,
            claudeVersion: version,
            isPinned: isPinned
        )
    }

    /// 첫 문장 또는 40자까지를 제목으로 추출
    private static func extractTitle(from text: String) -> String {
        // 줄바꿈 기준 첫 줄
        let firstLine = text.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text

        // 마침표/물음표/느낌표로 끝나는 첫 문장 (50자 이내)
        let sentenceEnders: [Character] = [".", "?", "!", "。"]
        for (i, ch) in firstLine.enumerated() {
            if sentenceEnders.contains(ch) && i < 50 {
                return String(firstLine.prefix(i + 1))
            }
        }

        // 문장 구분 없으면 40자 자르기
        if firstLine.count > 40 {
            return String(firstLine.prefix(40)) + "..."
        }
        return firstLine
    }

    private static func cleanMessage(_ text: String) -> String {
        var result = text

        // 시스템 태그+내용 제거
        for pattern in tagPatterns {
            result = result.replacingOccurrences(
                of: pattern, with: "", options: .regularExpression
            )
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 시스템 프리픽스로 시작하면 빈 문자열 반환
        for prefix in junkPrefixes {
            if result.hasPrefix(prefix) { return "" }
        }

        return result
    }
}
