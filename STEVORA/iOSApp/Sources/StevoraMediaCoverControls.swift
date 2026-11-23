import SwiftUI

struct StevoraMediaCoverControls: View {
    @EnvironmentObject private var model: StevoraModel
    let entity: HAEntity
    @State private var volume: Double?

    var body: some View {
        if entity.domain == "cover" {
            HStack {
                actionButton("open", model.localized("Отвори", "Open"))
                actionButton("stop", model.localized("Спри", "Stop"))
                actionButton("close", model.localized("Затвори", "Close"))
            }
        } else if entity.domain == "media_player" {
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
