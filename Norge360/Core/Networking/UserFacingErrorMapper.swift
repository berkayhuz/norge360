import Foundation
import OSLog

/// Keeps backend and SDK diagnostics out of user-facing messages while retaining
/// enough non-sensitive context for local troubleshooting.
enum UserFacingErrorMapper {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.norge360.app",
        category: "user-facing-error"
    )

    static func message(for error: Error, fallbackKey: String, operation: String = #function) -> String {
        let errorType = String(reflecting: type(of: error))
        logger.error(
            "Operation failed. operation=\(operation, privacy: .public) type=\(errorType, privacy: .public)"
        )
        return AppStrings.localized(fallbackKey)
    }
}
