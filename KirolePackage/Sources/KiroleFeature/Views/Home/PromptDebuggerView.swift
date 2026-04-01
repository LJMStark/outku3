import SwiftUI

#if DEBUG

// MARK: - Prompt Debugger FAB

public struct PromptDebuggerFAB: View {
    @State private var isShowingDebugger = false
    @Environment(ThemeManager.self) private var theme
    
    public init() {}
    
    public var body: some View {
        Button {
            isShowingDebugger = true
        } label: {
            ZStack {
                Circle()
                    .fill(theme.colors.cardBackground)
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.colors.accent)
            }
        }
        .buttonStyle(.kiroleIcon)
        .sheet(isPresented: $isShowingDebugger) {
            PromptDebuggerSheet()
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Debugger Sheet View

enum DebugPersona: Hashable {
    case style(CompanionStyle)
    case custom

    var displayName: String {
        switch self {
        case .style(let style): return style.displayName
        case .custom: return "完全自定义 (Custom)"
        }
    }
}

struct PromptDebuggerSheet: View {
    @Bindable private var state = PromptDebuggerState.shared
    @Environment(ThemeManager.self) private var theme
    
    @State private var selectedPersona: DebugPersona = .style(.companion)
    @State private var editingDraft: String = ""
    @State private var isForceRefreshing: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 1. Selector
                Picker("Persona", selection: $selectedPersona) {
                    ForEach(CompanionStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(DebugPersona.style(style))
                    }
                    Text("完全自定义 (Custom)").tag(DebugPersona.custom)
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .onChange(of: selectedPersona) { _, newPersona in
                    loadDraft(for: newPersona)
                }
                
                // 2. Text Editor
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt Override:")
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                    
                    TextEditor(text: $editingDraft)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .background(theme.colors.background)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.colors.secondaryText.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal)
                
                HStack {
                    if case .style(let style) = selectedPersona {
                        Button("Reset to Default") {
                            editingDraft = OpenAIService.defaultPrompt(for: style)
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    } else {
                        Button("Clear") {
                            editingDraft = ""
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    
                    Spacer()
                    
                    Button("Apply Changes") {
                        if case .style(let style) = selectedPersona {
                            state.overridePrompts[style] = editingDraft
                            state.customGlobalOverride = nil
                            state.selectedMockStyle = style
                        } else {
                            state.customGlobalOverride = editingDraft
                        }
                    }
                    .font(.footnote.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.colors.accent.opacity(0.2))
                    .foregroundStyle(theme.colors.accent)
                    .clipShape(Capsule())
                }
                .padding(.horizontal)
                
                Divider()
                
                // 3. Force Refresh Action
                Button {
                    Task {
                        await forceTestGeneration()
                    }
                } label: {
                    if isForceRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text("模拟极端参数强制生成测试")
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .disabled(isForceRefreshing)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 24)


            .onAppear {
                loadDraft(for: selectedPersona)
            }
        }
    }
    
    private func loadDraft(for persona: DebugPersona) {
        switch persona {
        case .style(let style):
            if let existingOverride = state.overridePrompts[style], !existingOverride.isEmpty {
                editingDraft = existingOverride
            } else {
                editingDraft = OpenAIService.defaultPrompt(for: style)
            }
        case .custom:
            editingDraft = state.customGlobalOverride ?? ""
        }
    }
    
    private func forceTestGeneration() async {
        isForceRefreshing = true
        
        let mockContext = state.createMockContext()
        
        do {
            // Generates a mock smart reminder / companion text natively based on override
            let result = try await OpenAIService.shared.generateCompanionText(type: .smartReminder, context: mockContext)
            
            // Map the output string onto the home page's Haiku structure
            // Break it down into 3 aesthetic visual lines mimicking poetry format
            let words = result.split(separator: " ").map { String($0) }
            var lines: [String] = []
            
            if words.count >= 3 {
                let third = Int(ceil(Double(words.count) / 3.0))
                let line1 = words[0..<min(third, words.count)].joined(separator: " ")
                let line2 = words[min(third, words.count)..<min(third * 2, words.count)].joined(separator: " ")
                let line3 = words[min(third * 2, words.count)..<words.count].joined(separator: " ")
                lines = [line1, line2, line3].filter { !$0.isEmpty }
            } else {
                lines = [result] // Fallback
            }
            
            let mockHaiku = Haiku(lines: lines)
            
            await MainActor.run {
                AppState.shared.currentHaiku = mockHaiku
            }
        } catch {
            await MainActor.run {
                AppState.shared.currentHaiku = Haiku(lines: ["⚠️ Generation Failed", error.localizedDescription, "Try again."])
            }
        }
        
        isForceRefreshing = false
    }
}

#endif
