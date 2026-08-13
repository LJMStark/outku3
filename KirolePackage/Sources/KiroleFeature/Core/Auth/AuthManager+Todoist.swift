import Foundation

@MainActor
extension AuthManager {
    public func connectTodoist() async throws {
        let components = try makeTodoistComponents()
        todoistAuthService = components.auth
        todoistCredentialManager = components.credentials
        let operation = try components.auth.beginCredentialOperation()
        defer { components.auth.endCredentialOperation(operation) }
        _ = try await components.auth.authorize()
        try components.auth.validateCredentialOperation(operation)
        // Keep durable writes until the new token has identified its account. The sync engine
        // retries them for the same account and quarantines them when the account changed.
        isTodoistConnected = true
    }

    public func getTodoistAccessToken() async throws -> String {
        let components = try makeTodoistComponents()
        todoistAuthService = components.auth
        todoistCredentialManager = components.credentials
        return try await components.credentials.accessToken()
    }

    public func disconnectTodoist() async throws {
        let components: (auth: TodoistAuthService, credentials: TodoistCredentialManager)?
        if let todoistAuthService, let todoistCredentialManager {
            components = (todoistAuthService, todoistCredentialManager)
        } else if todoistComponentFactoryOverride != nil {
            components = try makeTodoistComponents()
        } else {
            components = try? makeTodoistComponents()
        }
        let credentialGate = components?.auth.credentialGate
            ?? todoistCredentialOperationGate
        let preparedCleanup = todoistPreparedSignOutCleanup.flatMap { cleanup in
            credentialGate.accepts(cleanup) ? cleanup : nil
        }
        let cleanup = preparedCleanup
            ?? components?.auth.invalidateAndBlockCredentialOperations()
            ?? credentialGate.invalidateAndBlock()
        do {
            if let credentials = components?.credentials {
                try await credentials.clearCredentials(after: cleanup)
            } else {
                try await credentialGate.waitForInvalidatedOperations(before: cleanup)
                guard credentialGate.accepts(cleanup) else {
                    throw TodoistAuthError.operationInvalidated
                }
                let store = TodoistKeychainTokenStore()
                try await store.clear()
                guard try await store.load() == nil else {
                    throw TodoistAuthError.credentialDeletionFailed
                }
            }
            isTodoistConnected = false
            if let todoistDisconnectSyncResetOverride {
                try await todoistDisconnectSyncResetOverride()
            } else {
                try await TodoistSyncEngine.shared.reset()
            }
            if let todoistDisconnectProjectCleanupOverride {
                try await todoistDisconnectProjectCleanupOverride()
            } else {
                let projectStore = ProviderProjectSelectionStore.shared
                await projectStore.clear(.todoist)
                guard await projectStore.selectedProjectIDs(for: .todoist).isEmpty else {
                    throw TodoistAuthError.credentialDeletionFailed
                }
            }
        } catch {
            credentialGate.fail(cleanup)
            throw error
        }
        if preparedCleanup != nil {
            todoistPreparedSignOutCleanupCompleted = true
        } else {
            todoistAuthService = nil
            todoistCredentialManager = nil
            credentialGate.complete(cleanup)
        }
    }

    /// A global sign-out may stop before normal provider cleanup begins. Drain any credential
    /// write already inside its store, then remove the token before reopening this provider.
    func finishAbortedTodoistSignOut(
        _ cleanup: OAuthCredentialCleanupTicket,
        credentialGate: OAuthCredentialOperationGate
    ) async throws {
        do {
            try await credentialGate.waitForInvalidatedOperations(before: cleanup)
            guard credentialGate.accepts(cleanup) else {
                throw TodoistAuthError.operationInvalidated
            }

            if let todoistCredentialManager,
               todoistCredentialManager.credentialGate === credentialGate {
                try await todoistCredentialManager.clearCredentials(after: cleanup)
            } else {
                let store = TodoistKeychainTokenStore()
                try await store.clear()
                guard try await store.load() == nil else {
                    throw TodoistAuthError.credentialDeletionFailed
                }
            }
            isTodoistConnected = false
            todoistPreparedSignOutCleanupCompleted = true
        } catch {
            credentialGate.fail(cleanup)
            throw error
        }
    }

    func makeTodoistComponents() throws -> (
        auth: TodoistAuthService,
        credentials: TodoistCredentialManager
    ) {
        if let todoistComponentFactoryOverride {
            return try todoistComponentFactoryOverride()
        }
        if let auth = todoistAuthService, let credentials = todoistCredentialManager {
            return (auth, credentials)
        }
        guard let clientID = AppSecrets.todoistClientId,
              let redirectURI = URL(string: "https://kirole.681023.xyz/oauth/todoist-callback") else {
            throw TodoistAuthError.invalidConfiguration
        }
        let configuration = try TodoistOAuthConfiguration(
            clientID: clientID,
            redirectURI: redirectURI
        )
        let gate = todoistCredentialOperationGate
        let credentials = TodoistCredentialManager(
            configuration: configuration,
            credentialGate: gate
        )
        return (
            TodoistAuthService(
                configuration: configuration,
                credentialManager: credentials,
                credentialGate: gate
            ),
            credentials
        )
    }
}
