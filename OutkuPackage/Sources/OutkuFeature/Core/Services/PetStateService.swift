import Foundation

// MARK: - Pet State Service

/// 宠物状态计算服务
public actor PetStateService {
    public static let shared = PetStateService()

    private init() {}

    // MARK: - Calculate Mood

    /// 计算宠物当前心情
    /// - Parameters:
    ///   - lastInteraction: 上次交互时间
    ///   - tasksCompletedToday: 今日完成任务数
    ///   - totalTasksToday: 今日总任务数
    ///   - currentTime: 当前时间
    /// - Returns: 计算出的心情
    public func calculateMood(
        lastInteraction: Date,
        tasksCompletedToday: Int,
        totalTasksToday: Int,
        currentTime: Date = Date()
    ) -> PetMood {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)

        // 22:00-06:00 → Sleepy
        if hour >= 22 || hour < 6 {
            return .sleepy
        }

        // 超过 24h 未交互 → Missing
        let hoursSinceInteraction = currentTime.timeIntervalSince(lastInteraction) / 3600
        if hoursSinceInteraction > 24 {
            return .missing
        }

        // 任务完成率 > 80% → Excited
        if totalTasksToday > 0 {
            let completionRate = Double(tasksCompletedToday) / Double(totalTasksToday)
            if completionRate >= 0.8 {
                return .excited
            }
        }

        // 工作时间有任务 → Focused
        let isWorkHours = hour >= 9 && hour < 18
        if isWorkHours && totalTasksToday > 0 && tasksCompletedToday < totalTasksToday {
            return .focused
        }

        // 默认 → Happy
        return .happy
    }

    // MARK: - Calculate Scene

    /// 计算宠物当前场景
    /// - Parameters:
    ///   - currentTime: 当前时间
    ///   - hasTasks: 是否有待办任务
    /// - Returns: 计算出的场景
    public func calculateScene(
        currentTime: Date = Date(),
        hasTasks: Bool
    ) -> PetScene {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let weekday = calendar.component(.weekday, from: currentTime)

        // 夜间 (21:00-06:00) → Night
        if hour >= 21 || hour < 6 {
            return .night
        }

        // 周末 (周六=7, 周日=1) → Outdoor
        let isWeekend = weekday == 1 || weekday == 7
        if isWeekend {
            return .outdoor
        }

        // 工作时间有任务 → Work
        let isWorkHours = hour >= 9 && hour < 18
        if isWorkHours && hasTasks {
            return .work
        }

        // 默认 → Indoor
        return .indoor
    }

    // MARK: - Update Pet State

    /// 更新宠物完整状态
    /// - Parameters:
    ///   - pet: 当前宠物
    ///   - tasksCompletedToday: 今日完成任务数
    ///   - totalTasksToday: 今日总任务数
    /// - Returns: 更新后的宠物
    public func updatePetState(
        pet: Pet,
        tasksCompletedToday: Int,
        totalTasksToday: Int
    ) -> Pet {
        var updatedPet = pet
        let now = Date()

        // 更新心情
        updatedPet.mood = calculateMood(
            lastInteraction: pet.lastInteraction,
            tasksCompletedToday: tasksCompletedToday,
            totalTasksToday: totalTasksToday,
            currentTime: now
        )

        // 更新场景
        updatedPet.scene = calculateScene(
            currentTime: now,
            hasTasks: totalTasksToday > tasksCompletedToday
        )

        // 更新最后交互时间
        updatedPet.lastInteraction = now

        return updatedPet
    }

    // MARK: - Calculate Progress

    /// 计算宠物进化进度
    /// - Parameters:
    ///   - currentProgress: 当前进度
    ///   - taskCompleted: 是否完成了任务
    ///   - streakDays: 连续打卡天数
    /// - Returns: 新的进度值
    public func calculateProgress(
        currentProgress: Double,
        taskCompleted: Bool,
        streakDays: Int
    ) -> Double {
        var progress = currentProgress

        if taskCompleted {
            // 基础进度增加
            progress += 0.02

            // 连续打卡奖励
            if streakDays >= 7 {
                progress += 0.01 // 额外 1%
            }
            if streakDays >= 30 {
                progress += 0.01 // 再额外 1%
            }
        }

        return min(1.0, max(0.0, progress))
    }

    // MARK: - Check Evolution

    /// 检查是否可以进化
    /// - Parameter pet: 当前宠物
    /// - Returns: 是否可以进化
    public func canEvolve(pet: Pet) -> Bool {
        pet.progress >= 1.0 && pet.stage.nextStage != nil
    }

    /// 执行进化
    /// - Parameter pet: 当前宠物
    /// - Returns: 进化后的宠物
    public func evolve(pet: Pet) -> Pet {
        guard canEvolve(pet: pet), let nextStage = pet.stage.nextStage else {
            return pet
        }

        var evolvedPet = pet
        evolvedPet.stage = nextStage
        evolvedPet.progress = 0.0

        // 进化时增加属性
        evolvedPet.weight *= 1.2
        evolvedPet.height *= 1.15
        evolvedPet.tailLength *= 1.1

        return evolvedPet
    }

    // MARK: - Status Description

    /// 获取宠物状态描述
    /// - Parameter pet: 宠物
    /// - Returns: 状态描述文本
    public func getStatusDescription(pet: Pet) -> String {
        switch pet.mood {
        case .happy:
            return "\(pet.name) is feeling happy and content!"
        case .excited:
            return "\(pet.name) is excited about your progress!"
        case .focused:
            return "\(pet.name) is focused and ready to help!"
        case .sleepy:
            return "\(pet.name) is getting sleepy... time to rest?"
        case .missing:
            return "\(pet.name) missed you! Welcome back!"
        }
    }

    /// 获取场景描述
    /// - Parameter scene: 场景
    /// - Returns: 场景描述文本
    public func getSceneDescription(scene: PetScene) -> String {
        switch scene {
        case .indoor:
            return "Relaxing at home"
        case .outdoor:
            return "Enjoying the outdoors"
        case .night:
            return "Under the starry sky"
        case .work:
            return "In work mode"
        }
    }
}
