import Foundation

class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()
    
    let environment: AppEnvironment
    @Published var featureFlags: FeatureFlags
    let backendClient: BackendClient
    let audioController: AudioSessionController
    let outputArbiter: OutputArbiter
    let telemetryClient: TelemetryClient
    let diagnosticsStore: DiagnosticsStore
    
    init(environment: AppEnvironment = .development) {
        self.environment = environment
        self.featureFlags = FeatureFlags()
        
        let diag = DiagnosticsStore()
        let tele = TelemetryClient(diagnostics: diag)
        
        self.diagnosticsStore = diag
        self.telemetryClient = tele
        self.backendClient = BackendClient(environment: environment, telemetry: tele)
        self.audioController = AudioSessionController(diagnostics: diag)
        self.outputArbiter = OutputArbiter(diagnostics: diag)
    }
}
