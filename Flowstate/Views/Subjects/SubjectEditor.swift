import SwiftUI
import SwiftData

/// Creates a new subject (when `subject` is nil) or edits an existing one.
struct SubjectEditor: View {
    /// Long enough for real names, short enough for the chips on the Focus tab.
    static let maxNameLength = 30

    let subject: Subject?
    var onCreate: (Subject) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allSubjects: [Subject]

    @State private var name = ""
    @State private var colorHex = SubjectPalette.hexes[0]
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        Self.normalizedName(name)
    }

    /// Another subject with the same name, ignoring case, accents and extra spaces.
    private var existingMatch: Subject? {
        allSubjects.first { $0.uuid != subject?.uuid && Self.sameName($0.name, trimmedName) }
    }

    /// Accepts names however they're typed (Postel's law): trims the ends and collapses runs
    /// of spaces, tabs or line breaks into single spaces. "  calculus   2 " → "calculus 2".
    static func normalizedName(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        normalizedName(a).compare(normalizedName(b), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private var isCustomColor: Bool {
        !SubjectPalette.hexes.contains(colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 12, height: 12)
                        TextField("Name", text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                            .onChange(of: name) { _, newName in
                                if newName.count > Self.maxNameLength {
                                    name = String(newName.prefix(Self.maxNameLength))
                                }
                            }
                    }
                } footer: {
                    if let existingMatch {
                        Text(subject == nil
                             ? "You already have \(existingMatch.name). Saving picks it instead of adding a copy."
                             : "You already have a subject called \(existingMatch.name).")
                    }
                }

                Section("Color") {
                    HStack {
                        ForEach(SubjectPalette.hexes, id: \.self) { hex in
                            Button {
                                withAnimation(Motion.snappy) { colorHex = hex }
                            } label: {
                                swatch(Circle().fill(Color(hex: hex)), isSelected: hex == colorHex)
                            }
                            .buttonStyle(.plain)
                        }

                        // System color picker (wheel, grid and sliders) for any other color.
                        ColorPicker(
                            "Custom color",
                            selection: Binding(get: { Color(hex: colorHex) }, set: { colorHex = $0.hex }),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .overlay {
                            if isCustomColor {
                                Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-4)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 6)
                    .sensoryFeedback(.selection, trigger: colorHex)
                }
            }
            .navigationTitle(subject == nil ? "New subject" : "Edit subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || (subject != nil && existingMatch != nil))
                }
            }
            .onAppear {
                if let subject {
                    name = subject.name
                    colorHex = subject.colorHex
                } else {
                    colorHex = SubjectPalette.hex(at: allSubjects.count)
                    nameFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func swatch(_ circle: some View, isSelected: Bool) -> some View {
        circle
            .frame(width: 28, height: 28)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-4)
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let subject {
            guard existingMatch == nil else { return }
            subject.name = trimmedName
            subject.colorHex = colorHex
        } else if let existingMatch {
            // Typed a name that already exists: pick that subject rather than adding a duplicate.
            onCreate(existingMatch)
        } else {
            let newSubject = Subject(name: trimmedName, colorHex: colorHex)
            context.insert(newSubject)
            onCreate(newSubject)
        }
        dismiss()
    }
}
