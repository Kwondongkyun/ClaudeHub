import Foundation

enum SessionParser {
    /// 시스템 태그+내용 제거 패턴
    private static let tagPatterns: [String] = [
        "<local-command-caveat>[\\s\\S]*?</local-command-caveat>",
        "<local-command-stdout>[\\s\\S]*?</local-command-stdout>",
        "<system-reminder>[\\s\\S]*?</system-reminder>",
        "<command-name>[\\s\\S]*?</command-name>",
        "<command-message>[\\s\\S]*?</command-message>",
        "<command-args>[\\s\\S]*?</command-args>",
        "<[^>]+>"  // 남은 단독 태그
    ]

    /// 의미없는 시스템 프리픽스들
    private static let junkPrefixes = [
        "Caveat:",
        "The messages below were generated",
        "The user opened the file",
        "The user ",
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
        var customTitle: String?
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

            // custom-title: /rename으로 지정한 제목 (여러 번 rename 시 마지막이 최종)
            if let type = json["type"] as? String,
               type == "custom-title",
               let ct = json["customTitle"] as? String,
               !ct.isEmpty {
                customTitle = ct
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

        // sessionId가 없으면 실제 세션이 아님 (file-history-snapshot 등)
        guard let fileSessionId = sessionId else { return nil }

        // 전체 파일 읽기 (메시지 카운트 + custom-title 검색)
        handle.seek(toFileOffset: 0)
        let fullData = handle.readDataToEndOfFile()
        let messageCount = countOccurrences(of: "\"role\"", in: fullData)

        // custom-title이 첫 64KB에 없었으면 전체에서 마지막 것 검색
        if customTitle == nil, let fullContent = String(data: fullData, encoding: .utf8) {
            for line in fullContent.components(separatedBy: "\n").reversed() {
                guard !line.isEmpty,
                      let ld = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                      let type = json["type"] as? String,
                      type == "custom-title",
                      let ct = json["customTitle"] as? String,
                      !ct.isEmpty
                else { continue }
                customTitle = ct
                break
            }
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modified = attributes?[.modificationDate] as? Date ?? Date.distantPast

        // 제목 우선순위: customTitle > firstUserMessage > 날짜 폴백
        let title: String
        let description: String?
        if let ct = customTitle {
            title = ct
            description = firstUserMessage.map { String($0.prefix(120)) }
        } else if let msg = firstUserMessage {
            let shortTitle = extractTitle(from: msg)
            if shortTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let df = DateFormatter()
                df.locale = Locale(identifier: "ko_KR")
                df.dateFormat = "M월 d일 HH:mm 세션"
                title = df.string(from: modified)
                description = nil
            } else {
                title = shortTitle
                description = msg.count > shortTitle.count + 5 ? String(msg.prefix(120)) : nil
            }
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
            messageCount: messageCount,
            isPinned: isPinned
        )
    }

    /// 첫 문장 또는 40자까지를 제목으로 추출
    private static func extractTitle(from text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text

        let sentenceEnders: [Character] = [".", "?", "!", "。"]
        for (i, ch) in firstLine.enumerated() {
            if sentenceEnders.contains(ch) && i < 50 {
                return String(firstLine.prefix(i + 1))
            }
        }

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

        // 슬래시 명령어 필터 (/config, /exit, /rename 등)
        if result.hasPrefix("/"), !result.contains(" ") || result.count < 20 {
            return ""
        }

        return result
    }

    /// Data에서 특정 문자열 패턴 출현 횟수 카운트
    private static func countOccurrences(of pattern: String, in data: Data) -> Int {
        guard let patternData = pattern.data(using: .utf8) else { return 0 }
        var count = 0
        var searchStart = data.startIndex
        while let range = data.range(of: patternData, in: searchStart..<data.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}
