import Foundation
import Supabase

enum SupabaseClientFactory {
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
                ))
        )
    }
}
