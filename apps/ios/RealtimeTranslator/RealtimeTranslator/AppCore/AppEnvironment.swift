import Foundation

enum AppEnvironment: String, Codable, CaseIterable {
    case development
    case staging
    case production

    static var current: AppEnvironment = .development

    var baseURL: URL {
        switch self {
        case .development:
            return URL(string: "http://localhost:3000")!
        case .staging:
            return URL(string: "https://backend-api-stage-ee06.up.railway.app")!
        case .production:
            return URL(string: "https://api.translator.internal")!
        }
    }
}
