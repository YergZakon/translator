import Foundation

class DiagnosticsStore: ObservableObject {
    @Published private(set) var logs: [String] = []

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let formattedMessage = "[\(timestamp)] \(message)"

        DispatchQueue.main.async {
            self.logs.append(formattedMessage)
            if self.logs.count > 100 {
                self.logs.removeFirst()
            }
        }
    }
}
