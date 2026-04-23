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

            // 필드는 첫 라인에만 있지 않음 (permission-mode 라인엔 sessionId만 있고 cwd 없음)
            // 각 필드를 독립적으로, 처음 발견될 때까지 찾는다
            if sessionId == nil { sessionId = json["sessionId"] as? String }
            if cwd == nil { cwd = json["cwd"] as? String }
            if gitBranch == nil { gitBranch = json["gitBranch"] as? String }
            if version == nil { version = json["version"] as? String }

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

        // 전체 파일 읽기 (메시지 카운트 + custom-title + 토큰 + 시간)
        handle.seek(toFileOffset: 0)
        let fullData = handle.readDataToEndOfFile()

        var messageCount = 0
        var totalInputTokens = 0
        var totalOutputTokens = 0
        var minTimestamp: Date?
        var maxTimestamp: Date?

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let fullContent = String(data: fullData, encoding: .utf8) {
            for line in fullContent.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let ld = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: ld) as? [String: Any]
                else { continue }

                // cwd/gitBranch/version — 첫 64KB에서 못 찾은 경우 전체 스캔에서 보강
                if cwd == nil { cwd = json["cwd"] as? String }
                if gitBranch == nil { gitBranch = json["gitBranch"] as? String }
                if version == nil { version = json["version"] as? String }

                // 메시지 카운트
                if json["message"] is [String: Any], line.contains("\"role\"") {
                    messageCount += 1
                }

                // custom-title (마지막이 최종)
                if let type = json["type"] as? String,
                   type == "custom-title",
                   let ct = json["customTitle"] as? String,
                   !ct.isEmpty {
                    customTitle = ct
                }

                // 타임스탬프 min/max
                if let ts = json["timestamp"] as? String,
                   let date = isoFormatter.date(from: ts) {
                    if minTimestamp == nil || date < minTimestamp! { minTimestamp = date }
                    if maxTimestamp == nil || date > maxTimestamp! { maxTimestamp = date }
                }

                // 토큰 합산 (assistant 메시지만)
                if let type = json["type"] as? String, type == "assistant",
                   let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    totalInputTokens += (usage["input_tokens"] as? Int ?? 0)
                        + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                        + (usage["cache_read_input_tokens"] as? Int ?? 0)
                    totalOutputTokens += usage["output_tokens"] as? Int ?? 0
                }
            }
        }

        let duration: TimeInterval?
        if let min = minTimestamp, let max = maxTimestamp {
            duration = max.timeIntervalSince(min)
        } else {
            duration = nil
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
            duration: duration,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
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

}
