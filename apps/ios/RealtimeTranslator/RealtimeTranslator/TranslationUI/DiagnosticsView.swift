import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.presentationMode) var presentationMode

    private let strings = EasyTalkStrings.current

    var body: some View {
        ZStack {
            EasyTalkBackground()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 8)

                    EasyTalkSectionLabel(strings.connection)
                        .padding(.top, 22)
                        .padding(.bottom, 9)
                    connectionCard

                    EasyTalkSectionLabel(strings.preferences)
                        .padding(.top, 20)
                        .padding(.bottom, 9)
                    preferencesCard

                    EasyTalkSectionLabel("WebRTC")
                        .padding(.top, 20)
                        .padding(.bottom, 9)
                    logsCard

                    EasyTalkSectionLabel(strings.about)
                        .padding(.top, 20)
                        .padding(.bottom, 9)
                    aboutCard

                    Text("EasyTalk · SwiftUI · WebRTC · OpenAI Realtime")
                        .font(.easyTalk(11, .medium))
                        .foregroundColor(EasyTalk.fg3)
                        .padding(.top, 22)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(EasyTalk.fg)
                    .frame(width: 38, height: 38)
                    .easyTalkCard(cornerRadius: 12)
            }
            .accessibilityLabel("Back")
            Text(strings.setTitle)
                .font(.easyTalk(24, .bold))
                .foregroundColor(EasyTalk.fg)
            Spacer()
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 0) {
            row(strings.connection) {
                Text(container.environment.rawValue.uppercased())
                    .font(.easyTalk(13, .semibold))
                    .foregroundColor(EasyTalk.accent)
            }
            divider
            row("Endpoint") {
                Text(container.environment.baseURL.absoluteString)
                    .font(.easyTalk(11, .medium, design: .monospaced))
                    .foregroundColor(EasyTalk.fg2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            divider
            row(strings.model) {
                Text("gpt-realtime")
                    .font(.easyTalk(13, .semibold))
                    .foregroundColor(EasyTalk.fg2)
            }
        }
        .easyTalkCard()
    }

    // Haptics/autoplay behavior is outside the UX-02 visual scope, so these
    // preferences are announced but explicitly not offered as working toggles.
    private var preferencesCard: some View {
        VStack(spacing: 0) {
            plannedPreferenceRow(strings.haptics)
            divider
            plannedPreferenceRow(strings.autoplay)
        }
        .easyTalkCard()
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if container.diagnosticsStore.logs.isEmpty {
                Text("—")
                    .font(.easyTalk(13))
                    .foregroundColor(EasyTalk.fg3)
            } else {
                ForEach(container.diagnosticsStore.logs, id: \.self) { log in
                    Text(log)
                        .font(.easyTalk(11, design: .monospaced))
                        .foregroundColor(EasyTalk.fg2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .easyTalkCard()
    }

    private var aboutCard: some View {
        row(strings.version) {
            Text(appVersion)
                .font(.easyTalk(13, .semibold))
                .foregroundColor(EasyTalk.fg2)
        }
        .easyTalkCard()
    }

    private var divider: some View {
        Rectangle().fill(EasyTalk.stroke).frame(height: 1)
    }

    private func row(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.easyTalk(14, .medium))
                .foregroundColor(EasyTalk.fg)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private func plannedPreferenceRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.easyTalk(14, .medium))
                .foregroundColor(EasyTalk.fg3)
            Spacer(minLength: 12)
            Text(strings.comingSoon)
                .font(.easyTalk(11, .semibold))
                .foregroundColor(EasyTalk.fg3)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(EasyTalk.card2)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(EasyTalk.stroke, lineWidth: 1))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(strings.comingSoon)")
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
