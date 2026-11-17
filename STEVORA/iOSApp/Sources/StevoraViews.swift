import SwiftUI

private enum StevoraStyle {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.09)
    static let panel = Color(red: 0.085, green: 0.12, blue: 0.18)
    static let accent = Color(red: 0.22, green: 0.82, blue: 0.91)
}

struct RootView: View {
    @EnvironmentObject private var model: StevoraModel

    var body: some View {
        Group {
            if model.connected {
                DashboardView()
            } else {
                OnboardingView()
            }
        }
        .background(StevoraStyle.background.ignoresSafeArea())
        .tint(StevoraStyle.accent)
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var model: StevoraModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 32)
                    Text("STEVORA")
                        .font(.system(size: 43, weight: .black, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(StevoraStyle.accent)
                    Text(model.localized("Интелигентен дом, изцяло под твой контрол",
                                         "Your smart home, in your control"))
                        .font(.headline)
                    Text(model.localized("Свържи своя Home Assistant сървър",
                                         "Connect your Home Assistant server"))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("https://your-server.example", text: $model.address)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                            .accessibilityLabel("Server URL")
                        SecureField(model.localized("Дългосрочен токен за достъп",
                                                     "Long-lived access token"), text: $model.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text(model.localized("За първоначалните тестове използвай токен от профила си в Home Assistant. Той се пази в iOS Keychain. Преди публична версия ще бъде заменен с OAuth onboarding.",
                                             "For development, use a Home Assistant profile access token. It is stored in iOS Keychain. OAuth onboarding is required before public release."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(StevoraStyle.panel, in: RoundedRectangle(cornerRadius: 20))
                    Button {
                        Task { await model.signIn() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.busy { ProgressView().tint(.black) }
                            Label(model.localized("Вход със STEVORA", "Sign in to STEVORA"), systemImage: "lock.shield")
                                .fontWeight(.bold)
                            Spacer()
                        }.padding(14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StevoraStyle.accent)
                    .foregroundStyle(.black)
                    .disabled(model.busy || model.address.isEmpty)
                    Button {
                        Task { await model.connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.busy { ProgressView().tint(.black) }
                            Text(model.localized("Свържи STEVORA", "Connect STEVORA"))
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StevoraStyle.accent)
                    .foregroundStyle(.black)
                    .disabled(model.busy || model.token.isEmpty || model.address.isEmpty)
                    if let error = model.error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
                .padding(24)
            }
            .background(StevoraStyle.background)
        }
    }
}

private enum Screen: String, CaseIterable {
    case home, rooms, climate, lights, routines, assist, settings
    @MainActor
    func label(_ model: StevoraModel) -> String {
        switch self {
        case .home: model.localized("Начало", "Home")
        case .rooms: model.localized("Устройства", "Devices")
        case .climate: model.localized("Климат", "Climate")
        case .lights: model.localized("Светлини", "Lights")
        case .routines: model.localized("Сцени", "Scenes")
        case .assist: "Assist"
        case .settings: model.localized("Настройки", "Settings")
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .rooms: "square.grid.2x2.fill"
        case .climate: "thermometer.medium"
        case .lights: "lightbulb.fill"
        case .routines: "play.square.stack.fill"
        case .assist: "waveform.circle.fill"
        case .settings: "gearshape.fill"
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var model: StevoraModel

    var body: some View {
        TabView {
            ForEach(Screen.allCases, id: \.self) { screen in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            if screen == .home { homeSummary }
                            if screen == .rooms { roomSelector }
                            if let error = model.error {
                                Text(error).font(.footnote).foregroundStyle(.red)
                            }
                            if screen == .assist {
                                StevoraAssistView().frame(minHeight: 520)
                            } else if screen == .settings {
                                settings
                            } else {
                                let items = filtered(screen)
                                if items.isEmpty {
                                    Label(model.localized("Няма налични устройства", "No devices available"), systemImage: screen.symbol)
                                        .foregroundStyle(.secondary)
                                        .padding(20)
                                } else {
                                    LazyVStack(spacing: 12) {
                                        ForEach(items) { entity in
                                            DeviceTile(entity: entity)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(18)
                    }
                    .background(StevoraStyle.background)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await model.refresh() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel(model.localized("Обнови", "Refresh"))
                        }
                    }
                    .refreshable { await model.refresh() }
                }
                .tabItem { Label(screen.label(model), systemImage: screen.symbol) }
            }
        }
        .tint(StevoraStyle.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STEVORA")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(StevoraStyle.accent)
            Label(model.localized("Системата е свързана", "System connected"),
                  systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var homeSummary: some View {
        HStack(spacing: 12) {
            summaryTile("thermometer", title: model.localized("Температура", "Temperature"),
                        value: model.entities.first(where: { $0.id.contains("homepod_temperature") })?.state ?? "—", unit: "°C")
            summaryTile("humidity", title: model.localized("Влажност", "Humidity"),
                        value: model.entities.first(where: { $0.id.contains("homepod_humidity") })?.state ?? "—", unit: "%")
        }
    }

    private func summaryTile(_ icon: String, title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.cyan)
            Text(value + unit).font(.title2.bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(StevoraStyle.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var roomSelector: some View {
        let rooms = Array(Set(model.entities.compactMap { entity -> String? in
            let name = entity.name
            return name.contains(" ") ? String(name.split(separator: " ").first ?? "") : nil
        })).sorted()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                roomButton(model.localized("Всички", "All"), id: "all")
                roomButton("★", id: "favorites")
                ForEach(rooms, id: \.self) { room in roomButton(room, id: room) }
            }
        }
    }

    private func roomButton(_ title: String, id: String) -> some View {
        Button(title) { model.selectedRoom = id }
            .buttonStyle(.bordered)
            .tint(model.selectedRoom == id ? .cyan : .gray)
    }

    private func filtered(_ screen: Screen) -> [HAEntity] {
        let visible = model.entities.filter { !$0.id.localizedCaseInsensitiveContains("backlight") }
        switch screen {
        case .home:
            return visible.filter { ["climate", "light", "sensor"].contains($0.domain) }
                .prefix(14).map { $0 }
        case .rooms:
            return visible.filter {
                guard ["light", "switch", "fan", "climate"].contains($0.domain) else { return false }
                if model.selectedRoom == "favorites" { return model.favorites.contains($0.id) }
                if model.selectedRoom == "all" { return true }
                return $0.name.localizedCaseInsensitiveContains(model.selectedRoom)
            }
        case .climate:
            return visible.filter {
                $0.domain == "climate" ||
                ($0.domain == "sensor" &&
                 ($0.id.localizedCaseInsensitiveContains("temperature") ||
                  $0.id.localizedCaseInsensitiveContains("humidity") ||
                  $0.id.localizedCaseInsensitiveContains("humudity")))
            }
        case .lights: return visible.filter { $0.domain == "light" }
        case .routines: return visible.filter { ["scene", "script", "automation"].contains($0.domain) }
        case .assist, .settings: return []
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.localized("Език", "Language")).font(.headline)
            Picker("Language", selection: Binding(
                get: { model.language },
                set: { model.setLanguage($0) }
            )) {
                Text("Български").tag("bg")
                Text("English").tag("en")
            }
            .pickerStyle(.segmented)
            Text(model.address).font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive) { model.logout() } label: {
                Label(model.localized("Изход", "Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StevoraStyle.panel, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct DeviceTile: View {
    @EnvironmentObject private var model: StevoraModel
    let entity: HAEntity
    @State private var brightness = 50.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(StevoraStyle.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName).font(.headline).lineLimit(2)
                    Text(entity.state + (entity.attributes.unit_of_measurement ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.toggleFavorite(entity.id) } label: {
                    Image(systemName: model.favorites.contains(entity.id) ? "star.fill" : "star")
                }.accessibilityLabel("Favorite")
                if ["scene", "script", "automation"].contains(entity.domain) {
                    Button {
                        Task { await model.runRoutine(entity) }
                    } label: { Image(systemName: "play.circle.fill").font(.title2) }
                    .accessibilityLabel(model.localized("Стартирай", "Run"))
                }
                if ["light", "switch", "fan"].contains(entity.domain) {
                    Button {
                        Task { await model.toggle(entity) }
                    } label: {
                        Image(systemName: entity.state == "on" ? "power.circle.fill" : "power.circle")
                            .font(.title2)
                    }
                    .accessibilityLabel(entity.state == "on" ? "Turn off" : "Turn on")
                }
            }
            if entity.domain == "climate", let target = entity.attributes.temperature {
                HStack {
                    Text(model.localized("Зададена", "Target") + ": \(Int(target))°C")
                    Spacer()
                    Button {
                        Task { await model.setTemperature(entity, value: target - 1) }
                    } label: { Image(systemName: "minus.circle") }
                    Button {
                        Task { await model.setTemperature(entity, value: target + 1) }
                    } label: { Image(systemName: "plus.circle") }
                }
                .font(.subheadline)
            }
            if entity.domain == "light", entity.state == "on" {
                HStack {
                    Text(model.localized("Яркост", "Brightness"))
                    Slider(value: $brightness, in: 1...100, step: 1) { editing in
                        if !editing { Task { await model.setBrightness(entity, value: brightness) } }
                    }
                }
                .font(.caption)
                .onAppear { syncBrightness() }
                .onChange(of: entity.attributes.brightness) { _ in syncBrightness() }
            }
        }
        .padding(16)
        .background(StevoraStyle.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func syncBrightness() {
        if let b = entity.attributes.brightness {
            brightness = max(1, min(100, Double(b) / 255 * 100))
        }
    }

    private var displayName: String {
        if entity.attributes.friendly_name != nil { return entity.name }
        let suffix = entity.id.split(separator: ".").last.map(String.init) ?? entity.id
        return suffix.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var icon: String {
        switch entity.domain {
        case "light": "lightbulb"
        case "climate": "thermometer.medium"
        case "switch": "switch.2"
        case "fan": "fanblades"
        case "scene", "script", "automation": "play.square.stack"
        default: "waveform.path.ecg"
        }
    }
}
