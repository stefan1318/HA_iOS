import SwiftUI

// Native STEVORA iOS 26 design, sharing layout and semantic tokens with Android 2.1.
enum Brand {
    static let background = Color(red: 8/255, green: 19/255, blue: 31/255)
    static let surface = Color(red: 18/255, green: 36/255, blue: 55/255)
    static let raised = Color(red: 25/255, green: 49/255, blue: 71/255)
    static let cyan = Color(red: 39/255, green: 185/255, blue: 245/255)
    static let light = Color(red: 244/255, green: 250/255, blue: 255/255)
    static let muted = Color(red: 166/255, green: 188/255, blue: 205/255)
    static let mint = Color(red: 76/255, green: 224/255, blue: 179/255)
    static let border = Color(red: 41/255, green: 69/255, blue: 90/255)
}

struct StevoraGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(Brand.surface.opacity(0.43), in: RoundedRectangle(cornerRadius: 24))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Brand.border, lineWidth: 1))
        }
    }
}

struct StevoraTouchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.spring(response: 0.27, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

private struct StevoraBackdrop: View {
    @State private var glow = false
    var body: some View {
        ZStack {
            Brand.background
            LinearGradient(
                colors: [Brand.raised.opacity(0.75), Brand.background, Color(red: 0.02, green: 0.045, blue: 0.09)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(Brand.cyan.opacity(glow ? 0.14 : 0.035))
                .frame(width: 430, height: 430)
                .blur(radius: 100)
                .offset(x: glow ? 110 : -120, y: -240)
                .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: glow)
        }
        .ignoresSafeArea()
        .onAppear { glow = true }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: StevoraModel
    var body: some View {
        Group {
            if model.connected { StevoraDashboard() }
            else { StevoraOnboarding() }
        }
        .preferredColorScheme(.dark)
        .tint(Brand.cyan)
    }
}

private struct StevoraOnboarding: View {
    @EnvironmentObject private var model: StevoraModel
    @State private var showToken = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    Image("StevoraLogo").resizable().scaledToFit()
                        .frame(width: 112, height: 112)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 38)
                    Text("STEVORA")
                        .font(.system(size: 35, weight: .black, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Brand.light)
                    Text(model.localized("Твоят дом. Твоят интелект.", "Your home. Your intelligence."))
                        .font(.headline).foregroundStyle(Brand.cyan)
                    VStack(alignment: .leading, spacing: 15) {
                        TextField("https://your-home-hub.example", text: $model.address)
                            .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                            .textContentType(.URL)
                        DisclosureGroup(model.localized("Разширени настройки: тестов токен", "Advanced: test token"), isExpanded: $showToken) {
                            SecureField(model.localized("Токен за достъп", "Access token"), text: $model.token)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        Text(model.localized("Избери защитен вход с акаунта си или токен за тестова инсталация.",
                                             "Use secure account sign-in or a token for development installs."))
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                    .padding(20).modifier(StevoraGlassCard())
                    Button {
                        Task { await model.signIn() }
                    } label: {
                        Label(model.localized("Вход в STEVORA", "Sign in to STEVORA"), systemImage: "lock.shield")
                            .fontWeight(.bold).frame(maxWidth: .infinity).padding(15)
                            .background(Brand.cyan, in: RoundedRectangle(cornerRadius: 17))
                            .foregroundStyle(Brand.background)
                    }
                    .buttonStyle(StevoraTouchStyle()).disabled(model.busy || model.address.isEmpty)
                    Button {
                        Task { await model.connect() }
                    } label: {
                        Text(model.localized("Свържи с токен", "Connect with token"))
                            .frame(maxWidth: .infinity).padding(13)
                    }
                    .disabled(model.busy || model.address.isEmpty || model.token.isEmpty)
                    if model.busy { ProgressView().tint(Brand.cyan).frame(maxWidth: .infinity) }
                    if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
                }.padding(23)
            }
            .background(StevoraBackdrop())
        }
    }
}

private enum StevoraTab: String, CaseIterable {
    case home, rooms, climate, assistant, more
    var icon: String {
        switch self {
        case .home: "house.fill"
        case .rooms: "square.grid.2x2.fill"
        case .climate: "thermometer.medium"
        case .assistant: "waveform.circle.fill"
        case .more: "ellipsis.circle.fill"
        }
    }
    @MainActor
    func label(_ model: StevoraModel) -> String {
        switch self {
        case .home: model.localized("Начало", "Home")
        case .rooms: model.localized("Помещения", "Rooms")
        case .climate: model.localized("Климат", "Climate")
        case .assistant: "STEVORA AI"
        case .more: model.localized("Още", "More")
        }
    }
}

// Capability-based device discovery. Never assume the test home's entity IDs or room names.
private let controllableDomains: Set<String> = ["light", "switch", "fan", "climate", "media_player", "cover", "lock"]

private struct StevoraDashboard: View {
    @EnvironmentObject private var model: StevoraModel
    @State private var selected: StevoraTab = .home
    @State private var selectedRoom = "all"
    private var entityLookup: [String: HAEntity] {
        Dictionary(uniqueKeysWithValues: model.entities.map { ($0.id, $0) })
    }
    private var controls: [HAEntity] {
        model.entities.filter { controllableDomains.contains($0.domain)
            && !$0.id.lowercased().contains("backlight") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var deviceGroups: [String] {
        ["all"] + Array(Set(controls.map(\.domain))).sorted()
    }
    private func groupLabel(_ domain: String) -> String {
        switch domain {
        case "all": return model.localized("Всички", "All")
        case "light": return model.localized("Осветление", "Lights")
        case "climate": return model.localized("Климат", "Climate")
        case "fan": return model.localized("Вентилатори", "Fans")
        case "switch": return model.localized("Ключове", "Switches")
        case "media_player": return model.localized("Медия", "Media")
        case "cover": return model.localized("Щори", "Covers")
        case "lock": return model.localized("Брави", "Locks")
        default: return domain.capitalized
        }
    }
    private var temperatureSensor: HAEntity? {
        model.entities.first { $0.domain == "sensor" &&
            $0.attributes.device_class == "temperature" &&
            Double($0.state) != nil }
    }
    private var humiditySensor: HAEntity? {
        model.entities.first { $0.domain == "sensor" &&
            $0.attributes.device_class == "humidity" &&
            Double($0.state) != nil }
    }
    private var homepodTemperature: String {
        temperatureSensor?.state ?? model.entities.first(where: {
            $0.domain == "climate" && $0.attributes.current_temperature != nil
        }).flatMap { $0.attributes.current_temperature.map { String(format: "%.1f", $0) } } ?? "—"
    }
    private var homepodHumidity: String { humiditySensor?.state ?? "—" }

    var body: some View {
        TabView(selection: $selected) {
            ForEach(StevoraTab.allCases, id: \.self) { tab in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 21) {
                            banner
                            Group {
                                switch tab {
                                case .home: home
                                case .rooms: rooms
                                case .climate: climate
                                case .assistant: StevoraAssistView().frame(minHeight: 570)
                                case .more: more
                                }
                            }
                            if let error = model.error {
                                Text(error).font(.footnote).foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .padding(.bottom, 95)
                    }
                    .background(StevoraBackdrop())
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { Task { await model.refresh() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel(model.localized("Обнови", "Refresh"))
                        }
                    }
                    .refreshable { await model.refresh() }
                }
                .tabItem { Label(tab.label(model), systemImage: tab.icon) }
                .tag(tab)
            }
        }
        .tint(Brand.cyan)
    }

    private var banner: some View {
        HStack(spacing: 12) {
            Image("StevoraLogo")
                .resizable().scaledToFit().frame(width: 61, height: 61)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text("STEVORA")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .tracking(3).foregroundStyle(Brand.light)
                Label(model.localized("Системата е свързана", "Home Hub connected"),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Brand.mint)
            }
            Spacer()
        }.padding(.vertical, 7)
    }

    private func section(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).tracking(2.3).foregroundStyle(Brand.cyan)
            Text(subtitle).font(.footnote).foregroundStyle(Brand.muted)
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 19) {
            section(model.localized("МОЯТ ДОМ", "MY HOME"),
                    subtitle: model.localized("Жив преглед на STEVORA", "Your live home overview"))
            climateCenter
            HStack(spacing: 12) {
                metric(model.localized("СВЕТЛИНИ", "LIGHTS ON"),
                       value: String(controls.filter { $0.domain == "light" && $0.state == "on" }.count),
                       symbol: "lightbulb.fill")
                metric(model.localized("УСТРОЙСТВА", "DEVICES"),
                       value: String(controls.count), symbol: "square.grid.2x2")
            }
            section(model.localized("БЪРЗ ДОСТЪП", "QUICK ACCESS"),
                    subtitle: model.localized("Управление с едно докосване", "One-tap native controls"))
            HStack(spacing: 12) {
                shortcut(model.localized("Помещения", "Rooms"), icon: "square.grid.2x2.fill", target: .rooms)
                shortcut("STEVORA AI", icon: "waveform.circle.fill", target: .assistant)
            }
            section(model.localized("ИЗБРАНИ УСТРОЙСТВА", "FAVORITE DEVICES"),
                    subtitle: model.localized("Твоите избрани контроли", "Your selected controls"))
            ForEach(controls.filter { model.favorites.contains($0.id) }) { entity in
                StevoraDeviceCard(entity: entity, name: entity.name)
            }
        }
    }

    private var climateCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CLIMATE CENTER").font(.headline)
                    Text(model.localized("Данни от наличните датчици", "Available sensor readings"))
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                Image(systemName: "thermometer.sun.fill").foregroundStyle(Brand.cyan)
            }
            HStack(spacing: 20) {
                ZStack {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(Brand.border, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    Circle().trim(from: 0, to: 0.75 * gaugeProgress)
                        .stroke(AngularGradient(colors: [Brand.cyan, Brand.mint, .orange],
                                                center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: gaugeProgress)
                    VStack(spacing: 1) {
                        Text(homepodTemperature == "—" ? "—" : homepodTemperature + "°")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("ROOM TEMP").font(.system(size: 9, weight: .semibold))
                            .tracking(1).foregroundStyle(Brand.muted)
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 19) {
                    HStack {
                        Image(systemName: "humidity.fill").foregroundStyle(Brand.cyan)
                        VStack(alignment: .leading) {
                            Text(model.localized("Влажност", "Humidity")).font(.caption).foregroundStyle(Brand.muted)
                            Text(homepodHumidity == "—" ? "—" : homepodHumidity + "%").font(.title3.bold())
                        }
                    }
                    HStack {
                        Image(systemName: "air.conditioner.horizontal.fill").foregroundStyle(Brand.cyan)
                        VStack(alignment: .leading) {
                            Text(model.localized("Режим", "Mode")).font(.caption).foregroundStyle(Brand.muted)
                            Text(model.entities.first(where: { $0.domain == "climate" })?.state ?? "—").font(.headline)
                        }
                    }
                }
            }
            Button {
                withAnimation(.spring()) { selected = .climate }
            } label: {
                HStack {
                    Text(model.localized("Климатичен контрол", "Climate controls"))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.font(.subheadline.bold()).foregroundStyle(Brand.cyan)
            }.buttonStyle(StevoraTouchStyle())
        }
        .padding(20)
        .modifier(StevoraGlassCard())
    }
    private var gaugeProgress: CGFloat {
        guard let value = Double(homepodTemperature) else { return 0 }
        return CGFloat(max(0, min(1, (value - 10) / 25)))
    }
    private func metric(_ label: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Brand.cyan)
            Text(value).font(.title2.bold()).contentTransition(.numericText())
            Text(label).font(.system(size: 10, weight: .medium))
                .tracking(1).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17).modifier(StevoraGlassCard())
    }
    private func shortcut(_ label: String, icon: String, target: StevoraTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = target }
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: icon).font(.title2).foregroundStyle(Brand.cyan)
                Text(label).font(.subheadline.bold()).foregroundStyle(Brand.light)
                Image(systemName: "arrow.up.right").foregroundStyle(Brand.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(19)
            .modifier(StevoraGlassCard())
        }.buttonStyle(StevoraTouchStyle())
    }

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 17) {
            section(model.localized("УСТРОЙСТВА", "DEVICES"),
                    subtitle: model.localized("Автоматично открити контроли", "Automatically discovered controls"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(deviceGroups, id: \.self) { group in
                        Button(groupLabel(group)) {
                            withAnimation(.easeInOut(duration: 0.28)) { selectedRoom = group }
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 17).padding(.vertical, 11)
                        .background(selectedRoom == group ? Brand.cyan : Brand.surface, in: Capsule())
                        .foregroundStyle(selectedRoom == group ? Brand.background : Brand.light)
                    }
                }.padding(.vertical, 4)
            }
            ForEach(controls.filter { selectedRoom == "all" || $0.domain == selectedRoom }) { entity in
                StevoraDeviceCard(entity: entity, name: entity.name)
            }
            if controls.isEmpty {
                Text(model.localized("Няма открити управляеми устройства", "No controllable devices discovered"))
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    private var climate: some View {
        VStack(alignment: .leading, spacing: 17) {
            section("CLIMATE CENTER", subtitle: model.localized("Мониторинг и управление", "Monitor and control"))
            climateCenter
            HStack(spacing: 12) {
                metric(model.localized("ТЕМПЕРАТУРА", "TEMPERATURE"),
                       value: homepodTemperature == "—" ? "—" : homepodTemperature + "°C", symbol: "thermometer.medium")
                metric(model.localized("ВЛАЖНОСТ", "HUMIDITY"),
                       value: homepodHumidity == "—" ? "—" : homepodHumidity + "%", symbol: "humidity.fill")
            }
            ForEach(controls.filter { $0.domain == "climate" }) { device in
                StevoraDeviceCard(entity: device, name: device.name)
            }
        }
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(model.localized("КОНТРОЛЕН ЦЕНТЪР", "CONTROL CENTER"),
                    subtitle: model.localized("Автоматизации и настройки", "Routines and settings"))
            VStack(alignment: .leading, spacing: 13) {
                Text(model.localized("Сцени и автоматизации", "Scenes and automations"))
                    .font(.headline)
                ForEach(model.entities.filter {
                    ["scene", "script", "automation"].contains($0.domain)
                    && !$0.id.lowercased().contains("backlight")
                }) { entity in
                    HStack(spacing: 9) {
                        Image(systemName: "play.square.stack.fill").foregroundStyle(Brand.cyan)
                        Text(entity.name).lineLimit(2)
                        Spacer()
                        Button {
                            Task { await model.runRoutine(entity) }
                        } label: {
                            Image(systemName: "play.circle.fill").font(.title2)
                        }.accessibilityLabel(model.localized("Стартирай", "Run"))
                    }
                    .padding(.vertical, 6)
                }
            }.padding(19).modifier(StevoraGlassCard())
            VStack(alignment: .leading, spacing: 15) {
                Text(model.localized("Език", "Language")).font(.headline)
                Picker("Language", selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) }
                )) {
                    Text("Български").tag("bg")
                    Text("English").tag("en")
                }.pickerStyle(.segmented)
                Text(model.address).font(.caption).foregroundStyle(Brand.muted)
                Text(model.connectionMode).font(.caption).foregroundStyle(Brand.muted)
                Button(role: .destructive) { model.logout() } label: {
                    Label(model.localized("Изход от профила", "Sign out"),
                          systemImage: "rectangle.portrait.and.arrow.right")
                }
            }.padding(19).modifier(StevoraGlassCard())
        }
    }
}

