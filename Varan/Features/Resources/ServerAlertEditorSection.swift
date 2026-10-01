import SwiftUI

struct ServerAlertEditorSection: View {
  @Binding var draft: ServerAlertDraft

  var body: some View {
    Section("configuration.group.alerts") {
      DisclosureGroup {
        ForEach(ServerAlertSetting.allCases) { setting in
          if let value = draft.alerts[setting] {
            Toggle(LocalizedStringKey(setting.localizationKey), isOn: Binding(
              get: { draft.alerts[setting] ?? value },
              set: { draft.alerts[setting] = $0 }
            ))
            .accessibilityIdentifier("server-editor-alert-\(setting.rawValue)")
          } else {
            LabeledContent(LocalizedStringKey(setting.localizationKey)) {
              Text("configuration.value.unavailable")
            }
          }
        }
      } label: {
        Text("server.alerts.delivery")
          .accessibilityIdentifier("server-editor-alert-delivery")
      }
      DisclosureGroup {
        ForEach(ServerAlertThreshold.allCases) { threshold in
          if draft.canEdit(threshold) {
            HStack {
              Text(LocalizedStringKey(threshold.localizationKey))
              Spacer()
              thresholdField(threshold)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 60, maxWidth: 100)
                .accessibilityLabel(LocalizedStringKey(threshold.localizationKey))
                .accessibilityIdentifier("server-editor-threshold-\(threshold.rawValue)")
              Text(verbatim: "%").foregroundStyle(.secondary)
            }
          } else {
            LabeledContent(LocalizedStringKey(threshold.localizationKey)) {
              if let value = threshold.value(in: draft.original) {
                Text(value, format: .number).foregroundStyle(.secondary)
              } else {
                Text("configuration.value.unavailable")
              }
            }
          }
        }
        Text("server.alerts.thresholds.help")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } label: {
        Text("server.alerts.thresholds")
          .accessibilityIdentifier("server-editor-alert-thresholds")
      }
      if let validation = draft.validationMessageKey {
        Text(LocalizedStringKey(validation)).foregroundStyle(.red)
      }
    }
  }

  private func thresholdField(_ threshold: ServerAlertThreshold) -> some View {
    let field = TextField(LocalizedStringKey(threshold.localizationKey), text: Binding(
      get: { draft.thresholds[threshold] ?? "" },
      set: { draft.thresholds[threshold] = $0 }
    ))
    #if os(iOS)
    return field.keyboardType(.decimalPad)
    #else
    return field
    #endif
  }
}
