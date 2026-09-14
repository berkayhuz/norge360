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
        NorgeSkeletonList(rowCount: fillsAvailableSpace ? 4 : 2)
            .frame(
                maxWidth: .infinity,
                minHeight: minimumHeight,
                maxHeight: fillsAvailableSpace ? .infinity : nil
            )
            .padding(.horizontal, NorgeSpacing.medium)
            .padding(.top, topPadding)
    }
}

/// A lightweight, theme-aware placeholder with a subtle moving highlight.
/// It gives async content a stable shape before the real data arrives.
struct NorgeSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    @State private var phase: CGFloat = -1

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 7) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseColor)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, highlightColor, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(proxy.size.width * 0.55, 120))
                    .offset(x: phase * max(proxy.size.width * 1.7, 220))
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task {
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .accessibilityHidden(true)
    }

    private var baseColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }

    private var highlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.52)
    }
}

/// Reusable feed-shaped placeholders used by all full-page loading states.
struct NorgeSkeletonList: View {
    var rowCount = 3
    var showsMedia = true

    var body: some View {
        VStack(alignment: .leading, spacing: NorgeLayoutMetrics.feedItemSpacing) {
            ForEach(0..<max(rowCount, 1), id: \.self) { _ in
                NorgeSkeletonFeedRow(showsMedia: showsMedia)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NorgeSkeletonFeedRow: View {
    let showsMedia: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NorgeSkeleton(width: 44, height: 44, cornerRadius: 22)
                VStack(alignment: .leading, spacing: 6) {
                    NorgeSkeleton(width: 142, height: 12)
                    NorgeSkeleton(width: 92, height: 10)
                }
                Spacer(minLength: 0)
                NorgeSkeleton(width: 34, height: 28, cornerRadius: 14)
            }
            NorgeSkeleton(height: 14)
            NorgeSkeleton(width: 230, height: 14)
            if showsMedia {
                NorgeSkeleton(height: 176, cornerRadius: NorgeMediaMetrics.postCornerRadius)
            }
            HStack(spacing: 18) {
                NorgeSkeleton(width: 48, height: 12)
                NorgeSkeleton(width: 48, height: 12)
                NorgeSkeleton(width: 48, height: 12)
                Spacer(minLength: 0)
                NorgeSkeleton(width: 30, height: 12)
            }
        }
        .padding(.vertical, 6)
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
