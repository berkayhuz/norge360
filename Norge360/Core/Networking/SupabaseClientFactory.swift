import Foundation
import Supabase

enum SupabaseClientFactory {
    static func makeNetworkSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    static func make(bundle: Bundle = .main) -> SupabaseClient {
        guard let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let url = URL(string: urlString),
            let key = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
            !key.isEmpty
        else {
            preconditionFailure("Supabase client configuration is missing.")
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: .init(
                auth: .init(
                    storage: KeychainLocalStorage(),
                    redirectToURL: AuthCallbackURL.url,
                    emitLocalSessionAsInitialSession: true
                ),
                global: .init(session: makeNetworkSession())
            )
        )
    }
}
