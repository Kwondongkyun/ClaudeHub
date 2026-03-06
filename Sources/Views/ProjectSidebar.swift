import SwiftUI

struct ProjectSidebar: View {
    let projects: [Project]
    @Binding var selectedProjectId: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(projects) { project in
                    ProjectRow(
                        project: project,
                        isSelected: selectedProjectId == project.id
                    )
                    .onTapGesture {
                        selectedProjectId = project.id
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

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
                .fill(
                    isSelected
                        ? Color.accentColor
                        : (isHovered ? Color(.unemphasizedSelectedContentBackgroundColor).opacity(0.5) : .clear)
                )
        )
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}
