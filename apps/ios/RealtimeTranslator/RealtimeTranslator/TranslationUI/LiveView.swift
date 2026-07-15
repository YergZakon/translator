import SwiftUI

// Which Live controls exist per translation mode. One-way has a single
// RU→EN leg, so exposing a side switch would only fake speaker state.
enum LiveControlsPolicy {
    static func showsSideSwitch(for mode: TranslationMode) -> Bool {
        mode == .dialogue
    }
}

struct LiveView: View {
    @ObservedObject var sessionStore: TranslationSessionStore
    let mode: TranslationMode
    @Environment(\.presentationMode) var presentationMode
    @State private var isPreflightPassed = false
    @State private var showFeedback = false
    @State private var sessionDuration: TimeInterval = 0
    @State private var timerSubscription: Timer? = nil
    @State private var finishedSegments: [TranscriptSegment] = []
    @State private var isAnimating = false

    private let strings = EasyTalkStrings.current

    var body: some View {
        ZStack {
            EasyTalkBackground()

            if !isPreflightPassed {
                PreflightView(mode: mode, isConfirmed: $isPreflightPassed)
            } else {
                VStack(spacing: 0) {
                    statusStrip
                        .padding(.horizontal, 22)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    content

                    controlsBar
                }
                .onAppear {
                    isAnimating = true
                    startLiveSession()
                }
                .onDisappear {
                    cleanupTimers()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showFeedback, onDismiss: {
            presentationMode.wrappedValue.dismiss()
        }) {
            ResultView(duration: sessionDuration, segments: finishedSegments)
        }
    }

    // MARK: Status strip

    private var statusStrip: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: statusColor, radius: 4)
                Text(statusLabel)
                    .font(.easyTalk(13, .semibold))
                    .foregroundColor(EasyTalk.fg)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 13)
            .easyTalkCard(cornerRadius: 30)
            .accessibilityLabel(statusLabel)

            Spacer()

