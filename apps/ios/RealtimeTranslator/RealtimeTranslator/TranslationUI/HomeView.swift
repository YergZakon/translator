import SwiftUI

struct HomeView: View {
    @EnvironmentObject var container: DependencyContainer
    @StateObject private var sessionStore = TranslationSessionStore()
    @State private var showDiagnostics = false
    // One-way is the only mode the session store supports today (P0);
    // dialogue stays selectable per the design and fails gracefully in-store.
    @State private var selectedMode: TranslationMode = .oneWayRuToEn

    private let strings = EasyTalkStrings.current

    var body: some View {
        NavigationView {
            ZStack {
                EasyTalkBackground()

                // Scrollable so large Dynamic Type sizes never clip; at
                // regular sizes minHeight keeps the start button pinned low.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            header
                                .padding(.top, 6)

                            EasyTalkSectionLabel(strings.modeTitle)
                                .padding(.top, 24)
                                .padding(.bottom, 10)
                            modeCards

                            EasyTalkSectionLabel(strings.langTitle)
                                .padding(.top, 24)
                                .padding(.bottom, 10)
                            languagesCard

                            Spacer(minLength: 16)

                            startButton
                        }
                        .padding(.horizontal, 26)
                        .padding(.bottom, 26)
                        .frame(minHeight: proxy.size.height)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
                    .environmentObject(container)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(strings.hello)
                    .font(.easyTalk(14))
                    .foregroundColor(EasyTalk.fg2)
                Text(strings.homeTitle)
                    .font(.easyTalk(26, .bold))
                    .foregroundColor(EasyTalk.fg)
            }
            Spacer()
            Button(action: { showDiagnostics = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(EasyTalk.fg)
                    .frame(width: 42, height: 42)
                    .easyTalkCard(cornerRadius: 13)
            }
            .accessibilityLabel(strings.setTitle)
        }
    }

    private var modeCards: some View {
        VStack(spacing: 11) {
            modeCard(
                mode: .dialogue,
                icon: "bubble.left.and.bubble.right",
                title: strings.modeDialogue,
                subtitle: strings.modeDialogueSub
            )
            modeCard(
                mode: .oneWayRuToEn,
                icon: "arrow.right",
                title: strings.modeMono,
                subtitle: strings.modeMonoSub
            )
        }
    }

    private func modeCard(mode: TranslationMode, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = selectedMode == mode
        return Button(action: { selectedMode = mode }) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(EasyTalk.card2)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(EasyTalk.accent)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.easyTalk(16, .semibold))
                        .foregroundColor(EasyTalk.fg)
                    Text(subtitle)
                        .font(.easyTalk(12.5))
                        .foregroundColor(EasyTalk.fg2)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .stroke(isSelected ? EasyTalk.accent : EasyTalk.stroke, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(EasyTalk.accent)
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(15)
            .background(EasyTalk.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? EasyTalk.accent : EasyTalk.stroke, lineWidth: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(EasyTalk.accent.opacity(isSelected ? 0.15 : 0), lineWidth: 4)
            )
        }
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var languagesCard: some View {
        HStack(spacing: 11) {
            VStack(spacing: 2) {
                Text("RU")
                    .font(.easyTalk(22, .bold))
                    .foregroundColor(EasyTalk.russian)
                Text("Русский")
                    .font(.easyTalk(12, .medium))
                    .foregroundColor(EasyTalk.fg2)
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(EasyTalk.fg)
                .frame(width: 40, height: 40)
                .background(EasyTalk.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EasyTalk.stroke, lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("EN")
                    .font(.easyTalk(22, .bold))
                    .foregroundColor(EasyTalk.english)
                Text("English")
                    .font(.easyTalk(12, .medium))
                    .foregroundColor(EasyTalk.fg2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .easyTalkCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(strings.langTitle): Русский, English")
    }

    private var startButton: some View {
        NavigationLink(destination: LiveView(sessionStore: sessionStore, mode: selectedMode)) {
            HStack(spacing: 9) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(strings.startBtn)
                    .font(.easyTalk(17, .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(EasyTalk.brandGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: EasyTalk.gradientEnd.opacity(0.45), radius: 16, x: 0, y: 12)
        }
        .accessibilityLabel(strings.startBtn)
    }
}
