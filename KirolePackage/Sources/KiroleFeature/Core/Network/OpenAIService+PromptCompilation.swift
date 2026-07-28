import Foundation

extension OpenAIService {
    func compileScreensaverPrompt(
        isPostcard: Bool,
        usageDays: Int,
        workContext: String,
        profileContext: String
    ) -> (systemPrompt: String, userPrompt: String) {
        let tool = Self.promptTool("screensaver")
        let userPrompt: String

        if isPostcard {
            userPrompt = KirolePromptSpec.render(
                Self.promptTemplate(tool.userPromptTemplates, named: "postcard"),
                values: [
                    "usageDays": String(usageDays),
                    "profileContext": PromptSanitizer.userContent(profileContext, maxLen: 300),
                    "workContext": PromptSanitizer.userContent(workContext, maxLen: 300)
                ]
            )
        } else {
            userPrompt = KirolePromptSpec.render(
                Self.promptTemplate(tool.userPromptTemplates, named: "resting"),
                values: [
                    "profileContext": PromptSanitizer.userContent(profileContext, maxLen: 300),
                    "workContext": PromptSanitizer.userContent(workContext, maxLen: 300)
                ]
            )
        }
        return (
            systemPrompt: PromptSanitizer.systemPrompt(
                containingUserContent: tool.systemPromptTemplate
            ),
            userPrompt: userPrompt
        )
    }

    func compileScreensaverPromptForFixture(
        isPostcard: Bool,
        usageDays: Int,
        workContext: String,
        profileContext: String
    ) -> (systemPrompt: String, userPrompt: String) {
        compileScreensaverPrompt(
            isPostcard: isPostcard,
            usageDays: usageDays,
            workContext: workContext,
            profileContext: profileContext
        )
    }

    func compileTranslationPrompt(
        text: String
    ) -> (systemPrompt: String, userPrompt: String) {
        let tool = Self.promptTool("translation")
        return (
            systemPrompt: PromptSanitizer.systemPrompt(
                containingUserContent: tool.systemPromptTemplate
            ),
            userPrompt: KirolePromptSpec.render(
                Self.promptTemplate(tool.userPromptTemplates, named: "default"),
                values: ["text": PromptSanitizer.userContent(text, maxLen: 500)]
            )
        )
    }

    func compileTranslationPromptForFixture(
        text: String
    ) -> (systemPrompt: String, userPrompt: String) {
        compileTranslationPrompt(text: text)
    }

    func compileTaskOverviewPrompt(
        notes: String
    ) -> (systemPrompt: String, userPrompt: String) {
        let tool = Self.promptTool("taskOverview")
        return (
            systemPrompt: PromptSanitizer.systemPrompt(
                containingUserContent: tool.systemPromptTemplate
            ),
            userPrompt: KirolePromptSpec.render(
                Self.promptTemplate(tool.userPromptTemplates, named: "default"),
                values: ["notes": PromptSanitizer.userContent(notes, maxLen: 300)]
            )
        )
    }

    func compileTaskOverviewPromptForFixture(
        notes: String
    ) -> (systemPrompt: String, userPrompt: String) {
        compileTaskOverviewPrompt(notes: notes)
    }

    func compileDaySummaryPrompt(
        eventDigest: [String]
    ) -> (systemPrompt: String, userPrompt: String) {
        let tool = Self.promptTool("daySummary")
        let eventsText: String
        if eventDigest.isEmpty {
            eventsText = Self.promptTemplate(tool.userPromptTemplates, named: "empty")
        } else {
            eventsText = KirolePromptSpec.render(
                Self.promptTemplate(tool.userPromptTemplates, named: "events"),
                values: [
                    "eventDigest": eventDigest
                        .prefix(KirolePromptSpec.document.limits.scheduleEventCount)
                        .joined(separator: "; ")
                ]
            )
        }
        return (
            systemPrompt: PromptSanitizer.systemPrompt(
                containingUserContent: tool.systemPromptTemplate
            ),
            userPrompt: PromptSanitizer.userContent(eventsText, maxLen: 400)
        )
    }

    func compileDaySummaryPromptForFixture(
        eventDigest: [String]
    ) -> (systemPrompt: String, userPrompt: String) {
        compileDaySummaryPrompt(eventDigest: eventDigest)
    }

