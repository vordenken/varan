import SwiftUI

struct ConfigurationEditorField<Content: View>: View {
  let title: String
  let explanation: String?
  private let content: Content

  init(_ title: String, explanation: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.explanation = explanation
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(LocalizedStringKey(title))
        .font(.subheadline.weight(.semibold))
      content
      if let explanation {
        Text(LocalizedStringKey(explanation))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ConfigurationTextField: View {
  let title: String
  @Binding var text: String
  let explanation: String?
  let identifier: String

  init(_ title: String, text: Binding<String>, explanation: String? = nil, identifier: String? = nil) {
    self.title = title
    _text = text
    self.explanation = explanation
    self.identifier = identifier ?? "configuration-editor-\(title)"
  }

  var body: some View {
    ConfigurationEditorField(title, explanation: explanation) {
      TextField("", text: $text, prompt: Text("configuration.editor.placeholder"))
        #if os(iOS)
        .textFieldStyle(.plain)
        #else
        .textFieldStyle(.automatic)
        #endif
        .accessibilityLabel(LocalizedStringKey(title))
        .accessibilityIdentifier(identifier)
    }
  }
}

struct ConfigurationToggle: View {
  let title: String
  @Binding var isOn: Bool
  let explanation: String
  var identifier: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle(LocalizedStringKey(title), isOn: $isOn)
        .accessibilityIdentifier(identifier ?? "configuration-editor-\(title)")
      Text(LocalizedStringKey(explanation))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
