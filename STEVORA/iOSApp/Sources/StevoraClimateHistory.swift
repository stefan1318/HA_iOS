import Charts
import SwiftUI

struct StevoraClimateHistory: View {
    @EnvironmentObject private var model: StevoraModel
    let temperature: HAEntity?
    let humidity: HAEntity?
    @State private var hours = 24
    @State private var series: [String: [Point]] = [:]
    @State private var loading = false
    @State private var failed = false

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private var sensors: [HAEntity] { [temperature, humidity].compactMap { $0 } }

    var body: some View {
        if !sensors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.localized("История на климата", "Climate history")).font(.headline)
                Picker(model.localized("Период", "Period"), selection: $hours) {
                    ForEach([6, 24, 72], id: \.self) { Text("\($0) h").tag($0) }
                }.pickerStyle(.segmented)
                if loading {
                    ProgressView()
                } else if failed {
                    Text(model.localized("Историята е недостъпна", "History is unavailable"))
                } else {
                    ForEach(sensors) { sensor in
                        Text(model.displayName(sensor) + " · " + (sensor.attributes.unit_of_measurement ?? ""))
                            .font(.caption)
                        if let points = series[sensor.id], !points.isEmpty {
                            Chart(points) { point in
                                LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
                                    .foregroundStyle(Brand.cyan)
                            }.frame(height: 100)
                        } else {
                            Text(model.localized("Няма измервания за периода", "No readings in this period")).font(.caption)
                        }
                    }
                }
            }
            .padding(19).modifier(StevoraGlassCard())
            .task(id: sensors.map(\.id).joined(separator: "|") + String(hours)) { await load() }
        }
    }

    private func load() async {
        loading = true
        failed = false
        series = [:]
        defer { if !Task.isCancelled { loading = false } }
        do {
            let api = StevoraAssistantGateway(address: model.address, token: model.token, allowLocalHTTP: model.allowLocalHTTP)
            let end = Date()
            let iso = ISO8601DateFormatter()
            let result = try await api.adminRequest("history/history_during_period", fields: [
                "start_time": iso.string(from: end.addingTimeInterval(-Double(hours) * 3600)),
                "end_time": iso.string(from: end), "entity_ids": sensors.map(\.id),
                "minimal_response": true, "no_attributes": true
            ])
            try Task.checkCancellation()
            for sensor in sensors {
                let entries = result[sensor.id] as? [[String: Any]] ?? []
                series[sensor.id] = entries.compactMap { entry in
                    guard let state = entry["s"] as? String, let value = Double(state), value.isFinite,
                          let time = entry["lu"] as? Double else { return nil }
                    return Point(date: Date(timeIntervalSince1970: time), value: value)
                }.suffix(600).map { $0 }
            }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

#Preview {
    StevoraClimateHistory(temperature: nil, humidity: nil).environmentObject(StevoraModel())
}
