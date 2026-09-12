import SwiftUI

enum NorgeToastKind: Sendable, Equatable {
    case error
    case notice
    case success

    var color: Color {
        switch self {
        case .error: .red
        case .notice: .secondary
        case .success: .green
        }
    }

    var systemImage: String {
        switch self {
        case .error: "exclamationmark.triangle.fill"
        case .notice: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }
}

struct NorgeToastItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let message: String
    let kind: NorgeToastKind

    init(message: String, kind: NorgeToastKind) {
        id = UUID()
        self.message = message
        self.kind = kind
    }
}

@MainActor
final class NorgeToastCenter: ObservableObject {
    static let shared = NorgeToastCenter()

    @Published private(set) var current: NorgeToastItem?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, kind: NorgeToastKind = .error, duration: Duration = .seconds(4)) {
        guard !message.isEmpty else { return }
        dismissTask?.cancel()
        let item = NorgeToastItem(message: message, kind: kind)
        current = item
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(id: item.id)
        }
    }

    func dismiss(id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        current = nil
        dismissTask?.cancel()
        dismissTask = nil
    }

    deinit {
        dismissTask?.cancel()
    }
}

struct NorgeFeedbackToast: View {
    let item: NorgeToastItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.kind.color)
            Text(item.message)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .foregroundStyle(Color.primary)
        .background(Color.norgeTopBarBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }
}

/// Canonical non-content state for lists and full-page destinations.
/// Screens decide when it is shown; the design system owns its presentation.
struct NorgeUnavailableState: View {
    let title: String
    let systemImage: String
    var description: String?

    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        if let description {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            ContentUnavailableView(title, systemImage: systemImage)
        }
    }
}

struct NorgeLoadingState: View {
    var minimumHeight: CGFloat?
    var topPadding: CGFloat = 0
    var fillsAvailableSpace = false

    var body: some View {
        ProgressView()
            .frame(
                maxWidth: .infinity,
                minHeight: minimumHeight,
                maxHeight: fillsAvailableSpace ? .infinity : nil
            )
            .padding(.top, topPadding)
    }
}

struct NorgeInlineFeedback: View {
    enum Kind: Equatable {
        case error
        case notice
    }

    let message: String
    var kind: Kind = .error

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: message) {
                NorgeToastCenter.shared.show(
                    message,
                    kind: kind == .error ? .error : .notice
                )
            }
            .accessibilityHidden(true)
    }
}

/// Standard error section for `Form` and `List` settings screens.
struct NorgeFormErrorSection: View {
    let message: String

    var body: some View {
        Section {
            NorgeInlineFeedback(message: message)
        }
        .frame(height: 0)
        .listRowBackground(Color.norgeAppBackground)
    }
}
