import SwiftUI
import ZeroLogCore

/// First launch: what the gym has and how long a session is.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var equipment: Set<String> = []
    @State private var minutes = 45

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell ZeroLog what your gym has. It only plans exercises you can actually do there.")
                }
                EquipmentSection(types: model.catalog?.equipmentTypes ?? [], selected: $equipment)
                Section("How long do you usually train?") {
                    MinutesPicker(minutes: $minutes)
                }
                Section {
                    Button("Plan my first workout") {
                        model.updateSettings(UserSettings(equipment: equipment, minutes: minutes))
                    }
                    .disabled(equipment.isEmpty)
                } footer: {
                    if equipment.isEmpty {
                        Text("Pick at least one piece of equipment.")
                    }
                }
            }
            .navigationTitle("Your gym")
            .onAppear {
                // Start with everything ticked; most gyms have it all.
                if equipment.isEmpty {
                    equipment = Set(model.catalog?.equipmentTypes.map(\.id) ?? [])
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                EquipmentSection(types: model.catalog?.equipmentTypes ?? [], selected: setting(\.equipment))
                Section("Session length") {
                    MinutesPicker(minutes: setting(\.minutes))
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// A binding that saves straight into the user's settings.
    private func setting<Value>(_ keyPath: WritableKeyPath<UserSettings, Value>) -> Binding<Value> {
        Binding(
            get: { (model.settings ?? .fallback)[keyPath: keyPath] },
            set: { newValue in
                var updated = model.settings ?? .fallback
                updated[keyPath: keyPath] = newValue
                model.updateSettings(updated)
            }
        )
    }
}

struct EquipmentSection: View {
    let types: [EquipmentType]
    @Binding var selected: Set<String>

    var body: some View {
        Section("Equipment") {
            ForEach(types, id: \.id) { type in
                Toggle(type.name, isOn: Binding(
                    get: { selected.contains(type.id) },
                    set: { isOn in
                        if isOn { selected.insert(type.id) } else { selected.remove(type.id) }
                    }
                ))
            }
        }
    }
}

struct MinutesPicker: View {
    @Binding var minutes: Int

    var body: some View {
        Picker("Session length", selection: $minutes) {
            ForEach(AppModel.minuteOptions, id: \.self) { option in
                Text("\(option) min").tag(option)
            }
        }
    }
}
