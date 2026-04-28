import SwiftUI

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
                .injectAppEnvironment()
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
            ScrollView {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("宠物对话模型 (实时生效):")
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)

                    Menu {
                        ForEach(OpenAIService.companionModelOptions) { option in
                            Button {
                                state.selectedCompanionModelID = option.id
                            } label: {
                                if option.id == state.selectedCompanionModelID {
                                    Label("\(option.displayName)（当前）", systemImage: "checkmark")
                                } else {
                                    Text(option.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                            Text("切换模型")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(theme.colors.accent.opacity(0.16))
                        .foregroundStyle(theme.colors.accent)
                        .clipShape(Capsule())
                    }

                    Text("当前模型代号: \(state.selectedCompanionModelID)")
                        .font(.caption2)
                        .foregroundStyle(theme.colors.secondaryText)
                        .textSelection(.enabled)

                    if let selectedModel = OpenAIService.companionModelOptions.first(where: { $0.id == state.selectedCompanionModelID }) {
                        Text(selectedModel.note)
                            .font(.caption2)
                            .foregroundStyle(theme.colors.secondaryText.opacity(0.9))
                    }
                }
                .padding(.horizontal)
                
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
                
                // 3. User Defined Learn Text (Test)
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 语气/词汇附加学习 (实时生效):")
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                    
                    TextField("你想让它学舌的话，如: 喵喵喵~", text: $state.testLearnText)
                        .font(.system(size: 14))
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
                
                VStack(spacing: 12) {
                    Text("模拟生成测试")
                        .font(.headline)
                    
                    HStack {
                        Button { Task { await forceTestGeneration(type: .morningGreeting) } } label: { Text("早安问候") }
                        Button { Task { await forceTestGeneration(type: .taskEncouragement) } } label: { Text("任务鼓励") }
                        Button { Task { await forceTestGeneration(type: .scheduleReminder) } } label: { Text("日程提醒") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isForceRefreshing)

                    HStack {
                        Button { Task { await forceTestGeneration(type: .settlementSummary) } } label: { Text("日终结算") }
                        Button { Task { await forceTestGeneration(type: .smartReminder) } } label: { Text("闲置/随机提醒") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isForceRefreshing)
                    
                    if isForceRefreshing {
                        ProgressView().controlSize(.small)
                            .padding(.top, 4)
                    } else if !state.lastGeneratedDialogue.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(state.lastMockSummary)
                                .font(.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.colors.background)
                                .cornerRadius(6)
                            
                            Text("生成结果:")
                                .font(.caption.bold())
                                .foregroundStyle(theme.colors.secondaryText)
                            
                            CompanionDialogueView(
                                state.lastGeneratedDialogue,
                                color: theme.colors.primaryText
                            )
                            .padding()
                            .background(theme.colors.accent.opacity(0.1))
                            .cornerRadius(8)
                            
                            if !state.lastGeneratedTranslation.isEmpty {
                                Text("中文翻译:")
                                    .font(.caption.bold())
                                    .foregroundStyle(theme.colors.secondaryText)
                                    .padding(.top, 4)
                                
                                Text(state.lastGeneratedTranslation)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.colors.primaryText)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.colors.accent.opacity(0.05))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal)
                
                    Spacer()
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
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
    
    private func forceTestGeneration(type: AITextType = .smartReminder) async {
        isForceRefreshing = true
        await MainActor.run { state.lastGeneratedTranslation = "" }
        
        // Pass the requested type into the context builder so it reflects the phase accurately
        let styleOverride: CompanionStyle?
        switch selectedPersona {
        case .style(let style):
            styleOverride = style
        case .custom:
            styleOverride = nil
        }

        let mockContext = await state.createMockContext(type: type, styleOverride: styleOverride)

        let result = await CompanionTextService.shared.previewSharedPetDialogue(baseContext: mockContext, type: type)
        let translation = (try? await OpenAIService.shared.translateCompanionText(text: result)) ?? "翻译失败"
        
        await MainActor.run {
            state.lastGeneratedDialogue = result
            state.lastGeneratedTranslation = translation
            
            // Still update the main UI bubble so they can see how it looks rendered in the HomeView
            AppState.shared.currentPetDialogue = result
            AppState.shared.switchHomeToPetDialogue()
        }
        
        isForceRefreshing = false
    }
}
