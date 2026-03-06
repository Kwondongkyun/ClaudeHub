import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("설정")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

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

            Spacer()
        }
        .padding(16)
        .frame(width: 320, height: 200)
    }
}
