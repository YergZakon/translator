import SwiftUI

struct LiveView: View {
    @ObservedObject var sessionStore: TranslationSessionStore
    let mode: TranslationMode
    @Environment(\.presentationMode) var presentationMode
    @State private var isPreflightPassed = false
    @State private var volumeLevels: [CGFloat] = Array(repeating: 0.1, count: 20)
    @State private var showFeedback = false
    @State private var sessionDuration: TimeInterval = 0
    @State private var timerSubscription: Timer? = nil

    var body: some View {
        VStack(spacing: 0) {
            if !isPreflightPassed {
                PreflightView(mode: mode, isConfirmed: $isPreflightPassed)
            } else {
                VStack(spacing: 0) {
                    // Header Bar
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .animation(isPulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isPulsing)

                        Text(sessionStore.state.displayName)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Spacer()

                        Text(formatDuration(sessionDuration))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)

                        Button(action: {
                            sessionStore.setMute(!sessionStore.isMuted)
                        }) {
                            Image(systemName: sessionStore.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(sessionStore.isMuted ? .red : .blue)
                                .padding(10)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(sessionStore.isMuted ? "Включить звук" : "Выключить звук")
                    }
                    .padding()
                    .background(Color(.systemBackground))

                    // Subtitles feed area
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(sessionStore.segments) { seg in
                                    HStack {
                                        if seg.side == .russianSpeaker {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Вы (RU)")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.blue)
                                                Text(seg.text)
                                                    .font(.body)
                                                    .padding(12)
                                                    .background(Color.blue.opacity(0.12))
                                                    .cornerRadius(14)
                                            }
                                            Spacer(minLength: 60)
                                        } else {
                                            Spacer(minLength: 60)
                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text("Собеседник (EN)")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.green)
                                                Text(seg.text)
                                                    .font(.body)
                                                    .padding(12)
                                                    .background(Color.green.opacity(0.12))
                                                    .cornerRadius(14)
                                            }
                                        }
                                    }
                                    .id(seg.id)
                                    .transition(.opacity.combined(with: .slide))
                                }
                            }
                            .padding()
                        }
                        .onChange(of: sessionStore.segments.last?.text) { _ in
                            if let last = sessionStore.segments.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground).opacity(0.5))

                    // Volume Level wave meter
                    if isListeningOrTranslating {
                        HStack(spacing: 3) {
                            ForEach(0..<volumeLevels.count, id: \.self) { idx in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(sessionStore.activeSide == .russianSpeaker ? Color.blue : Color.green)
                                    .frame(width: 4, height: volumeLevels[idx] * 40)
                            }
                        }
                        .frame(height: 50)
                        .padding(.vertical, 8)
                        .animation(.spring(response: 0.15, dampingFraction: 0.4), value: volumeLevels)
                    }

                    // Controls Area
                    VStack(spacing: 16) {
                        if mode == .dialogue {
                            // Split-style switch zone
                            HStack(spacing: 16) {
                                Button(action: {
                                    sessionStore.switchSide(to: .russianSpeaker)
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.fill")
                                            .font(.title)
                                        Text("Я говорю (RU)")
                                            .fontWeight(.bold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(sessionStore.activeSide == .russianSpeaker ? Color.blue : Color.gray.opacity(0.15))
                                    .foregroundColor(sessionStore.activeSide == .russianSpeaker ? .white : .primary)
                                    .cornerRadius(18)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(sessionStore.activeSide == .russianSpeaker ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                                    )
                                }
                                .accessibilityLabel("Активировать сторону Я говорю по-русски")

                                Button(action: {
                                    sessionStore.switchSide(to: .englishSpeaker)
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.2.fill")
                                            .font(.title)
                                        Text("Собеседник (EN)")
                                            .fontWeight(.bold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(sessionStore.activeSide == .englishSpeaker ? Color.green : Color.gray.opacity(0.15))
                                    .foregroundColor(sessionStore.activeSide == .englishSpeaker ? .white : .primary)
                                    .cornerRadius(18)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(sessionStore.activeSide == .englishSpeaker ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                                    )
                                }
                                .accessibilityLabel("Активировать сторону Собеседник говорит по-английски")
                            }
                            .padding(.horizontal)
                        } else {
                            // One way controls
                            Button(action: {
                                sessionStore.switchSide(to: .russianSpeaker)
                            }) {
                                HStack {
                                    Image(systemName: "mic.fill")
                                    Text("Говорить (RU)")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            }
                            .padding(.horizontal)
                            .accessibilityLabel("Начать запись русской речи")
                        }

                        // Stop button (minimum 48pt target)
                        Button(action: stopSession) {
                            Text("Завершить разговор")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                        .accessibilityLabel("Завершить текущую сессию перевода")
                    }
                    .background(Color(.systemBackground))
                }
                .onAppear {
                    startLiveSession()
                }
                .onDisappear {
                    cleanupTimers()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showFeedback) {
            ResultView(duration: sessionDuration)
        }
    }

    private var statusColor: Color {
        switch sessionStore.state {
        case .idle: return .gray
        case .loadingConfig, .creatingSession, .connecting: return .orange
        case .active: return .green
        case .reconnecting: return .red
        case .failed: return .red
        case .completed: return .gray
        }
    }

    private var isPulsing: Bool {
        switch sessionStore.state {
        case .connecting, .active, .reconnecting: return true
        default: return false
        }
    }

    private var isListeningOrTranslating: Bool {
        switch sessionStore.state {
        case .active: return true
        default: return false
        }
    }

    private func startLiveSession() {
        Task {
            await sessionStore.startSession(mode: mode)

            if case .failed = sessionStore.state { return }

            // Timer for duration
            timerSubscription = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                sessionDuration += 1
            }
        }
    }

    private func stopSession() {
        cleanupTimers()
        sessionStore.stopSession()
        showFeedback = true
    }

    private func cleanupTimers() {
        timerSubscription?.invalidate()
        timerSubscription = nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
