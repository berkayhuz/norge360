import SwiftUI
import UIKit

/// Reusable compact form controls. Features own their validation and bindings;
/// this layer owns the shared field geometry, keyboard defaults and password
/// visibility affordance.
struct NorgeCapsuleTextField: View {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var height: CGFloat = 46

    var body: some View {
        TextField(placeholder, text: $text)
            .textContentType(contentType)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .norgeCapsuleInput(height: height, horizontalPadding: 20)
    }
}

struct NorgeCapsulePasswordField: View {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    var height: CGFloat = 46
    @State private var revealsPassword = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealsPassword {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(contentType)

            Button {
                revealsPassword.toggle()
            } label: {
                Image(systemName: revealsPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(revealsPassword ? AppStrings.auth("hide_password") : AppStrings.auth("show_password"))
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: height)
        .background(Color.norgeInputSurface, in: Capsule())
    }
}

struct NorgeOutlinedTextField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    var height: CGFloat = 45

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.norgeMutedTextOnLight)
                .frame(width: 18)
            TextField(title, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.norgeTextOnLight)
        }
        .font(.system(size: 13))
        .norgeOutlinedInput(height: height)
    }
}

struct NorgeOutlinedPasswordField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    var height: CGFloat = 45
    @State private var revealsPassword = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "lock")
                .foregroundStyle(Color.norgeMutedTextOnLight)
                .frame(width: 18)

            Group {
                if revealsPassword { TextField(title, text: $text) } else { SecureField(title, text: $text) }
            }
            .textContentType(contentType)
            .foregroundStyle(Color.norgeTextOnLight)

            Button {
                revealsPassword.toggle()
            } label: {
                Image(systemName: revealsPassword ? "eye.slash" : "eye")
                    .foregroundStyle(Color.norgeMutedTextOnLight)
            }
            .accessibilityLabel(revealsPassword ? AppStrings.auth("hide_password") : AppStrings.auth("show_password"))
        }
        .font(.system(size: 13))
        .norgeOutlinedInput(height: height)
    }
}

struct NorgeCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(configuration.isOn ? Color.norgePrimary : Color.norgeMutedTextOnLight)
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}

struct NorgeCapsulePickerRow<Content: View>: View {
    let title: String
    var titleWidth: CGFloat = 72
    var height: CGFloat = NorgeControlSize.prominent
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: titleWidth, alignment: .leading)
            content
                .labelsHidden()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .norgeCapsuleInput(height: height)
    }
}

struct NorgeCapsuleDisclosureRow: View {
    let title: String
    let value: String
    var height: CGFloat = NorgeControlSize.prominent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.medium)).foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .norgeCapsuleInput(height: height)
    }
}
