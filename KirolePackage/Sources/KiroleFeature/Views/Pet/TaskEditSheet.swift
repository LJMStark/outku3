import Accessibility
import SwiftUI

public struct TaskEditSheet: View {
    let task: TaskItem
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.focusService) private var focusService
    @Environment(\.dismiss) private var dismiss

    @State private var bleService = BLEService.shared

    @State private var title: String
    @State private var priority: TaskPriority
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var notes: String
    @State private var isSaving = false
    @State private var saveError: String?

    private var dueDateValue: Binding<Date> {
        Binding(get: { dueDate ?? Date() }, set: { dueDate = $0 })
    }

    private var capabilities: TaskEditCapabilities {
        task.editCapabilities(in: TaskEditingContext(
            isDeviceConnected: bleService.connectionState.isConnected,
            activeFocusTaskID: focusService.activeSession?.taskId
        ))
    }

    private var dueDateComponents: DatePickerComponents {
        switch capabilities.dueDatePrecision {
        case .dateAndTime:
            return [.date, .hourAndMinute]
        case .dateOnly:
            return [.date]
        case .unsupported:
            return [.date]
        }
    }

    public init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _priority = State(initialValue: task.priority)
        _dueDate = State(initialValue: task.dueDate)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _notes = State(initialValue: task.notes ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let guidance = capabilities.guidance {
                    Section {
                        Label(guidance, systemImage: statusIconName)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(capabilities.accessibilityStatus)
                            .accessibilityIdentifier("TaskEdit_Status")
                    }
                }

                Section("Title") {
                    TextField("Task title", text: $title)
                        .disabled(!capabilities.isEditable || !capabilities.supportsTitle)
                }

                if capabilities.supportsPriority {
                    Section("Priority") {
                        Picker("Priority", selection: $priority) {
                            Text("Low").tag(TaskPriority.low)
                            Text("Medium").tag(TaskPriority.medium)
                            Text("High").tag(TaskPriority.high)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!capabilities.isEditable)
                    }
                }

                if capabilities.dueDatePrecision != .unsupported {
                    Section("Due Date") {
                        Toggle("Has due date", isOn: $hasDueDate)
                            .disabled(!capabilities.isEditable)
                            .onChange(of: hasDueDate) { _, newValue in
                                if newValue && dueDate == nil {
                                    dueDate = Date()
                                }
                            }
                        if hasDueDate {
                            DatePicker("Due", selection: dueDateValue, displayedComponents: dueDateComponents)
                                .disabled(!capabilities.isEditable)
                        }
                    }
                }

                if capabilities.supportsNotes {
                    Section("Notes") {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .disabled(!capabilities.isEditable)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .onChange(of: capabilities.accessibilityStatus) { oldValue, newValue in
                guard oldValue != newValue else { return }
                AccessibilityNotification.Announcement(newValue).post()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("Save Failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("TaskEdit_Cancel")
                }
                if capabilities.isEditable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Saving..." : "Save") {
                            Task {
                                await saveTask()
                            }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("TaskEdit_Save")
                    }
                }
            }
        }
    }

    private var statusIconName: String {
        if capabilities.isFocusLocked {
            return "lock.fill"
        }
        return capabilities.isEditable ? "info.circle" : "arrow.up.forward"
    }

    @MainActor
    private func saveTask() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await appState.editTask(
                task,
                title: title,
                priority: priority,
                dueDate: hasDueDate ? dueDate : nil,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
