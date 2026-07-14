import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Состояние сети")) {
                    HStack {
                        Text("Environment")
                        Spacer()
                        Text(container.environment.rawValue)
                    }
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text(container.environment.baseURL.absoluteString)
                            .font(.caption)
                    }
                }
                
                Section(header: Text("Аудио")) {
                    HStack {
                        Text("Route")
                        Spacer()
                        Text(container.audioController.currentRoute)
                    }
                }
                
                Section(header: Text("Журнал диагностики")) {
                    ForEach(container.diagnosticsStore.logs, id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Диагностика")
            .navigationBarItems(trailing: Button("Закрыть") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