            if isDegraded {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .bold))
                    Text(strings.degraded)
                        .font(.easyTalk(12, .semibold))
                }
                .foregroundColor(EasyTalk.warning)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(EasyTalk.warning.opacity(0.16))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(EasyTalk.warning.opacity(0.4), lineWidth: 1))
                .accessibilityLabel(strings.degraded)
            }
        }
    }

    // MARK: Content area

    @ViewBuilder
    private var content: some View {
        if case .failed(_, let message) = sessionStore.state {
            errorState(message: message)
        } else if sessionStore.segments.isEmpty {
            heroState
        } else {
            transcript
        }
    }

    private var heroState: some View {
        VStack(spacing: 0) {
            Spacer()
            switch sessionStore.state {
            case .idle, .loadingConfig, .creatingSession, .connecting, .reconnecting:
                connectingHero
            case .active:
                if sessionStore.isMuted {
                    readyHero
                } else {
                    listeningHero
                }
            default:
                readyHero
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 34)
    }

    private var connectingHero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(EasyTalk.stroke, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(EasyTalk.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isAnimating)
            }
            .frame(width: 72, height: 72)
            .padding(.bottom, 26)
            .accessibilityHidden(true)

            Text(strings.connecting)
                .font(.easyTalk(19, .semibold))
                .foregroundColor(EasyTalk.fg)
            Text(strings.connectingSub)
                .font(.easyTalk(14))
                .foregroundColor(EasyTalk.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 8)
        }
    }

    private var readyHero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(activeColor.opacity(0.18))
                    .scaleEffect(isAnimating ? 2.0 : 0.75)
                    .opacity(isAnimating ? 0 : 0.6)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: isAnimating)
                Circle()
                    .fill(EasyTalk.brandGradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: EasyTalk.gradientEnd.opacity(0.5), radius: 15, x: 0, y: 12)
                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 118, height: 118)
            .padding(.bottom, 28)
            .accessibilityHidden(true)

            Text(strings.ready)
                .font(.easyTalk(20, .semibold))
                .foregroundColor(EasyTalk.fg)
            Text(strings.readySub)
                .font(.easyTalk(14))
                .foregroundColor(EasyTalk.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 8)
        }
    }

    private var listeningHero: some View {
        VStack(spacing: 26) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    WaveBar(color: activeColor, delay: Double(index) * 0.12)
                }
            }
            .frame(height: 80)
            .accessibilityHidden(true)

            Text(strings.listening)
                .font(.easyTalk(19, .semibold))
                .foregroundColor(EasyTalk.fg)
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(EasyTalk.danger)
                Text(message)
                    .font(.easyTalk(14, .medium))
                    .foregroundColor(EasyTalk.fg)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(EasyTalk.danger.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(EasyTalk.danger.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 34)
            Spacer()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 11) {
                    ForEach(sessionStore.segments) { segment in
                        bubble(for: segment)
                            .id(segment.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .onChange(of: sessionStore.segments.last?.text) { _, _ in
                if let last = sessionStore.segments.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(for segment: TranscriptSegment) -> some View {
        let isRussian = segment.side == .russianSpeaker
        let sideColor = EasyTalk.side(segment.side)
        return HStack {
            if !isRussian { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(isRussian ? "RU" : "EN")
                        .font(.easyTalk(10, .heavy))
                        .tracking(0.5)
                        .foregroundColor(sideColor)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(sideColor.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(segment.side.displayName)
                        .font(.easyTalk(10.5, .medium))
                        .foregroundColor(EasyTalk.fg3)
                }
                Text(segment.text)
                    .font(.easyTalk(16, .semibold))
                    .foregroundColor(EasyTalk.fg)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(isRussian ? EasyTalk.russianBubble : EasyTalk.englishBubble)
            .clipShape(
                .rect(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: isRussian ? 6 : 20,
                    bottomTrailingRadius: isRussian ? 20 : 6,
                    topTrailingRadius: 20
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: isRussian ? 6 : 20,
                    bottomTrailingRadius: isRussian ? 20 : 6,
                    topTrailingRadius: 20
                )
                .stroke(sideColor.opacity(0.25), lineWidth: 1)
            )
            if isRussian { Spacer(minLength: 60) }
        }
    }

    // MARK: Controls

    private var controlsBar: some View {
        HStack {
            Spacer()
            if LiveControlsPolicy.showsSideSwitch(for: mode) {
                controlColumn(label: strings.switchSpeaker) {
                    Button(action: switchSpeaker) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundColor(EasyTalk.fg)
                            .frame(width: 54, height: 54)
                            .background(EasyTalk.card2)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(EasyTalk.stroke, lineWidth: 1))
                    }
                    .accessibilityLabel(strings.switchSpeaker)
                }
                Spacer()
            }
            controlColumn(label: sessionStore.isMuted ? strings.unmute : strings.mute) {
                Button(action: { sessionStore.setMute(!sessionStore.isMuted) }) {
                    Image(systemName: sessionStore.isMuted ? "mic.slash" : "mic.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(sessionStore.isMuted ? EasyTalk.fg : .white)
                        .frame(width: 66, height: 66)
                        .background(
                            Group {
                                if sessionStore.isMuted {
                                    Circle().fill(EasyTalk.card2)
                                } else {
                                    Circle().fill(EasyTalk.brandGradient)
                                }
                            }
                        )
                        .overlay(
                            Circle().stroke(
                                sessionStore.isMuted ? EasyTalk.stroke : Color.clear,
                                lineWidth: 1
                            )
                        )
                        .shadow(
                            color: sessionStore.isMuted ? .clear : EasyTalk.gradientEnd.opacity(0.45),
                            radius: 13, x: 0, y: 10
                        )
                }
                .accessibilityLabel(sessionStore.isMuted ? strings.unmute : strings.mute)
            }
            Spacer()
            controlColumn(label: strings.end) {
                Button(action: stopSession) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(EasyTalk.danger))
                        .shadow(color: EasyTalk.danger.opacity(0.4), radius: 10, x: 0, y: 8)
                }
                .accessibilityLabel(strings.end)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .background(
            EasyTalk.bar
                .overlay(Rectangle().fill(EasyTalk.stroke).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func controlColumn(label: String, @ViewBuilder button: () -> some View) -> some View {
        VStack(spacing: 6) {
            button()
            Text(label)
                .font(.easyTalk(10.5, .medium))
                .foregroundColor(EasyTalk.fg2)
        }
    }

    // MARK: State mapping

    private var activeColor: Color {
        EasyTalk.side(sessionStore.activeSide)
    }

    private var statusColor: Color {
        switch sessionStore.state {
        case .idle, .loadingConfig, .creatingSession, .connecting, .reconnecting:
            return EasyTalk.accent
        case .active:
            return sessionStore.isMuted ? EasyTalk.english : activeColor
        case .failed:
            return EasyTalk.danger
        case .completed:
            return EasyTalk.fg3
        }
    }

    private var statusLabel: String {
        switch sessionStore.state {
        case .idle, .loadingConfig, .creatingSession, .connecting, .reconnecting:
            return strings.connecting
        case .active:
            return sessionStore.isMuted ? strings.ready : strings.listening
        case .failed:
            return strings.degraded
        case .completed:
            return strings.ready
        }
    }

    private var isDegraded: Bool {
        if case .reconnecting = sessionStore.state { return true }
        return false
    }

    // MARK: Session lifecycle

    private func startLiveSession() {
        Task {
            await sessionStore.startSession(mode: mode)

            if case .failed = sessionStore.state { return }

            timerSubscription = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                sessionDuration += 1
            }
        }
    }

    private func switchSpeaker() {
        let next: Side = sessionStore.activeSide == .russianSpeaker ? .englishSpeaker : .russianSpeaker
        sessionStore.switchSide(to: next)
    }

    private func stopSession() {
        cleanupTimers()
        finishedSegments = sessionStore.segments
        sessionStore.stopSession()
        showFeedback = true
    }

    private func cleanupTimers() {
        timerSubscription?.invalidate()
        timerSubscription = nil
    }
}

private struct WaveBar: View {
    let color: Color
    let delay: Double
    @State private var isUp = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(width: 8, height: 80)
            .scaleEffect(y: isUp ? 1.0 : 0.28, anchor: .bottom)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay),
                value: isUp
            )
            .onAppear { isUp = true }
    }
}
