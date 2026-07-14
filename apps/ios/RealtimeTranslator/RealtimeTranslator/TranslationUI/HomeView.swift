import SwiftUI

struct HomeView: View {
    @EnvironmentObject var container: DependencyContainer
    @StateObject private var sessionStore = TranslationSessionStore()
    @State private var showDiagnostics = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background Gradient
                LinearGradient(colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.12)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // Logo & Slogan
                    VStack(spacing: 12) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                            )
                            .accessibilityHidden(true)

                        Text("Realtime Translator")
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.black)

                        Text("Синхронный голосовой перевод в реальном времени")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()

                    // Modes Container with Glassmorphism
                    VStack(spacing: 16) {
                        NavigationLink(destination: LiveView(sessionStore: sessionStore, mode: .oneWayRuToEn)) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "mic.badge.plus").foregroundColor(.blue))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Режим «Я говорю»")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Русский микрофон → английский звук и текст")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground).opacity(0.7))
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .accessibilityLabel("Режим Я говорю. Русский микрофон переводит на английский")

                        NavigationLink(destination: LiveView(sessionStore: sessionStore, mode: .dialogue)) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.green.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "arrow.left.and.right.circle.fill").foregroundColor(.green))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Режим «Диалог»")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Двусторонний разговор на одном экране")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground).opacity(0.7))
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .accessibilityLabel("Режим Диалог. Двусторонний разговор на одном экране")
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    // Bottom Controls
                    Button(action: { showDiagnostics = true }) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("Диагностика")
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(24)
                    }
                    .padding(.bottom, 16)
                    .accessibilityLabel("Открыть экран диагностики")
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
                    .environmentObject(container)
            }
        }
    }
}
