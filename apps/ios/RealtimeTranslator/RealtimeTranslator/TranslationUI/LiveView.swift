import SwiftUI

struct LiveView: View {
    @ObservedObject var sessionStore: TranslationSessionStore
    let mode: TranslationMode
    @Environment(\.presentationMode) var presentationMode
    @State private var isPreflightPassed = false
    @State private var mockTimer: Timer? = nil
    
    var body: some View {
        VStack {
            if !isPreflightPassed {
                PreflightView(mode: mode, isConfirmed: $isPreflightPassed)
            } else {
                VStack(spacing: 20) {
                    // Status bar
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                        Text(sessionStore.state.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        Button(action: {
                            sessionStore.setMute(!sessionStore.isMuted)
                        }) {
                            Image(systemName: sessionStore.isMuted ? "mic.slash.fill" : "mic.fill")
                                .foregroundColor(sessionStore.isMuted ? .red : .blue)
                                .padding(8)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    
                    // Subtitles Buffer area
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                ForEach(sessionStore.segments) { seg in
                                    HStack {
                                        if seg.side == .russianSpeaker {
                                            VStack(alignment: .leading) {
                                                Text("RU:")
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.blue)
                                                Text(seg.text)
                                                    .padding(10)
                                                    .background(Color.blue.opacity(0.1))
                                                    .cornerRadius(10)
                                            }
                                            Spacer()
                                        } else {
                                            Spacer()
                                            VStack(alignment: .trailing) {
                                                Text("EN:")
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.green)
                                                Text(seg.text)
                                                    .padding(10)
                                                    .background(Color.green.opacity(0.1))
                                                    .cornerRadius(10)
                                            }
                                        }
                                    }
                                    .id(seg.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: sessionStore.segments.count) { _ in
                            if let last = sessionStore.segments.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // Controls Area
                    if mode == .dialogue {
                        HStack(spacing: 20) {
                            Button(action: {
                                sessionStore.switchSide(to: .russianSpeaker)
                            }) {
                                Text("Я говорю (RU)")
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(sessionStore.activeSide == .russianSpeaker ? Color.blue : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                sessionStore.switchSide(to: .englishSpeaker)
                            }) {
                                Text("Собеседник (EN)")
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(sessionStore.activeSide == .englishSpeaker ? Color.green : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        Button(action: {
                            sessionStore.switchSide(to: .russianSpeaker)
                        }) {
                            Text("Говорить (RU)")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    Button(action: {
                        stopSession()
                    }) {
                        Text("Завершить")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .onAppear {
                    startMockSession()
                }
                .onDisappear {
                    mockTimer?.invalidate()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private var statusColor: Color {
        switch sessionStore.state {
        case .idle: return .gray
        case .preparingAudio, .requestingSecret, .negotiatingWebRTC: return .orange
        case .ready: return .green
        case .listening: return .blue
        case .translating: return .purple
        case .networkDegraded: return .yellow
        case .reconnecting: return .red
        case .error: return .red
        case .ending: return .gray
        }
    }
    
    private func startMockSession() {
        Task {
            await sessionStore.startSession(mode: mode)
            
            // Start producing some mock text deltas
            var counter = 0
            mockTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
                counter += 1
                let side: Side = (mode == .dialogue && counter % 2 == 0) ? .englishSpeaker : .russianSpeaker
                let text = side == .russianSpeaker ? "Привет, как дела? " : "Hello, how are you? "
                let segId = "seg_\(counter)"
                
                sessionStore.appendTranscriptDelta(id: segId, text: text, side: side, isFinal: false)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    sessionStore.appendTranscriptDelta(id: segId, text: "Все отлично!", side: side, isFinal: true)
                    sessionStore.completeSegment(id: segId)
                }
            }
        }
    }
    
    private func stopSession() {
        mockTimer?.invalidate()
        sessionStore.stopSession()
        presentationMode.wrappedValue.dismiss()
    }
}
