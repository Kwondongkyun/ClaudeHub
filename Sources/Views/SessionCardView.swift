import SwiftUI

struct SessionCardView: View {
    let session: Session
    let onResume: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onCopyId: () -> Void

    @State private var isHovered = false

    var body: some View {
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
                .fill(isHovered
                    ? Color(.selectedContentBackgroundColor).opacity(0.3)
                    : Color(.windowBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 0.5)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { onResume() }
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(
                    session.isPinned ? "핀 해제" : "핀 고정",
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }

            Button {
                onCopyId()
            } label: {
                Label("세션 ID 복사", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("세션 삭제", systemImage: "trash")
            }
        }
    }
}
