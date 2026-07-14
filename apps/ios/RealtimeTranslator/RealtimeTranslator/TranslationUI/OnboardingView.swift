import SwiftUI

struct OnboardingView: View {
    @Binding var isOnboardingCompleted: Bool
    @State private var currentPage = 0
    @State private var micPermissionGranted = false
    @State private var isRequesting = false

    let cards = [
        OnboardingCard(
            title: "Синхронный Перевод",
            description: "Говорите естественно. Приложение переведет вашу речь в реальном времени с минимальной задержкой.",
            icon: "bubble.left.and.bubble.right.fill",
            color: .blue
        ),
        OnboardingCard(
            title: "Прямой WebRTC",
            description: "Прямое подключение к OpenAI без промежуточных серверов обеспечивает превосходную скорость.",
            icon: "bolt.horizontal.fill",
            color: .orange
        ),
        OnboardingCard(
            title: "Конфиденциальность",
            description: "Ваш аудиопоток и транскрипты не сохраняются на сервере и используются исключительно для перевода.",
            icon: "lock.shield.fill",
            color: .green
        )
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack {
                Spacer()

                TabView(selection: $currentPage) {
                    ForEach(0..<cards.count, id: \.self) { idx in
                        VStack(spacing: 24) {
                            Image(systemName: cards[idx].icon)
                                .font(.system(size: 80))
                                .foregroundColor(cards[idx].color)
                                .padding()
                                .accessibilityHidden(true)

                            Text(cards[idx].title)
                                .font(.system(.largeTitle, design: .rounded))
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Text(cards[idx].description)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(PageTabViewStyle())
                .frame(maxHeight: 450)

                Spacer()

                // Indicators & Action buttons
                VStack(spacing: 16) {
                    if currentPage == cards.count - 1 {
                        if !micPermissionGranted {
                            Button(action: requestMicPermission) {
                                HStack {
                                    if isRequesting {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "mic.fill")
                                    }
                                    Text(isRequesting ? "Запрос..." : "Предоставить доступ к микрофону")
                                }
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .accessibilityLabel("Запросить доступ к микрофону")
                            }
                            .disabled(isRequesting)
                        } else {
                            Button(action: {
                                withAnimation {
                                    isOnboardingCompleted = true
                                }
                            }) {
                                Text("Начать работу")
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                                    .accessibilityLabel("Начать работу с приложением")
                            }
                        }
                    } else {
                        Button(action: {
                            withAnimation {
                                currentPage += 1
                            }
                        }) {
                            Text("Далее")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.primary)
                                .cornerRadius(14)
                                .accessibilityLabel("Перейти к следующему экрану")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func requestMicPermission() {
        isRequesting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.isRequesting = false
            self.micPermissionGranted = true
        }
    }
}

struct OnboardingCard {
    let title: String
    let description: String
    let icon: String
    let color: Color
}
