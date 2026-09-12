import Foundation

enum AuthCallbackURL {
    static let scheme = "com.norge360.app.auth"
    static let host = "auth"
    static let path = "/callback"
    static let url: URL = {
        guard let url = URL(string: "\(scheme)://\(host)\(path)") else {
            preconditionFailure("Auth callback URL configuration is invalid.")
        }
        return url
    }()

    /// Accept only the callback route owned by this app. OAuth query and
    /// fragment parameters are intentionally allowed because Supabase may use
    /// either PKCE or implicit-flow response parameters.
    static func isValid(_ candidate: URL) -> Bool {
        candidate.scheme?.caseInsensitiveCompare(scheme) == .orderedSame
            && candidate.host?.caseInsensitiveCompare(host) == .orderedSame
            && candidate.path == path
            && candidate.user == nil
            && candidate.password == nil
            && candidate.port == nil
    }
}
