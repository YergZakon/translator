import SwiftUI

struct OnboardingView: View {
    @Binding var isOnboardingCompleted: Bool
    @State private var micPermission: PermissionState = .idle
    @State private var speechPermission: PermissionState = .idle
    @State private var isFloating = false

    private let strings = EasyTalkStrings.current

    enum PermissionState {
        case idle, granted, denied
    }

    var body: some View {
        ZStack {
            EasyTalkBackground()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    benefits
                        .padding(.top, 22)

                    EasyTalkSectionLabel(strings.permTitle)
                        .padding(.top, 22)
                        .padding(.bottom, 9)
                    permissionCards

                    if micPermission == .denied {
                        micDeniedWarning
                            .padding(.top, 12)
                    }

                    continueButton
                        .padding(.top, 26)
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .onAppear { isFloating = true }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(EasyTalk.brandGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: EasyTalk.gradientEnd.opacity(0.5), radius: 17, x: 0, y: 14)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(y: isFloating ? -8 : 0)
            .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: isFloating)
            .accessibilityHidden(true)

            Text("EasyTalk")
                .font(.easyTalk(27, .bold))
                .foregroundColor(EasyTalk.fg)
                .padding(.top, 18)

            Text(strings.onbTitle)
                .font(.easyTalk(17, .semibold))
                .foregroundColor(EasyTalk.fg)
                .padding(.top, 12)

            Text(strings.onbSub)
                .font(.easyTalk(14))
                .foregroundColor(EasyTalk.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(spacing: 9) {
            benefitRow(icon: "waveform", title: strings.b1t, subtitle: strings.b1s)
            benefitRow(icon: "bolt.fill", title: strings.b2t, subtitle: strings.b2s)
            benefitRow(icon: "shield", title: strings.b3t, subtitle: strings.b3s)
        }
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(EasyTalk.card2)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(EasyTalk.accent)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.easyTalk(14, .semibold))
                    .foregroundColor(EasyTalk.fg)
                Text(subtitle)
                    .font(.easyTalk(12.5))
                    .foregroundColor(EasyTalk.fg2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .easyTalkCard()
    }

    private var permissionCards: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(EasyTalk.danger.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(EasyTalk.danger)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(strings.micPerm)
                            .font(.easyTalk(14, .semibold))
                            .foregroundColor(EasyTalk.fg)
                        Text(strings.critical)
                            .font(.easyTalk(9, .bold))
                            .foregroundColor(EasyTalk.danger)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(EasyTalk.danger.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Text(strings.micPermSub)
                        .font(.easyTalk(12))
                        .foregroundColor(EasyTalk.fg2)
                }
                Spacer(minLength: 8)
                permissionButton(state: micPermission, action: requestMicPermission)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 15)
            .easyTalkCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(strings.micPerm). \(strings.micPermSub)")

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(EasyTalk.card2)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(EasyTalk.accent)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(strings.speechPerm)
                        .font(.easyTalk(14, .semibold))
                        .foregroundColor(EasyTalk.fg)
                    Text(strings.speechPermSub)
                        .font(.easyTalk(12))
                        .foregroundColor(EasyTalk.fg2)
                }
                Spacer(minLength: 8)
                permissionButton(state: speechPermission, action: requestSpeechPermission)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 15)
            .easyTalkCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(strings.speechPerm). \(strings.speechPermSub)")
        }
    }

    private func permissionButton(state: PermissionState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if state == .granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text("OK")
                        .font(.easyTalk(12, .bold))
                }
            }
            .foregroundColor(state == .granted ? EasyTalk.english : EasyTalk.fg)
            .frame(width: 44, height: 32)
            .background(state == .granted ? EasyTalk.english.opacity(0.15) : EasyTalk.card2)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var micDeniedWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(EasyTalk.danger)
                .padding(.top, 1)
            Text(strings.micError)
                .font(.easyTalk(12.5, .medium))
                .foregroundColor(EasyTalk.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(EasyTalk.danger.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EasyTalk.danger.opacity(0.3), lineWidth: 1)
        )
    }

    private var continueButton: some View {
        Button(action: finishOnboarding) {
            Text(strings.continueLabel)
        }
        .buttonStyle(EasyTalkPrimaryButtonStyle(isEnabled: micPermission == .granted))
        .disabled(micPermission != .granted)
        .accessibilityLabel(strings.continueLabel)
    }

    // Permission flow stays simulated at the prototype level; real
    // AVAudioApplication/SFSpeechRecognizer requests are a separate task.
    private func requestMicPermission() {
        micPermission = micPermission == .granted ? .denied : .granted
    }

    private func requestSpeechPermission() {
        speechPermission = speechPermission == .granted ? .idle : .granted
    }

    private func finishOnboarding() {
        guard micPermission == .granted else { return }
        withAnimation {
            isOnboardingCompleted = true
        }
    }
}