    func compileSettlementReviewPrompt(
        eventDigest: [String],
        deadlineTitles: [String],
        focusMinutes: Int,
        tasksCompleted: Int,
        tasksTotal: Int
    ) -> (systemPrompt: String, userPrompt: String) {
        let tool = Self.promptTool("settlementReview")
        let instructions = KirolePromptSpec.render(
            tool.systemPromptTemplate,
            values: [
                "deadlineInstruction": deadlineTitles.isEmpty
                    ? ""
                    : "\nYou MUST mention the deadline item(s) listed in the facts.",
                "focusInstruction": focusMinutes > DayPackGenerator.focusMentionThresholdMinutes
                    ? "\nYou MUST state the total focus time exactly as given in the facts."
                    : ""
            ]
        )
        let eventFacts = eventDigest.isEmpty
            ? "No events were scheduled today."
            : "Today's events: " + eventDigest
                .prefix(KirolePromptSpec.document.limits.scheduleEventCount)
                .joined(separator: "; ")
        let deadlineFacts = deadlineTitles.isEmpty
            ? ""
            : "Deadline items: " + deadlineTitles
                .prefix(KirolePromptSpec.document.limits.deadlineTitleCount)
                .joined(separator: "; ")
        let focusFacts = focusMinutes > 0
            ? "\nTotal focus time: \(DayPackGenerator.focusDurationLabel(minutes: focusMinutes))."
            : ""
        let facts = KirolePromptSpec.render(
            Self.promptTemplate(tool.userPromptTemplates, named: "default"),
            values: [
                "eventFacts": eventFacts,
                "deadlineFacts": deadlineFacts,
                "tasksCompleted": String(tasksCompleted),
                "tasksTotal": String(tasksTotal),
                "focusFacts": focusFacts
            ]
        )

        return (
            systemPrompt: PromptSanitizer.systemPrompt(containingUserContent: instructions),
            userPrompt: PromptSanitizer.userContent(facts, maxLen: 500)
        )
    }

    func compileSettlementReviewPromptForFixture(
        eventDigest: [String],
        deadlineTitles: [String],
        focusMinutes: Int,
        tasksCompleted: Int,
        tasksTotal: Int
    ) -> (systemPrompt: String, userPrompt: String) {
        compileSettlementReviewPrompt(
            eventDigest: eventDigest,
            deadlineTitles: deadlineTitles,
            focusMinutes: focusMinutes,
            tasksCompleted: tasksCompleted,
            tasksTotal: tasksTotal
        )
    }

    func compilePromptForFixture(
        type: AITextType,
        context: AIContext
    ) async -> (systemPrompt: String, userPrompt: String) {
        (
            systemPrompt: await buildCompanionSystemPrompt(context: context),
            userPrompt: buildCompanionUserPrompt(type: type, context: context)
        )
    }

    var haikuSystemPrompt: String {
        PromptSanitizer.systemPrompt(
            containingUserContent: Self.promptTool("haiku").systemPromptTemplate
        )
    }

    func buildHaikuPrompt(context: HaikuContext) -> String {
        let hour = Calendar.current.component(.hour, from: context.currentTime)
        let timeContext: String
        if hour < 6 {
            timeContext = " in the early morning hours"
        } else if hour < 12 {
            timeContext = " starting their morning"
        } else if hour < 17 {
            timeContext = " in the afternoon"
        } else if hour < 21 {
            timeContext = " in the evening"
        } else {
            timeContext = " winding down for the night"
        }

        var taskContext = ""
        if context.tasksCompletedToday > 0 {
            taskContext += " who has completed \(context.tasksCompletedToday) task(s) today"
        }
        if context.totalTasksToday > 0 {
            let remaining = context.totalTasksToday - context.tasksCompletedToday
            taskContext += remaining > 0
                ? " with \(remaining) task(s) remaining"
                : " and finished all their tasks"
        }

        let moodContext = context.petMood.map {
            ". Their pet companion is feeling \($0.rawValue.lowercased())"
        } ?? ""
        let sceneContext = context.currentSceneName.map {
            ". Their E-ink companion display shows the '\(PromptSanitizer.sanitize($0, maxLen: 50))' scene. Use imagery from this scene in the haiku"
        } ?? ""
        let tool = Self.promptTool("haiku")
        let rendered = KirolePromptSpec.render(
            Self.promptTemplate(tool.userPromptTemplates, named: "default"),
            values: [
                "timeContext": timeContext,
                "taskContext": taskContext,
                "moodContext": moodContext,
                "sceneContext": sceneContext
            ]
        )
        return PromptSanitizer.userContent(rendered, maxLen: 1_000)
    }

    func compileHaikuPromptForFixture(
        context: HaikuContext
    ) -> (systemPrompt: String, userPrompt: String) {
        (
            systemPrompt: haikuSystemPrompt,
            userPrompt: buildHaikuPrompt(context: context)
        )
    }
}
