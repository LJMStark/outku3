import Foundation

// MARK: - Event Support Text Service

/// 日程支持性文字服务：为当天每条日程生成一句「进行中」支持性文案，随 DayPack Events[]
/// 的 SupportText 字段下发硬件（协议 §4.7）。固件按当前时间自行决定显示哪条——App 只提供
/// 每条日程各自的文案，不猜"现在是哪一条"。
///
/// 六类各有独立生成规则（prompt tool `eventSupportText`）：深度工作只指向最小第一步、会议给
/// 轻量准备提示、行政琐事框成自我小挑战、硬性死线安抚不加压、健康关怀温和提醒、休息充电
/// 给许可不派任务。分类本身由 `EventCategoryService` 先算好——本服务只按已定类别取角度。
///
/// - 缓存：结果按「标题|描述|类别」键做内存缓存，同一事件跨 BLE sync 轮（白天每小时）不
///   重复调 LLM；仅内存——支持性文字是廉价可再生数据，进程重启后首轮重生成即回填。
///   **类别进 key**：异步分类晚到（先 `.admin` 兜底、下轮 AI 升级为 `.deadline`）时必须
///   重新生成，否则死线事件会一直显示行政琐事的"小挑战"口吻。
/// - 兜底链：AI 不可用/出错/回复对不齐 → 按类别取 `FallbackText.eventSupportText` 模板池
///   → 永不返回空串（空串上 wire 固件不渲染这行，等于功能消失）。模板兜底**不缓存**；
///   AI 调用失败或任一条验收失败后冷却 10 分钟再重试；合格条目仍会缓存。
@MainActor
public final class EventSupportTextService {
    public static let shared = EventSupportTextService()

    private let openAI = OpenAIService.shared
    private var cache: [String: String] = [:]
    private var aiRetryAfter: Date?
    /// Task cache keys with a prewarm request currently in flight.
    ///
    /// `prewarmTaskSupportText` is fired unawaited once per DayPack generation, and syncs can
    /// overlap (a hardware `0x20` arriving mid-sync, a forced sync right after a scheduled one).
    /// Without this set the second call would re-request titles the first is still fetching —
    /// duplicate paid tokens for an identical answer. Entries are removed in a `defer`, so a
    /// throwing or cancelled request cannot wedge a title permanently.
    private var inFlightTaskKeys: Set<String> = []
    /// 缓存上限：当天事件 ≤8 条，正常远够；防的是长期运行下的无界增长。
    private static let cacheLimit = 512
    nonisolated static let aiFailureCooldown: TimeInterval = 10 * 60

    struct AIReplyEvaluation: Sendable, Equatable {
        let acceptedLines: [String?]
        let retryAfter: Date?
    }

    private init() {}

    /// Returns `summaries` with `supportText` filled: cached hits first, ONE batched AI call for
    /// the misses, per-category template fallback for whatever AI could not fill.
    ///
    /// Call this AFTER `EventCategoryService.categorized(_:)` — the category decides which rule
    /// the line follows, so an uncategorized input would generate against the wrong angle.
    public func withSupportText(_ summaries: [EventSummary]) async -> [EventSummary] {
        guard !summaries.isEmpty else { return [] }

        // Density is a property of the whole day, not of one event, so compute it once from the full
        // snapshot (times included) and hand it to every pending line. Same rule as the box② day
        // summary, so the panel and the support lines never disagree about whether today was busy.
        let isDayPacked = FallbackText.isDayBusy(summaries)

        // Density joins the cache key. A Wellness line generated on a packed day may open with
        // "busy stretch today"; reusing it after the user clears their calendar would state
        // something untrue — the same reasoning that puts category in the key.
        var resolved: [String?] = summaries.map {
            cache[Self.cacheKey(for: $0, isDayPacked: isDayPacked)]
        }
        let pendingIndices = resolved.indices.filter { resolved[$0] == nil }

        if !pendingIndices.isEmpty,
           Self.isAIRetryAllowed(retryAfter: aiRetryAfter, now: Date()),
           await openAI.isConfigured {
            let pendingEvents = pendingIndices.map {
                OpenAIService.EventSupportTextInput(
                    title: Self.generationText(for: summaries[$0]),
                    category: summaries[$0].category,
                    isDayPacked: isDayPacked
                )
            }
            do {
                let lines = try await openAI.generateEventSupportTexts(events: pendingEvents)
                let evaluation = Self.evaluateAIReply(
                    lines,
                    expectedCount: pendingIndices.count,
                    maxBytes: DayPackTextBudget.eventSupportText,
                    now: Date()
                )
                aiRetryAfter = evaluation.retryAfter
                if cache.count > Self.cacheLimit { cache.removeAll() }
                for (offset, index) in pendingIndices.enumerated() {
                    let line = evaluation.acceptedLines[offset]
                    resolved[index] = line
                    // 只缓存 wire-safe 的 AI 文案；失败条目当轮走稳定模板兜底。
                    if let line {
                        cache[Self.cacheKey(for: summaries[index], isDayPacked: isDayPacked)] = line
                    }
                }
                if evaluation.retryAfter != nil {
                    let rejectedCount = evaluation.acceptedLines.count(where: { $0 == nil })
                    Log.ai.warning("Event support text AI returned \(rejectedCount, privacy: .public) rejected line(s) — falling back to category templates; retrying AI in 10 minutes")
                }
            } catch {
                aiRetryAfter = Date().addingTimeInterval(Self.aiFailureCooldown)
                Log.ai.warning("Event support text AI failed (\(error.localizedDescription, privacy: .private)) — falling back to category templates for \(pendingIndices.count, privacy: .public) event(s); retrying in 10 minutes")
            }
        }

        return zip(summaries, resolved).map { summary, line in
            let seed = Self.cacheKey(for: summary, isDayPacked: isDayPacked)
            return summary.withSupportText(
                line ?? FallbackText.eventSupportText(
                    for: summary.category, seed: seed, isDayPacked: isDayPacked
                )
            )
        }
    }

