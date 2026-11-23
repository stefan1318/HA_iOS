import CoreLocation
import SwiftUI

struct StevoraPresenceSettings: View {
    @EnvironmentObject private var model: StevoraModel
    @ObservedObject var presence: StevoraPresence
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(model.localized("Споделяне на местоположение", "Share location"),
                   isOn: Binding(get: { presence.enabled }, set: presence.setEnabled))
                .disabled(!presence.ready)
            Text(model.localized("Изпраща местоположението на този iPhone към активния дом за присъствие и автоматизации.",
                                 "Send this iPhone’s location to the active home for presence and automations."))
                .font(.caption).foregroundStyle(Brand.muted)
            if presence.enabled {
                if presence.authorization == .denied || presence.authorization == .restricted {
                    Button(model.localized("Разрешения в iOS", "Location permissions in iOS")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else {
                    Toggle(model.localized("Обновявай и във фонов режим", "Update in the background"),
                           isOn: Binding(get: { presence.background }, set: presence.setBackground))
                        .disabled(presence.authorization == .notDetermined)
                    if presence.background && presence.authorization != .authorizedAlways {
                        Button(model.localized("За фон избери „Винаги“ в iOS", "Choose Always in iOS for background updates")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    Button(model.localized("Обнови локацията сега", "Update location now")) { presence.requestUpdate() }
                    if let last = presence.lastSent {
                        Text(model.localized("Последно изпращане", "Last sent") + " · " + last.formatted())
                            .font(.caption)
                    }
                }
                if presence.failed {
                    Text(model.localized("Неуспешно обновяване. Провери връзката и Mobile App интеграцията в дома.",
                                         "Update failed. Check the connection and the home’s Mobile App integration."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }.padding(19).modifier(StevoraGlassCard())
    }
}

#Preview {
    StevoraPresenceSettings(presence: StevoraPresence()).environmentObject(StevoraModel())
}
