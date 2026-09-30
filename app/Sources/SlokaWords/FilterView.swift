import SwiftUI

struct FilterView: View {
    let sources: [Source]
    @Binding var selected: Set<String>
    @Binding var excludedLangs: Set<String>
    @Binding var collapsed: Set<String>
    let cardCount: Int
    let cardNoun: String

    private var languages: [String] {
        Array(Set(sources.map(\.lang))).sorted()
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
                ForEach(sources) { source in
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
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Text("ॐ")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.85, green: 0.33, blue: 0.08)],
                        startPoint: .top, endPoint: .bottom))
                Text("Sloka Words").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