private struct StevoraDeviceCard: View {
    @EnvironmentObject private var model: StevoraModel
    let entity: HAEntity
    let name: String
    @State private var expanded = false
    @State private var brightness = 50.0
    @State private var red = 255.0
    @State private var green = 100.0
    @State private var blue = 100.0

    private var symbol: String {
        switch entity.domain {
        case "light": "lightbulb.fill"
        case "fan": "fanblades.fill"
        case "climate": "air.conditioner.horizontal"
        case "media_player": "tv"
        default: "switch.2"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Brand.cyan)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(entity.state).font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 4)
                Button { model.toggleFavorite(entity.id) } label: {
                    Image(systemName: model.favorites.contains(entity.id) ? "star.fill" : "star")
                        .foregroundStyle(Brand.cyan)
                }
                .accessibilityLabel("Favorite")
                if ["light", "fan", "switch"].contains(entity.domain) {
                    Button {
                        Task { await model.toggle(entity) }
                    } label: {
                        Image(systemName: entity.state == "on" ? "power.circle.fill" : "power.circle")
                            .font(.title2).foregroundStyle(Brand.cyan)
                    }.accessibilityLabel(entity.state == "on" ? "Turn off" : "Turn on")
                }
            }
            if entity.domain == "climate", let target = entity.attributes.temperature {
                HStack(spacing: 14) {
                    Text(model.localized("Зададена", "Target") + ": \(Int(target))°C")
                        .font(.subheadline)
                    Spacer()
                    Button { Task { await model.setTemperature(entity, value: max(entity.attributes.min_temp ?? 7, target - 1)) } } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                    }
                    Button { Task { await model.setTemperature(entity, value: min(entity.attributes.max_temp ?? 35, target + 1)) } } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }.foregroundStyle(Brand.cyan)
            }
            if entity.domain == "climate" {
                if let modes = entity.attributes.hvac_modes, !modes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.localized("Режим", "Mode")).font(.caption).foregroundStyle(Brand.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(modes, id: \.self) { mode in
                                    Button(model.localized([
                                        "off": "Изключен", "heat": "Отопление",
                                        "cool": "Охлаждане", "dry": "Изсушаване",
                                        "fan_only": "Вентилатор", "auto": "Автоматично",
                                        "heat_cool": "Автоматичен климат"
                                    ][mode] ?? mode, mode)) {
                                        Task { await model.setClimateMode(entity, mode: mode) }
                                    }
                                        .buttonStyle(.bordered)
                                        .tint(entity.state == mode ? Brand.cyan : Brand.muted)
                                }
                            }
                        }
                    }
                }
                if let modes = entity.attributes.fan_modes, !modes.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.localized("Вентилатор", "Fan speed")).font(.caption).foregroundStyle(Brand.muted)
                        Picker("Fan", selection: Binding(
                            get: { entity.attributes.fan_mode ?? modes[0] },
                            set: { value in Task { await model.setFanMode(entity, mode: value) } }
                        )) {
                            ForEach(modes, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu)
                    }
                }
                if let presets = entity.attributes.preset_modes, !presets.isEmpty {
                    Picker("Preset", selection: Binding(
                        get: { entity.attributes.preset_mode ?? presets[0] },
                        set: { value in Task { await model.setPresetMode(entity, mode: value) } }
                    )) {
                        ForEach(presets, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                }
            }
            if entity.domain == "light" {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { expanded.toggle() }
                } label: {
                    HStack {
                        Text(model.localized("Яркост и цвят", "Brightness & color"))
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.font(.caption).foregroundStyle(Brand.muted)
                }.buttonStyle(StevoraTouchStyle())
                if expanded {
                    HStack(spacing: 10) {
                        Image(systemName: "sun.min").foregroundStyle(Brand.cyan)
                        Slider(value: $brightness, in: 1...100, step: 1) { editing in
                            if !editing { Task { await model.setBrightness(entity, value: brightness) } }
                        }
                        Image(systemName: "sun.max").foregroundStyle(Brand.cyan)
                    }
                    if entity.attributes.supported_color_modes?.contains(where: {
                        ["rgb", "rgbw", "rgbww", "hs", "xy"].contains($0)
                    }) == true {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.localized("RGB цвят", "RGB color")).font(.caption)
                            HStack {
                                Text("R").foregroundStyle(.red)
                                Slider(value: $red, in: 0...255, step: 1)
                            }
                            HStack {
                                Text("G").foregroundStyle(.green)
                                Slider(value: $green, in: 0...255, step: 1)
                            }
                            HStack {
                                Text("B").foregroundStyle(.blue)
                                Slider(value: $blue, in: 0...255, step: 1)
                            }
                            Button(model.localized("Приложи цвят", "Apply color")) {
                                Task { await model.setColor(entity, rgb: [Int(red), Int(green), Int(blue)]) }
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                    if let effects = entity.attributes.effect_list, !effects.isEmpty {
                        Picker("Effect", selection: Binding(
                            get: { entity.attributes.effect ?? effects[0] },
                            set: { value in Task { await model.setLightEffect(entity, effect: value) } }
                        )) {
                            ForEach(effects, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu)
                    }
                    if entity.attributes.supported_color_modes?.contains(where: { ["rgb", "rgbw", "rgbww", "hs", "xy"].contains($0) }) == true {
                        HStack(spacing: 13) {
                            colorDot(.red, rgb: [255, 0, 0])
                            colorDot(.pink, rgb: [255, 25, 130])
                            colorDot(.blue, rgb: [0, 100, 255])
                            colorDot(.white, rgb: [255, 255, 255])
                        }
                    }
                }
            }
        }
        .padding(19)
        .modifier(StevoraGlassCard())
        .onAppear { updateBrightness(); updateRGB() }
        .onChange(of: entity.attributes.brightness) { _ in updateBrightness() }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expanded)
    }
    private func updateRGB() {
        if let rgb = entity.attributes.rgb_color, rgb.count == 3 {
            red = Double(rgb[0]); green = Double(rgb[1]); blue = Double(rgb[2])
        }
    }
    private func updateBrightness() {
        if let level = entity.attributes.brightness {
            brightness = min(100, max(1, Double(level) * 100 / 255))
        }
    }
    private func colorDot(_ color: Color, rgb: [Int]) -> some View {
        Button {
            Task { await model.setColor(entity, rgb: rgb) }
        } label: {
            Circle().fill(color).frame(width: 30, height: 30)
                .overlay(Circle().stroke(Brand.light.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(StevoraTouchStyle())
        .accessibilityLabel("Set light color")
    }
}
