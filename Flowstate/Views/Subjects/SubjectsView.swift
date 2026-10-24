import SwiftUI
import SwiftData

struct SubjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.createdAt) private var subjects: [Subject]

    @State private var showingNew = false
    @State private var subjectToDelete: Subject?

    var body: some View {
        NavigationStack {
            Group {
                if subjects.isEmpty {
                    ContentUnavailableView {
                        Label("No subjects yet", systemImage: "square.stack")
                    } description: {
                        Text("Add the things you focus on, like Math, Reading or a side project.")
                    } actions: {
                        Button("Add subject") { showingNew = true }
                    }
                } else {
                    List {
                        ForEach(subjects) { subject in
                            NavigationLink(value: subject) {
                                SubjectRow(subject: subject)
                            }
                        }
                        .onDelete { offsets in
                            subjectToDelete = offsets.first.map { subjects[$0] }
                        }
                    }
                }
            }
            .navigationTitle("Subjects")
            .navigationDestination(for: Subject.self) { SubjectDetailView(subject: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add subject")
                }
            }
            .sheet(isPresented: $showingNew) {
                SubjectEditor(subject: nil)
            }
            .confirmationDialog(
                subjectToDelete.map { "Delete \($0.name)?" } ?? "",
                isPresented: Binding(get: { subjectToDelete != nil }, set: { if !$0 { subjectToDelete = nil } }),
                titleVisibility: .visible,
                presenting: subjectToDelete
            ) { subject in
                Button("Delete", role: .destructive) {
                    context.delete(subject)
                }
            } message: { subject in
                Text("Its \(subject.sessions.count) sessions stay in your stats as \"No subject\".")
            }
        }
    }
}

private struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(subject.color).frame(width: 10, height: 10)
            Text(subject.name)
        }
        .padding(.vertical, 2)
    }
}
