import SwiftUI

struct MainView: View {
    @StateObject private var scanner = SessionScanner()
    @StateObject private var settings = AppSettings.shared
    @State private var selectedProjectId: String?
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var deleteTargetSessionId: String?
    @State private var didInitialScan = false
    @State private var hoveredSessionId: String?
    @State private var hoveredProjectId: String?

    private var selectedProject: Project? {
        filteredProjects.first { $0.id == selectedProjectId }
    }

    private var filteredProjects: [Project] {
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

    private var pinnedSessions: [Session] {
        displaySessions.filter { $0.isPinned }
    }

    private var unpinnedSessions: [Session] {
        displaySessions.filter { !$0.isPinned }
    }

    private var totalSessionCount: Int {
        scanner.projects.reduce(0) { $0 + $1.sessionCount }
    }

    private var totalPinnedCount: Int {
        scanner.projects.reduce(0) { $0 + $1.pinnedCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                settingsPage
            } else {
                mainPage
            }
        }
        .frame(width: 640, height: 520)
        .onAppear {
            guard !didInitialScan else { return }
            didInitialScan = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task {
                    await scanner.scan()
                    if selectedProjectId == nil {
                        selectedProjectId = scanner.projects.first?.id
                    }
                    if settings.refreshInterval > 0 {
                        scanner.startAutoRefresh(interval: settings.refreshInterval)
                    }
                }
            }
        }
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 190)

                Divider()

                VStack(spacing: 0) {
                    if let project = selectedProject {
                        projectHeader(project)
                        Divider()
                    }
                    sessionList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)

            Text("ClaudeHub")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                TextField("검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 120)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.textBackgroundColor).opacity(0.5))
            )

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredProjects) { project in
                    sidebarRow(project: project)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(.windowBackgroundColor).opacity(0.3))
    }

    private func sidebarRow(project: Project) -> some View {
        let isSelected = selectedProjectId == project.id
        let isHovered = hoveredProjectId == project.id && !isSelected

        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Text(smartPath(project.fullPath))
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .gray)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 4)

            Text("\(project.sessionCount)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(minWidth: 20)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color(.separatorColor).opacity(0.15))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor : isHovered ? Color(.separatorColor).opacity(0.1) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProjectId = project.id
        }
        .onHover { h in
            hoveredProjectId = h ? project.id : nil
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Project Header (우측 상단)

    private func projectHeader(_ project: Project) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(shortenHomePath(project.fullPath))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()

            Text("\(project.sessionCount)개 세션")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor).opacity(0.3))
    }

    // MARK: - Session List

    private var sessionList: some View {
        Group {
            if scanner.isLoading && scanner.projects.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("불러오는 중...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displaySessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text(selectedProjectId == nil ? "프로젝트를 선택하세요" : "세션 없음")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 핀된 세션 섹션
                        if !pinnedSessions.isEmpty {
                            sectionHeader(title: "고정됨", icon: "pin.fill", color: .orange)
                            ForEach(pinnedSessions) { session in
                                sessionRow(session: session)
                            }
                        }

                        // 일반 세션 섹션
                        if !unpinnedSessions.isEmpty {
                            if !pinnedSessions.isEmpty {
                                sectionHeader(title: "최근", icon: "clock", color: .secondary)
                            }
                            ForEach(unpinnedSessions) { session in
                                sessionRow(session: session)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Session Row

    private func sessionRow(session: Session) -> some View {
        Group {
            if deleteTargetSessionId == session.id {
                deleteConfirmRow(session: session)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            } else {
                sessionCard(session: session)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
    }

    private func sessionCard(session: Session) -> some View {
        let isHovered = hoveredSessionId == session.id

        return HStack(spacing: 10) {
            // 좌측 컬러 바
            RoundedRectangle(cornerRadius: 1.5)
                .fill(session.isPinned ? Color.orange : Color.accentColor.opacity(0.4))
                .frame(width: 3)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 5) {
                // 1줄: 제목 + 시간
                HStack(alignment: .top) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(session.relativeTime)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // 2줄: 설명
                Text(session.description ?? "설명 없음")
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundStyle(session.description != nil ? .secondary : .quaternary)

                // 3줄: 브랜치
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8))
                    Text(session.gitBranch ?? "브랜치 없음")
                        .font(.system(size: 10))
                }
                .foregroundStyle(session.gitBranch != nil ? .tertiary : .quaternary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.accentColor.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredSessionId = hovering ? session.id : nil
        }
        .onTapGesture {
            TerminalLauncher.resumeSession(
                sessionId: session.id,
                projectPath: session.projectPath.isEmpty ? (selectedProject?.fullPath ?? "") : session.projectPath,
                terminal: settings.terminal
            )
        }
        .contextMenu {
            Button {
                scanner.togglePin(sessionId: session.id)
            } label: {
                Label(
                    session.isPinned ? "핀 해제" : "핀 고정",
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            } label: {
                Label("세션 ID 복사", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                deleteTargetSessionId = session.id
            } label: {
                Label("세션 삭제", systemImage: "trash")
            }
        }
    }

    // MARK: - Delete Confirm

    private func deleteConfirmRow(session: Session) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("삭제하시겠습니까?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                Text(session.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                deleteTargetSessionId = nil
            } label: {
                Text("취소")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            Button {
                if let project = selectedProject {
                    scanner.deleteSession(sessionId: session.id, in: project)
                }
                deleteTargetSessionId = nil
            } label: {
                Text("삭제")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(totalSessionCount) 세션")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)

            if totalPinnedCount > 0 {
                Text("·")
                    .foregroundStyle(.quaternary)
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.orange.opacity(0.7))
                Text("\(totalPinnedCount)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if scanner.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Spacer()

            Button {
                Task { await scanner.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(scanner.isLoading)
            .help("새로고침")

            Divider().frame(height: 12)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("종료")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    // MARK: - Settings Page

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    showSettings = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("뒤로")
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("설정")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider()

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
            .padding(.horizontal, 16)

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
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    // MARK: - Helpers

    /// 사이드바용: 마지막 2세그먼트만 표시 (~/Desktop/Claude-Code)
    private func smartPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var display = path
        if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        let segments = display.components(separatedBy: "/").filter { !$0.isEmpty }
        if segments.count <= 3 {
            return display
        }
        // ~/...마지막2개
        return "~/\(segments.suffix(2).joined(separator: "/"))"
    }

    /// 프로젝트 헤더용: 전체 경로 (~로 시작)
    private func shortenHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