    /// The support line for a task the user opened with the hardware button (`0x11` TaskInPage
    /// `Encouragement`, §4.8). `TaskItem` carries no category — the six classes only exist on
    /// calendar events — so the client fixed this to the **Deep Work** rule.
    ///
    /// **Synchronous by contract.** The device is already parked on the task detail page waiting
    /// for this frame, and with no notes `taskOverview` returns instantly, so an awaiting support
    /// line would be the only thing between the button press and the screen — up to
    /// `model.requestTimeoutSeconds` (60 s) of blank page. The AI wording is produced ahead of time
    /// by `prewarmTaskSupportText`; here we only read that cache, falling back to the deterministic
    /// template on a miss. Never returns an empty string: an empty line renders nothing at all.
    public func cachedOrFallbackTaskSupportText(taskTitle: String) -> String {
        cache[Self.taskCacheKey(for: taskTitle)]
            ?? FallbackText.eventSupportText(for: .deepWork, seed: taskTitle)
    }

    /// Warms the cache for the tasks the device can actually open.
    ///
    /// The hardware Overview only lists `DayPack.topTasks`, so a button press can only ever name
    /// one of those — generating their lines during sync (already off the critical path) turns the
    /// `0x11` path into a cache hit. Runs as ONE batched call for all of them.
    ///
    /// Silent on failure: this is a latency optimisation, and `cachedOrFallbackTaskSupportText`
    /// already degrades to the template.
    ///
    /// Skips titles already being fetched by an earlier, still-running prewarm — overlapping syncs
    /// otherwise pay twice for the same answer (see `inFlightTaskKeys`).
    func prewarmTaskSupportText(taskTitles: [String]) async {
        let missing = taskTitles.filter {
            let key = Self.taskCacheKey(for: $0)
            return cache[key] == nil && !inFlightTaskKeys.contains(key)
        }
        guard !missing.isEmpty,
              Self.isAIRetryAllowed(retryAfter: aiRetryAfter, now: Date()) else { return }

        // Claim BEFORE the first suspension point. `@MainActor` only guarantees exclusivity between
        // awaits: two overlapping prewarms both run the filter above, and if the claim happened
        // after `await openAI.isConfigured` each would resume believing it owned the same titles —
        // the duplicate request this set exists to prevent. `defer` releases on every exit path,
        // including a throw or a cancellation, so a title can never stay wedged.
        let claimedKeys = Set(missing.map(Self.taskCacheKey(for:)))
        inFlightTaskKeys.formUnion(claimedKeys)
        defer { inFlightTaskKeys.subtract(claimedKeys) }

        guard await openAI.isConfigured else { return }

        do {
            let lines = try await openAI.generateEventSupportTexts(
                events: missing.map {
                    OpenAIService.EventSupportTextInput(title: $0, category: .deepWork)
                }
            )
            let evaluation = Self.evaluateAIReply(
                lines, expectedCount: missing.count,
                maxBytes: DayPackTextBudget.taskSupportText,
                now: Date()
            )
            aiRetryAfter = evaluation.retryAfter
            if cache.count > Self.cacheLimit { cache.removeAll() }
            for (title, line) in zip(missing, evaluation.acceptedLines) {
                if let line { cache[Self.taskCacheKey(for: title)] = line }
            }
        } catch {
            aiRetryAfter = Date().addingTimeInterval(Self.aiFailureCooldown)
            Log.ai.warning("Task support text prewarm failed (\(error.localizedDescription, privacy: .private)) — button presses will use the Deep Work template; retrying in 10 minutes")
        }
    }

