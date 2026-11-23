import SwiftUI

struct StevoraMediaCoverControls: View {
    @EnvironmentObject private var model: StevoraModel
    let entity: HAEntity
    @State private var volume: Double?

    var body: some View {
        let attr = entity.attributes
        if entity.domain == "light", let lo = attr.min_color_temp_kelvin, let hi = attr.max_color_temp_kelvin {
            number("color_temp", "color_temp_kelvin", model.localized("Цветна температура (K)", "Color temperature (K)"),
                   value: attr.color_temp_kelvin, min: lo, max: hi)
        }
        if entity.domain == "fan" {
            number("percentage", "percentage", model.localized("Скорост (%)", "Speed (%)"), value: attr.percentage)
            choices("direction", model.localized("Посока", "Direction"), ["forward", "reverse"])
            choices("preset_mode", model.localized("Профил", "Preset"), attr.preset_modes)
            if model.allows(entity, "oscillate"), let active = attr.oscillating {
                Toggle(model.localized("Осцилация", "Oscillation"), isOn: Binding(get: { active }, set: { value in
                    Task { await model.setDetailValue(entity, action: "oscillate", field: "oscillating", value: value) }
                }))
            }
        }
        if entity.domain == "climate" {
            choices("swing_mode", model.localized("Жалузи", "Swing"), attr.swing_modes)
        }
        if entity.domain == "cover" {
            number("position", "position", model.localized("Позиция (%)", "Position (%)"), value: attr.current_position)
            number("tilt", "tilt_position", model.localized("Наклон (%)", "Tilt (%)"), value: attr.current_tilt_position)
            HStack {
                actionButton("open", model.localized("Отвори", "Open"))
                actionButton("stop", model.localized("Спри", "Stop"))
                actionButton("close", model.localized("Затвори", "Close"))
            }
        } else if entity.domain == "media_player" {
            choices("source", model.localized("Източник", "Source"), attr.source_list)
            actionButton("play_pause", model.localized("Пусни / пауза", "Play / pause"))
            if model.allows(entity, "volume"), let level = entity.attributes.volume_level {
                Slider(value: Binding(get: { volume ?? min(1, max(0, level)) }, set: { volume = $0 }),
                       in: 0...1, onEditingChanged: { editing in
                    if !editing, let value = volume {
                        volume = nil
                        Task { await model.mediaOrCover(entity, action: "volume", volume: value) }
                    }
                }).accessibilityLabel(model.localized("Сила на звука", "Volume"))
            }
        }
    }

    @State private var edits: [String: Double] = [:]

    @ViewBuilder
    private func number(_ action: String, _ field: String, _ label: String, value: Int?, min lower: Int = 0, max upper: Int = 100) -> some View {
        if model.allows(entity, action), lower < upper {
            let current = edits[action] ?? Double(min(upper, max(lower, value ?? lower)))
            Text(label + " · " + (edits[action] != nil || value != nil ? String(Int(current)) : "—")).font(.caption)
            Slider(value: Binding(get: { current }, set: { edits[action] = $0 }), in: Double(lower)...Double(upper), step: 1) { editing in
                if !editing, let selected = edits.removeValue(forKey: action) {
                    Task { await model.setDetailValue(entity, action: action, field: field, value: Int(selected)) }
                }
            }
        }
    }

    @ViewBuilder
    private func choices(_ action: String, _ label: String, _ values: [String]?) -> some View {
        if model.allows(entity, action), let values, !values.isEmpty {
            Menu(label) {
                ForEach(values, id: \.self) { value in
                    Button(value) { Task { await model.setDetailValue(entity, action: action, field: action, value: value) } }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: String, _ title: String) -> some View {
        if model.allows(entity, action) {
            Button(title) { Task { await model.mediaOrCover(entity, action: action) } }.buttonStyle(.bordered)
        }
    }
}

#Preview {
    if let entity = try? JSONDecoder().decode(HAEntity.self, from: Data(#"{"entity_id":"cover.preview","state":"closed","attributes":{}}"#.utf8)) {
        StevoraMediaCoverControls(entity: entity).environmentObject(StevoraModel())
    }
}
