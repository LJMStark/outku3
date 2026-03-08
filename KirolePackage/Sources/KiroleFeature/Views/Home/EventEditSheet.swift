import SwiftUI

// MARK: - Event Edit Sheet

public struct EventEditSheet: View {
    let event: CalendarEvent
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String
    @State private var notes: String

    private var isEditableSource: Bool {
        event.source == .apple || event.source == .google
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
                if !isEditableSource {
                    Section {
                        Label("Edit in \(event.source.rawValue)", systemImage: "arrow.up.forward")
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
                }
                if isEditableSource {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await appState.editEvent(
                                    event,
                                    title: title,
                                    startTime: startTime,
                                    endTime: endTime,
                                    location: location.isEmpty ? nil : location,
                                    notes: notes.isEmpty ? nil : notes
                                )
                                dismiss()
                            }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !isTimeRangeValid)
                    }
                }
            }
        }
    }
}
