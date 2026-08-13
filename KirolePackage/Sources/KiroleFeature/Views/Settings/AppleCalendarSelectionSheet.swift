import SwiftUI

public struct AppleCalendarSelectionSheet: View {
    private let intent: AppleCalendarSelectionIntent

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var calendars: [AppleCalendarDescriptor] = []
    @State private var selectedIdentifiers: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    public init(intent: AppleCalendarSelectionIntent = .editExisting) {
        self.intent = intent
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading calendars…")
                } else if calendars.isEmpty {
                    ContentUnavailableView(
                        "No System Calendars",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(
                            "Add iCloud, CalDAV, Exchange, or a subscribed calendar in iOS Settings, then return here."
                        )
                    )
                } else {
                    calendarList
                }
            }
            .navigationTitle("Choose Calendars")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveSelection() }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
            .task {
                await loadCalendars()
            }
            .alert("Calendar Selection", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unable to update calendars.")
            }
        }
    }

    private var calendarList: some View {
        List {
            Section {
                Text("These calendars are read through Apple Calendar. Kirole does not store CalDAV or Exchange passwords.")
                    .font(.footnote)
                    .foregroundStyle(theme.colors.secondaryText)
            }

            ForEach(groupedAccounts, id: \.accountIdentifier) { group in
                Section(group.accountTitle) {
                    ForEach(group.calendars) { calendar in
                        Button {
                            toggle(calendar.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIdentifiers.contains(calendar.id)
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .foregroundStyle(selectedIdentifiers.contains(calendar.id)
                                        ? theme.colors.accent
                                        : theme.colors.secondaryText)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(calendar.title)
                                        .foregroundStyle(theme.colors.primaryText)
                                    Text(calendarLabel(calendar))
                                        .font(.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!calendar.isSelectable)
                        .accessibilityLabel(accessibilityLabel(calendar))
                    }
                }
            }
        }
    }

    private var groupedAccounts: [CalendarAccountGroup] {
        let grouped = Dictionary(grouping: calendars, by: \.accountIdentifier)
        return grouped.map { accountIdentifier, calendars in
            CalendarAccountGroup(
                accountIdentifier: accountIdentifier,
                accountTitle: calendars.first?.accountTitle ?? "System Account",
                calendars: calendars.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }
        .sorted { $0.accountTitle.localizedCaseInsensitiveCompare($1.accountTitle) == .orderedAscending }
    }

    private func calendarLabel(_ calendar: AppleCalendarDescriptor) -> String {
        if calendar.isReadOnly {
            return "\(calendar.sourceKind.displayName) · Read only"
        }
        return calendar.sourceKind.displayName
    }

    private func accessibilityLabel(_ calendar: AppleCalendarDescriptor) -> String {
        let state = selectedIdentifiers.contains(calendar.id) ? "selected" : "not selected"
        return "\(calendar.title), \(calendarLabel(calendar)), \(state)"
    }

    private func toggle(_ identifier: String) {
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }

    private func loadCalendars() async {
        calendars = await AppleSyncEngine.shared.availableEventCalendars()
        selectedIdentifiers = await AppleSyncEngine.shared.selectedEventCalendarIdentifiers(
            selectionMode: intent.selectionModeForLoading
        )
        isLoading = false
    }

    private func saveSelection() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await coordinator.save(selectedIdentifiers: selectedIdentifiers)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if let error = appState.remoteSyncErrors["Apple Calendar"] {
            errorMessage = error
            return
        }
        dismiss()
    }

    private var coordinator: AppleCalendarSelectionCoordinator {
        AppleCalendarSelectionCoordinator(
            intent: intent,
            actions: AppleCalendarSelectionActions(
                saveIdentifiers: { identifiers in
                    await AppleSyncEngine.shared.setSelectedEventCalendarIdentifiers(identifiers)
                },
                saveMode: { mode in
                    await AppleSyncEngine.shared.setEventCalendarSelectionMode(mode)
                },
                connectAppleCalendar: {
                    appState.updateIntegrationStatus(.appleCalendar, isConnected: true)
                },
                syncAppleCalendar: {
                    await appState.syncAppleCalendarEvents()
                }
            )
        )
    }
}

private struct CalendarAccountGroup {
    let accountIdentifier: String
    let accountTitle: String
    let calendars: [AppleCalendarDescriptor]
}
