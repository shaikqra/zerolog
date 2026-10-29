import SwiftUI
import ZeroLogCore

/// First launch: what the gym has and how long a session is.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var equipment: Set<String> = []
    @State private var minutes = 45
    @State private var unit = UserSettings.fallback.unit

    var body: some View {
        NavigationStack {
            Form {
                Text("Tell ZeroLog what your gym has. It only plans exercises you can actually do there.")
                    .font(.ui(17))
                    .foregroundStyle(Color.textSecondary)
                    .listRowBackground(Color.clear)
                EquipmentSection(types: model.catalog?.equipmentTypes ?? [], selected: $equipment)
                Section {
                    MinutesPicker(minutes: $minutes)
                } header: {
                    SectionTitle("How long do you usually train?")
                }
                .listRowBackground(Color.surface)
                Section {
                    UnitPicker(unit: $unit)
                } header: {
                    SectionTitle("Weights in")
                }
                .listRowBackground(Color.surface)
            }
            .darkList()
            .navigationTitle("Your gym")
            .safeAreaInset(edge: .bottom) {
                Button("Plan my first workout") {
                    model.updateSettings(UserSettings(equipment: equipment, minutes: minutes, unit: unit))
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(20)
                .disabled(equipment.isEmpty)
            }
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
                Section {
                    MinutesPicker(minutes: setting(\.minutes))
                } header: {
                    SectionTitle("Session length")
                }
                .listRowBackground(Color.surface)
                Section {
                    UnitPicker(unit: setting(\.unit))
                } header: {
                    SectionTitle("Weights in")
                } footer: {
                    Text("Past workouts convert automatically.")
                        .font(.ui(14))
                        .foregroundStyle(Color.textTertiary)
                }
                .listRowBackground(Color.surface)
            }
            .darkList()
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
        Section {
            ForEach(types, id: \.id) { type in
                Toggle(type.name, isOn: Binding(
                    get: { selected.contains(type.id) },
                    set: { isOn in
                        if isOn { selected.insert(type.id) } else { selected.remove(type.id) }
                    }
                ))
                .font(.ui(17))
                .tint(Color.done)
            }
        } header: {
            SectionTitle("Equipment")
        } footer: {
            if selected.isEmpty {
                Text("Pick at least one piece of equipment.")
                    .font(.ui(14))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .listRowBackground(Color.surface)
    }
}

struct UnitPicker: View {
    @Binding var unit: WeightUnit

    var body: some View {
        Picker("Weights in", selection: $unit) {
            Text("kg").tag(WeightUnit.kg)
            Text("lb").tag(WeightUnit.lb)
        }
        .pickerStyle(.segmented)
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
        .font(.ui(17))
    }
}
