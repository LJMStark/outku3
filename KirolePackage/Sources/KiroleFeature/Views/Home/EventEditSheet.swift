import SwiftUI

// MARK: - Event Edit Sheet

public struct EventEditSheet: View {
    let event: CalendarEvent
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var editCapabilities: EventEditCapabilities {
        event.editCapabilities(googleCalendarWriteAccess: authManager.hasCalendarWriteAccess)
    }

    private var isEditableSource: Bool {
        editCapabilities.isEditable
    }

    private var isTimeRangeValid: Bool {
        endTime > startTime
    }

    public init(event: CalendarEvent) {
        self.event = event
        _title = State(initialValue: event.title)
        _startTime = State(initialValue: event.startTime)
        _endTime = State(initialValue: event.endTime)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.description ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let guidance = editCapabilities.guidance {
                    Section {
                        Label(guidance, systemImage: "arrow.up.forward")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Title") {
                    TextField("Event title", text: $title)
                        .disabled(!isEditableSource)
                }

                Section("Time") {
                    DatePicker("Start", selection: $startTime)
                        .disabled(!isEditableSource)
                    DatePicker("End", selection: $endTime)
                        .disabled(!isEditableSource)
                    if isEditableSource && !isTimeRangeValid {
                        Text("End time must be after start time")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Location") {
                    TextField("Location", text: $location)
                        .disabled(!isEditableSource)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(!isEditableSource)
                }
            }
            .navigationTitle("Edit Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("EventEdit_Cancel")
                }
                if isEditableSource {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Saving..." : "Save") {
                            Task {
                                await saveEvent()
                            }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !isTimeRangeValid || isSaving)
                        .accessibilityIdentifier("EventEdit_Save")
                    }
                }
            }
            .alert("Save Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    @MainActor
    private func saveEvent() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await appState.editEvent(
                event,
                title: title,
                startTime: startTime,
                endTime: endTime,
                location: location.isEmpty ? nil : location,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
            return
        }
    }
}
