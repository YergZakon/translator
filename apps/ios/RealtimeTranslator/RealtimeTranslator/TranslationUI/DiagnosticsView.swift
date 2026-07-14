import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("easyTalkHapticsEnabled") private var hapticsEnabled = true
    @AppStorage("easyTalkAutoplayEnabled") private var autoplayEnabled = true

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
                        .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(EasyTalk.fg)
            Spacer()
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 0) {
            row(strings.connection) {
                Text(container.environment.rawValue.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(EasyTalk.accent)
            }
            divider
            row("Endpoint") {
                Text(container.environment.baseURL.absoluteString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(EasyTalk.fg2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            divider
            row(strings.model) {
                Text("gpt-realtime")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(EasyTalk.fg2)
            }
        }
        .easyTalkCard()
    }

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            toggleRow(strings.haptics, isOn: $hapticsEnabled)
            divider
            toggleRow(strings.autoplay, isOn: $autoplayEnabled)
        }
        .easyTalkCard()
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if container.diagnosticsStore.logs.isEmpty {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundColor(EasyTalk.fg3)
            } else {
                ForEach(container.diagnosticsStore.logs, id: \.self) { log in
                    Text(log)
                        .font(.system(size: 11, design: .monospaced))
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
                .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(EasyTalk.fg)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(EasyTalk.fg)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(EasyTalk.english)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
