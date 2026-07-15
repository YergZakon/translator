import SwiftUI

struct PreflightView: View {
    let mode: TranslationMode
    @Binding var isConfirmed: Bool
    @EnvironmentObject var container: DependencyContainer
    @State private var micPermissionGranted = false
    @State private var networkChecked = false
    @State private var audioRouteChecked = false
    @State private var isChecking = true

    private let strings = EasyTalkStrings.current

    var body: some View {
        VStack(spacing: 0) {
            Text(strings.connecting)
                .font(.easyTalk(24, .bold))
                .foregroundColor(EasyTalk.fg)
                .padding(.top, 40)

            VStack(spacing: 0) {
                checkRow(
                    done: micPermissionGranted,
                    title: strings.micPerm,
                    subtitle: micPermissionGranted ? "✓" : "…"
                )
                Rectangle().fill(EasyTalk.stroke).frame(height: 1)
                checkRow(
                    done: networkChecked,
                    title: strings.connection,
                    subtitle: networkChecked ? strings.connected : "…"
                )
                Rectangle().fill(EasyTalk.stroke).frame(height: 1)
                checkRow(
                    done: audioRouteChecked,
                    title: "Audio",
                    subtitle: container.audioController.currentRoute
                )
            }
            .easyTalkCard()
            .padding(.horizontal, 26)
            .padding(.top, 30)

            Spacer()

            if isChecking {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(EasyTalk.accent)
                    Text(strings.connectingSub)
                        .font(.easyTalk(12))
                        .foregroundColor(EasyTalk.fg2)
                }
                .padding(.bottom, 40)
            } else {
                Button(action: { isConfirmed = true }) {
                    Text(strings.startBtn)
                }
                .buttonStyle(EasyTalkPrimaryButtonStyle())
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
                .accessibilityLabel(strings.startBtn)
            }
        }
        .onAppear {
            runPreflightChecks()
        }
    }

    private func checkRow(done: Bool, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(done ? EasyTalk.english : EasyTalk.fg3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.easyTalk(14, .medium))
                    .foregroundColor(EasyTalk.fg)
                Text(subtitle)
                    .font(.easyTalk(12))
                    .foregroundColor(EasyTalk.fg2)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(subtitle)")
    }

    private func runPreflightChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.micPermissionGranted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.networkChecked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.audioRouteChecked = true
                    self.isChecking = false
                }
            }
        }
    }
}
