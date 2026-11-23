import SwiftUI

struct StevoraSettingsPicker: View {
    struct Choice: Identifiable {
        let id: String
        let name: String
        var detail: String = ""
    }

    @EnvironmentObject private var model: StevoraModel
    let title: String
    let choices: [Choice]
    @Binding var selection: String?
    var multiple: Binding<Set<String>>? = nil
    @State private var isSearching = false
    @State private var query = ""

    private var matches: [Choice] {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return choices }
        return choices.filter { item in
            let label = [item.name, item.id, item.detail].joined(separator: " ")
            return terms.allSatisfy { label.localizedStandardContains(String($0)) }
        }
    }

    var body: some View {
        Button {
            query = ""
            isSearching = true
        } label: {
            LabeledContent {
                Text(multiple.map { String($0.wrappedValue.count) } ?? choices.first { $0.id == selection }?.name ?? model.localized("Избери", "Choose"))
                    .foregroundStyle(Brand.cyan)
            } label: { Text(title) }
        }
        .sheet(isPresented: $isSearching) {
            NavigationStack {
                List {
                    let results = matches
                    if results.isEmpty {
                        Text(model.localized("Няма съвпадения", "No matches")).foregroundStyle(.secondary)
                    }
                    ForEach(results) { item in
                        Button {
                            if let multiple {
                                var next = multiple.wrappedValue
                                if next.contains(item.id) { next.remove(item.id) } else { next.insert(item.id) }
                                multiple.wrappedValue = next
                            } else {
                                selection = item.id
                                isSearching = false
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).foregroundStyle(.primary)
                                    if !item.detail.isEmpty {
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if multiple?.wrappedValue.contains(item.id) ?? (item.id == selection) { Image(systemName: "checkmark") }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: model.localized("Търси по име или ID", "Search by name or ID"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.localized("Затвори", "Close")) { isSearching = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    Form {
        StevoraSettingsPicker(title: "Room", choices: [.init(id: "office", name: "Office")],
                              selection: .constant(nil))
    }.environmentObject(StevoraModel())
}
