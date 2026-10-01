import SwiftUI

struct StackComposeEditorSection: View {
  @Binding var draft: StackComposeDraft
  @State private var revealingContents = false
  @State private var revealingEnvironment = false

  var body: some View {
    Section("configuration.group.files") {
      ConfigurationEditorField("stack.compose.source.label", explanation: "configuration.help.composeSource") {
        Picker("stack.compose.source.label", selection: $draft.source) {
          ForEach(draft.availableSources) { source in
            Text(LocalizedStringKey(source.localizationKey)).tag(source)
          }
        }
        .labelsHidden()
        .accessibilityLabel("stack.compose.source.label")
        .accessibilityIdentifier("stack-editor-source-picker")
      }
      if draft.source == .linkedRepo {
        ConfigurationEditorField("configuration.field.linkedRepo", explanation: "configuration.help.linkedRepo") {
          Text(draft.original?.linkedRepo ?? "").textSelection(.enabled)
        }
      }
      if draft.source == .komodo {
        Toggle("stack.compose.revealContents", isOn: $revealingContents)
        if revealingContents {
          ConfigurationEditorField("configuration.field.fileContents", explanation: "configuration.help.fileContents") {
            TextEditor(text: $draft.fileContents)
              .font(.system(.body, design: .monospaced))
              .frame(minHeight: 180)
              .privacySensitive()
              .accessibilityLabel("configuration.field.fileContents")
              .accessibilityIdentifier("stack-editor-compose-contents")
          }
        }
      }
      ConfigurationTextField("configuration.field.runDirectory", text: $draft.runDirectory,
        explanation: "configuration.help.runDirectory", identifier: "stack-editor-run-directory")
      ConfigurationEditorField("configuration.field.filePaths", explanation: "stack.compose.paths.help") {
        TextEditor(text: $draft.filePathsText)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 80)
          .accessibilityLabel("configuration.field.filePaths")
          .accessibilityIdentifier("stack-editor-file-paths")
      }
      ConfigurationTextField("configuration.field.envFilePath", text: $draft.envFilePath,
        explanation: "configuration.help.envFilePath", identifier: "stack-editor-env-path")
      Toggle("stack.compose.revealEnvironment", isOn: $revealingEnvironment)
      if revealingEnvironment {
        ConfigurationEditorField("configuration.field.environment", explanation: "configuration.help.environment") {
          TextEditor(text: $draft.environment)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 120)
            .privacySensitive()
            .accessibilityLabel("configuration.field.environment")
            .accessibilityIdentifier("stack-editor-environment")
        }
      }
      if let message = draft.validationMessageKey {
        Text(LocalizedStringKey(message)).foregroundStyle(.red)
      }
    }
  }
}