    /// Task keys carry a distinct prefix so a task and a calendar event sharing a title do not
    /// share an entry — they are generated against different byte budgets (80B vs 120B).
    private static func taskCacheKey(for taskTitle: String) -> String {
        "task\u{1F}" + taskTitle
    }

    /// Pure acceptance policy shared by production and tests. Sanitization happens before byte
    /// enforcement so transformations that expand text (for example `…` -> `...`) cannot exceed
    /// the field budget. Any rejected item cools the batch down, while valid siblings remain usable.
    nonisolated static func evaluateAIReply(
        _ lines: [String], expectedCount: Int, maxBytes: Int, now: Date
    ) -> AIReplyEvaluation {
        let acceptedLines = (0..<expectedCount).map { index -> String? in
            guard lines.indices.contains(index) else { return nil }
            return accepted(lines[index], maxBytes: maxBytes)
        }
        let hasFailure = lines.count != expectedCount || acceptedLines.contains(where: { $0 == nil })
        return AIReplyEvaluation(
            acceptedLines: acceptedLines,
            retryAfter: hasFailure ? now.addingTimeInterval(aiFailureCooldown) : nil
        )
    }

    private nonisolated static func accepted(_ raw: String, maxBytes: Int) -> String? {
        let sanitized = raw.asciiSanitizedForEInk()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = CompanionTextService.enforceByteBudget(sanitized, maxBytes: maxBytes)
        let containsEmoji = raw.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x7E)
        }
        let containsASCIIAlphaNumeric = text.utf8.contains {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
        }
        guard !text.isEmpty,
              containsASCIIAlphaNumeric,
              isExactlyOneCompleteSentence(text),
              !text.localizedCaseInsensitiveContains("[Error]"),
              !CompanionDialogueDisplayPolicy.containsCJKScript(raw),
              !containsEmoji else { return nil }
        return text
    }

    /// One terminal punctuation run at the end (`.`, `...`, `!`, or `?`) and no earlier sentence
    /// terminator. This keeps the hardware line to the single sentence promised by PromptSpec.
    ///
    /// A trailing quote mark is NOT accepted: support text is the App speaking plainly, never a
    /// quotation, so `"Sentence."` means the model wrapped its answer in quotes — reject and let
    /// the template fallback take over rather than shipping stray quote marks to the panel.
    /// (Attributed quotations are a different feature entirely — Mode B, which never routes here.)
    /// The quote ban is anchored to the ends only — inner apostrophes are ordinary English and
    /// appear in the client's own examples ("Bet you can't clear this...", "What's the one part").
    private nonisolated static func isExactlyOneCompleteSentence(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last else { return false }
        let quoteMarks: Set<Character> = ["\"", "'"]
        guard !quoteMarks.contains(first), !quoteMarks.contains(last) else { return false }
        return text.range(
            of: #"^[^.!?]*[.!?]+$"#,
            options: .regularExpression
        ) != nil
    }

    /// Category joins the key: a late classification upgrade must regenerate the line, otherwise a
    /// deadline event keeps the admin-flavored "small contest" wording it got while still `.admin`.
    private static func cacheKey(for summary: EventSummary, isDayPacked: Bool) -> String {
        summary.title + "\u{1F}" + summary.description + "\u{1F}"
            + String(summary.category.rawValue) + "\u{1F}" + (isDayPacked ? "packed" : "open")
    }

    nonisolated static func isAIRetryAllowed(retryAfter: Date?, now: Date) -> Bool {
        guard let retryAfter else { return true }
        return now >= retryAfter
    }

    /// Generation input: title first, non-empty description appended for context — same shape as
    /// `EventCategoryService.classificationText` so both calls see the same event wording.
    private static func generationText(for summary: EventSummary) -> String {
        summary.description.isEmpty ? summary.title : "\(summary.title) — \(summary.description)"
    }

}
