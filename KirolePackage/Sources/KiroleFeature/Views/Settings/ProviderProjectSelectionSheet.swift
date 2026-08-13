import SwiftUI

enum ProviderProjectSelectionTarget: Identifiable, Equatable {
    case todoist
    case tickTick(TickTickRegion)

    var id: String {
        switch self {
        case .todoist: "todoist"
        case .tickTick(let region): "ticktick-\(region.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .todoist: "Choose Todoist Projects"
        case .tickTick(.international): "Choose TickTick Projects"
        case .tickTick(.china): "Choose TickTick China Projects"
        }
    }

    var selectionKey: ProviderProjectSelectionKey {
        switch self {
        case .todoist: .todoist
        case .tickTick(let region): .tickTick(region)
        }
    }
}

struct ProviderProjectSelectionSheet: View {
    let target: ProviderProjectSelectionTarget

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var projects: [ProviderProjectDescriptor] = []
    @State private var selectedIdentifiers: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading projects…")
                } else if projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects Found",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Create a project in the source app, then try again.")
                    )
                } else {
                    projectList
                }
            }
            .navigationTitle(target.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isLoading || isSaving)
                }
            }
            .task { await load() }
            .alert("Project Selection", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unable to update projects.")
            }
        }
    }

    private var projectList: some View {
        List {
            Section {
                Text("Only selected projects are imported. Leaving everything unselected imports no tasks.")
                    .font(.footnote)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            Section("Projects") {
                ForEach(projects) { project in
                    Button {
                        toggle(project.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIdentifiers.contains(project.id)
                                ? "checkmark.circle.fill"
                                : "circle")
                                .foregroundStyle(selectedIdentifiers.contains(project.id)
                                    ? theme.colors.accent
                                    : theme.colors.secondaryText)
                            Text(project.name)
                                .foregroundStyle(theme.colors.primaryText)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(project.name), \(selectedIdentifiers.contains(project.id) ? "selected" : "not selected")"
                    )
                }
            }
        }
    }

    private func toggle(_ identifier: String) {
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }

    private func load() async {
        do {
            selectedIdentifiers = await appState.selectedProjectIDs(for: target.selectionKey)
            switch target {
            case .todoist:
                projects = try await appState.availableTodoistProjects()
            case .tickTick:
                projects = try await appState.availableTickTickProjects()
            }
            let available = Set(projects.map(\.id))
            selectedIdentifiers.formIntersection(available)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await appState.saveProjectSelection(selectedIdentifiers, for: target.selectionKey)
        switch target {
        case .todoist:
            await appState.syncTodoistData()
        case .tickTick:
            await appState.syncTickTickData(force: true)
        }
        let provider = target == .todoist ? "Todoist" : "TickTick"
        if let error = appState.remoteSyncErrors[provider] {
            errorMessage = error
            return
        }
        dismiss()
    }
}
