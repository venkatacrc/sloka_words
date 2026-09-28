import SwiftUI

struct FilterView: View {
    let deck: Deck
    @Binding var selected: Set<String>
    @Binding var excludedLangs: Set<String>
    @Binding var collapsed: Set<String>
    let cardCount: Int
    let cardNoun: String

    private var languages: [String] {
        Array(Set(deck.sources.map(\.lang))).sorted()
    }

    var body: some View {
        List {
            if languages.count > 1 {
                Section("Language") {
                    ForEach(languages, id: \.self) { lang in
                        Toggle(lang.capitalized, isOn: Binding(
                            get: { !excludedLangs.contains(lang) },
                            set: { on in
                                if on { excludedLangs.remove(lang) } else { excludedLangs.insert(lang) }
                            }))
                        .toggleStyle(.checkbox)
                    }
                }
            }

            Section("Practice these") {
                ForEach(deck.sources) { source in
                    DisclosureGroup(isExpanded: Binding(
                        get: { !collapsed.contains(source.id) },
                        set: { open in
                            if open { collapsed.remove(source.id) } else { collapsed.insert(source.id) }
                        })
                    ) {
                        HStack {
                            Button("Select all") { setAll(source, on: true) }
                            Button("Clear") { setAll(source, on: false) }
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        ForEach(source.groups) { group in
                            Toggle(group.label, isOn: binding(for: GroupKey.make(source.id, group.id)))
                                .toggleStyle(.checkbox)
                        }
                    } label: {
                        Text(source.title).font(.headline)
                    }
                    .disabled(excludedLangs.contains(source.lang))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("\(cardCount) \(cardNoun) selected")
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.bar)
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(key) },
            set: { on in
                if on { selected.insert(key) } else { selected.remove(key) }
            })
    }

    private func setAll(_ source: Source, on: Bool) {
        for group in source.groups {
            let key = GroupKey.make(source.id, group.id)
            if on { selected.insert(key) } else { selected.remove(key) }
        }
    }
}
