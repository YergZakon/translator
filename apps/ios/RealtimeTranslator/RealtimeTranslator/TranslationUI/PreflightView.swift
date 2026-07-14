import SwiftUI

struct PreflightView: View {
    let mode: TranslationMode
    @Binding var isConfirmed: Bool
    @EnvironmentObject var container: DependencyContainer
    @State private var micPermissionGranted = false
    @State private var isChecking = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Проверка готовности")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: micPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(micPermissionGranted ? .green : .red)
                    Text("Доступ к микрофону")
                }
                
                HStack {
                    Image(systemName: "wifi")
                        .foregroundColor(.green)
                    Text("Сеть готова (Dev environment)")
                }
                
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.green)
                    Text("Аудиовыход: \(container.audioController.currentRoute)")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            if isChecking {
                ProgressView("Проверка оборудования...")
                    .padding()
            } else if !micPermissionGranted {
                Button("Разрешить доступ к микрофону") {
                    requestMicPermission()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            } else {
                Button("Начать перевод") {
                    isConfirmed = true
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.top, 20)
            }
        }
        .padding()
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        // Mock permission check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.micPermissionGranted = true
            self.isChecking = false
        }
    }
    
    private func requestMicPermission() {
        self.micPermissionGranted = true
    }
}
