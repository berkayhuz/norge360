import SwiftUI

struct StatusBadge: View {
    let status: TaskStatus

    private var tint: Color {
        switch status {
        case .notStarted: .secondary
        case .inProgress: .orange
        case .completed: .green
        }
    }

    var body: some View {
        Label(status.title, systemImage: status == .completed ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityLabel(status.title)
    }
}
