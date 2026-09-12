import Foundation

/// Owns one delayed task at a time. Useful for deliberate, cancellation-aware
/// UI searches without coupling a feature to `Task` lifecycle bookkeeping.
@MainActor
final class NorgeTaskDebouncer: ObservableObject {
    private var pendingTask: Task<Void, Never>?

    deinit { pendingTask?.cancel() }

    func schedule(
        after delay: Duration = .milliseconds(250),
        operation: @escaping @MainActor () async -> Void
    ) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await operation()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
