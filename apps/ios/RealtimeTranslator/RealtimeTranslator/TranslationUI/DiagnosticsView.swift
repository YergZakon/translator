import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                List {
                    Section(header: Text("Параметры Окружения")) {
                        HStack {
                            Text("Окружение")
                            Spacer()
                            Text(container.environment.rawValue.uppercased())
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        HStack {
                            Text("Endpoint URL")
                            Spacer()
                            Text(container.environment.baseURL.absoluteString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section(header: Text("Состояние Устройства")) {
                        HStack {
                            Text("Аудиовыход")
                            Spacer()
                            Text(container.audioController.currentRoute)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Флаг: Автоопределение")
                            Spacer()
                            Text(container.featureFlags.enableAutoSideDetection ? "Да" : "Нет")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section(header: Text("Логи Событий WebRTC (P0)")) {
                        if container.diagnosticsStore.logs.isEmpty {
                            Text("Нет записанных логов.")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(container.diagnosticsStore.logs, id: \.self) { log in
                                Text(log)
                                    .font(.system(.caption2, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Панель Диагностики")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Закрыть") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
