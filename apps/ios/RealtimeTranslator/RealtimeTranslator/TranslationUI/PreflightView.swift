import SwiftUI

struct PreflightView: View {
    let mode: TranslationMode
    @Binding var isConfirmed: Bool
    @EnvironmentObject var container: DependencyContainer
    @State private var micPermissionGranted = false
    @State private var networkChecked = false
    @State private var audioRouteChecked = false
    @State private var isChecking = true

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 30) {
                Text("Подготовка Окружения")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .padding(.top, 40)

                VStack(spacing: 20) {
                    // Check item 1
                    HStack {
                        Image(systemName: micPermissionGranted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(micPermissionGranted ? .green : .secondary)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Разрешение микрофона")
                                .fontWeight(.medium)
                            Text(micPermissionGranted ? "Доступ предоставлен" : "Ожидание доступа...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    // Check item 2
                    HStack {
                        Image(systemName: networkChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(networkChecked ? .green : .secondary)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Подключение к интернету")
                                .fontWeight(.medium)
                            Text(networkChecked ? "Соединение стабильное" : "Проверка сети...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    // Check item 3
                    HStack {
                        Image(systemName: audioRouteChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(audioRouteChecked ? .green : .secondary)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Аудиомаршрут")
                                .fontWeight(.medium)
                            Text("Выход: \(container.audioController.currentRoute)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(24)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(18)
                .padding(.horizontal)

                Spacer()

                if isChecking {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Проверяем доступность сервисов...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    Button(action: {
                        isConfirmed = true
                    }) {
                        Text("Начать перевод")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                    .accessibilityLabel("Начать сессию перевода")
                }
            }
        }
        .onAppear {
            runPreflightChecks()
        }
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
