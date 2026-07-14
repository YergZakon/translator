import SwiftUI

struct HomeView: View {
    @EnvironmentObject var container: DependencyContainer
    @StateObject private var sessionStore = TranslationSessionStore()
    @State private var showDiagnostics = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                Text("Realtime Translator")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Синхронный голосовой перевод RU ↔ EN")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                NavigationLink(destination: LiveView(sessionStore: sessionStore, mode: .oneWayRuToEn)) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Я говорю (RU → EN)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                NavigationLink(destination: LiveView(sessionStore: sessionStore, mode: .dialogue)) {
                    HStack {
                        Image(systemName: "arrow.left.and.right.circle.fill")
                        Text("Диалог (RU ↔ EN)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
                
                HStack {
                    Button(action: { showDiagnostics = true }) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("Диагностика")
                        }
                        .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
                    .environmentObject(container)
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(DependencyContainer.shared)
    }
}
