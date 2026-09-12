import SwiftUI

/// Shared label for overflow menus. Menu actions remain feature-owned while
/// touch size and visual weight stay consistent across community content.
struct NorgeOverflowMenuLabel: View {
    var font: Font = .body.weight(.semibold)

    var body: some View {
        Image(systemName: "ellipsis")
            .font(font)
            .foregroundStyle(.primary)
            .frame(width: NorgeControlSize.tapTarget, height: NorgeControlSize.tapTarget)
            .contentShape(Rectangle())
    }
}

/// Small secondary metadata treatment for locations, dates and compact facts.
struct NorgeMetadataLabel: View {
    let title: String
    let systemImage: String
    var font: Font = .caption

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(font)
            .foregroundStyle(.secondary)
    }
}
