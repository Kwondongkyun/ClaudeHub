import SwiftUI

struct MainView: View {
    @StateObject private var scanner = SessionScanner()
    @StateObject private var settings = AppSettings.shared
    @State private var selectedProjectId: String?
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var deleteTargetSessionId: String?
    @State private var didInitialScan = false

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
        .frame(width: 560, height: 480)
        .onAppear {
            guard !didInitialScan else { return }
            didInitialScan = true
            // 패널이 완전히 열린 후 스캔 시작 (딜레이 필수)
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
            // Header
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

            Divider()

            // Content: Sidebar + Sessions
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 168)

                Divider()

                sessionList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredProjects) { project in
                    sidebarRow(project: project)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func sidebarRow(project: Project) -> some View {
        let isSelected = selectedProjectId == project.id
        let pathText = shortenHomePath(project.fullPath)

        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Text(pathText)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .gray)
                    .lineLimit(1)
                    .truncationMode(.head)

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
                .fill(isSelected ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProjectId = project.id
        }
        .padding(.horizontal, 4)
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
                    LazyVStack(spacing: 4) {
                        ForEach(displaySessions) { session in
                            if deleteTargetSessionId == session.id {
                                deleteConfirmRow(session: session)
                            } else {
                                sessionCard(session: session)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    // MARK: - Session Card

    private func sessionCard(session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .fill(Color(.windowBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            TerminalLauncher.resumeSession(
                sessionId: session.id,
                projectPath: selectedProject?.fullPath ?? session.projectPath,
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
                Text("세션 삭제")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                Text("'\(session.title)'")
                    .font(.system(size: 11))
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
                    .padding(.vertical, 5)
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.08))
        )
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

    private func shortenHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
