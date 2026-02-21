import SwiftUI

// MARK: - Pixel Art Body

struct PixelArtBody: View {
    let pixelSize: CGFloat
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let animationPhase: Int
    let petForm: PetForm
    var mood: PetMood = .happy
    var isBlinking: Bool = false

    // 0 = transparent, 1 = primary, 2 = secondary, 3 = accent, 4 = white, 5 = black, 6 = highlight, 7 = sleepy eyes
    private var pixelPattern: [[Int]] {
        var pattern = basePatternForForm(petForm)

        // Apply mood-based eye modifications
        pattern = applyMoodToPattern(pattern, mood: mood, form: petForm)

        // Apply blink: either from animation phase or explicit blink state
        if (animationPhase == 3 && mood != .sleepy) || (isBlinking && mood != .sleepy) {
            pattern = applyBlinkAnimation(to: pattern, form: petForm)
        }

        return pattern
    }

    // MARK: - Mood Pattern Modifications

    private func applyMoodToPattern(_ pattern: [[Int]], mood: PetMood, form: PetForm) -> [[Int]] {
        var result = pattern

        switch mood {
        case .sleepy:
            // 半闭眼效果
            result = applySleepyEyes(to: result, form: form)
        case .excited:
            // 眼睛更大/更亮（使用 accent 色）
            result = applyExcitedEyes(to: result, form: form)
        case .missing:
            // 悲伤的眼睛（向下看）
            result = applyMissingEyes(to: result, form: form)
        case .focused, .happy:
            // 保持默认
            break
        }

        return result
    }

    private func applySleepyEyes(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

        switch form {
        case .cat:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .dog:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .bunny:
            result[5] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[6] = [0, 2, 6, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 6, 2, 0]
        case .bird:
            result[4] = [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0]
            result[5] = [0, 0, 0, 2, 1, 5, 5, 1, 5, 5, 1, 2, 2, 2, 0, 0]
        case .dragon:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        }

        return result
    }

    private func applyExcitedEyes(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

        // 使用 accent 色（3）替代白色（4）让眼睛更亮
        switch form {
        case .cat:
            result[4] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
        case .dog:
            result[4] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
        case .bunny:
            result[5] = [0, 0, 2, 1, 1, 5, 3, 1, 1, 5, 3, 1, 1, 2, 0, 0]
            result[6] = [0, 2, 6, 1, 1, 5, 3, 1, 1, 5, 3, 1, 1, 6, 2, 0]
        case .bird:
            result[4] = [0, 0, 0, 2, 1, 5, 3, 1, 5, 3, 1, 2, 0, 0, 0, 0]
            result[5] = [0, 0, 0, 2, 1, 5, 3, 1, 5, 3, 1, 2, 2, 2, 0, 0]
        case .dragon:
            // Dragon already has glowing eyes
            break
        }

        return result
    }

    private func applyMissingEyes(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

        // 眼睛向下看的效果
        switch form {
        case .cat:
            result[4] = [0, 0, 2, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .dog:
            result[4] = [0, 0, 2, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .bunny:
            result[5] = [0, 0, 2, 1, 1, 4, 4, 1, 1, 4, 4, 1, 1, 2, 0, 0]
            result[6] = [0, 2, 6, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 6, 2, 0]
        case .bird:
            result[4] = [0, 0, 0, 2, 1, 4, 4, 1, 4, 4, 1, 2, 0, 0, 0, 0]
            result[5] = [0, 0, 0, 2, 1, 5, 5, 1, 5, 5, 1, 2, 2, 2, 0, 0]
        case .dragon:
            result[4] = [0, 0, 2, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        }

        return result
    }

    // MARK: - Pet Form Patterns

    private func basePatternForForm(_ form: PetForm) -> [[Int]] {
        switch form {
        case .cat:
            return catPattern
        case .dog:
            return dogPattern
        case .bunny:
            return bunnyPattern
        case .bird:
            return birdPattern
        case .dragon:
            return dragonPattern
        }
    }

    // Cat: Pointed ears, whiskers, sleek body
    private var catPattern: [[Int]] {
        [
            [0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0],  // Row 0 - ear tips
            [0, 0, 2, 1, 2, 0, 0, 0, 0, 0, 0, 2, 1, 2, 0, 0],  // Row 1 - ears
            [0, 0, 2, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 2, 0, 0],  // Row 2 - head top
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 3 - head
            [0, 0, 2, 1, 5, 4, 1, 1, 1, 1, 5, 4, 1, 2, 0, 0],  // Row 4 - eyes top
            [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0],  // Row 5 - eyes bottom
            [0, 2, 2, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 2, 2, 0],  // Row 6 - whiskers + nose
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 7 - mouth
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 8 - neck
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 9 - body top
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 10 - body
            [0, 0, 2, 1, 1, 1, 6, 1, 1, 6, 1, 1, 1, 2, 0, 0],  // Row 11 - belly
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 2, 0, 0, 0, 0, 2, 1, 2, 0, 1, 2],  // Row 13 - feet + tail
            [0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 0],  // Row 14 - paws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Dog: Floppy ears, happy tongue, wagging tail
    private var dogPattern: [[Int]] {
        [
            [0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0],  // Row 0 - ear tops
            [0, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2, 0],  // Row 1 - floppy ears
            [0, 2, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 2, 0],  // Row 2 - ears + head
            [0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0],  // Row 3 - head
            [0, 0, 2, 1, 5, 4, 1, 1, 1, 1, 5, 4, 1, 2, 0, 0],  // Row 4 - eyes
            [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0],  // Row 5 - eyes
            [0, 0, 2, 1, 1, 1, 1, 5, 5, 1, 1, 1, 1, 2, 0, 0],  // Row 6 - snout
            [0, 0, 2, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 2, 0, 0],  // Row 7 - tongue
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 8 - chin
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 9 - neck
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 10 - body
            [0, 0, 2, 1, 1, 6, 6, 6, 6, 6, 6, 1, 1, 2, 0, 0],  // Row 11 - belly
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 0],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 1, 2, 0, 0, 2, 1, 1, 2, 0, 2, 2],  // Row 13 - feet + tail
            [0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0],  // Row 14 - paws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Bunny: Long upright ears, fluffy cheeks, cotton tail
    private var bunnyPattern: [[Int]] {
        [
            [0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 2, 0, 0, 0, 0],  // Row 0 - ear tips
            [0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 2, 0, 0, 0, 0],  // Row 1 - ears
            [0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 2, 0, 0, 0, 0],  // Row 2 - ears
            [0, 0, 0, 0, 2, 3, 2, 2, 2, 2, 3, 2, 0, 0, 0, 0],  // Row 3 - inner ears + head
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 4 - head
            [0, 0, 2, 1, 1, 5, 4, 1, 1, 5, 4, 1, 1, 2, 0, 0],  // Row 5 - eyes
            [0, 2, 6, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 6, 2, 0],  // Row 6 - cheeks + eyes
            [0, 2, 6, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 6, 2, 0],  // Row 7 - cheeks + nose
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 8 - mouth
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 9 - neck
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 10 - body
            [0, 0, 2, 1, 1, 1, 6, 6, 6, 6, 1, 1, 1, 2, 0, 0],  // Row 11 - belly
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 6, 0],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 1, 2, 0, 0, 2, 1, 1, 2, 6, 6, 0],  // Row 13 - feet + fluffy tail
            [0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0],  // Row 14 - paws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Bird: Wings, beak, feathered crest
    private var birdPattern: [[Int]] {
        [
            [0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0],  // Row 0 - crest
            [0, 0, 0, 0, 0, 2, 3, 3, 3, 2, 0, 0, 0, 0, 0, 0],  // Row 1 - crest
            [0, 0, 0, 0, 2, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0],  // Row 2 - head top
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0],  // Row 3 - head
            [0, 0, 0, 2, 1, 5, 4, 1, 5, 4, 1, 2, 0, 0, 0, 0],  // Row 4 - eyes
            [0, 0, 0, 2, 1, 5, 5, 1, 5, 5, 1, 2, 2, 2, 0, 0],  // Row 5 - eyes + beak
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 3, 3, 3, 2, 0],  // Row 6 - face + beak
            [0, 0, 0, 0, 2, 1, 1, 1, 1, 1, 2, 2, 2, 0, 0, 0],  // Row 7 - chin
            [0, 0, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 0, 0, 0],  // Row 8 - wings start
            [0, 2, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1, 2, 2, 0, 0],  // Row 9 - wings
            [2, 2, 1, 1, 2, 1, 6, 6, 6, 1, 2, 1, 1, 2, 2, 0],  // Row 10 - wings + belly
            [0, 2, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0],  // Row 11 - wings end
            [0, 0, 0, 0, 2, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0],  // Row 12 - body
            [0, 0, 0, 0, 0, 2, 1, 2, 1, 2, 0, 0, 0, 0, 0, 0],  // Row 13 - feet
            [0, 0, 0, 0, 0, 2, 2, 0, 2, 2, 0, 0, 0, 0, 0, 0],  // Row 14 - claws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Dragon: Horns, wings, spiky tail
    private var dragonPattern: [[Int]] {
        [
            [0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0],  // Row 0 - horn tips
            [0, 0, 2, 3, 2, 0, 0, 0, 0, 0, 0, 2, 3, 2, 0, 0],  // Row 1 - horns
            [0, 0, 0, 2, 1, 2, 2, 2, 2, 2, 2, 1, 2, 0, 0, 0],  // Row 2 - head top
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 3 - head
            [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0],  // Row 4 - glowing eyes
            [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0],  // Row 5 - eyes
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 6 - snout
            [0, 0, 2, 1, 1, 1, 3, 1, 1, 3, 1, 1, 1, 2, 0, 0],  // Row 7 - nostrils
            [0, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 0],  // Row 8 - neck + wing start
            [2, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 2, 2],  // Row 9 - wings
            [0, 2, 1, 2, 1, 6, 6, 6, 6, 6, 6, 1, 2, 1, 2, 0],  // Row 10 - wings + belly
            [0, 0, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 0, 0],  // Row 11 - body
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 1, 2, 0, 0, 2, 1, 1, 2, 0, 3, 2],  // Row 13 - feet + spiky tail
            [0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 2, 0, 2, 3, 2],  // Row 14 - claws + tail tip
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0],  // Row 15 - tail end
        ]
    }

    // MARK: - Blink Animation

    private func applyBlinkAnimation(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

        // Find eye rows and close them (replace white/pupil with primary color)
        switch form {
        case .cat:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .dog:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .bunny:
            result[5] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[6] = [0, 2, 6, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 6, 2, 0]
        case .bird:
            result[4] = [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0]
            result[5] = [0, 0, 0, 2, 1, 5, 5, 1, 5, 5, 1, 2, 2, 2, 0, 0]
        case .dragon:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<pixelPattern.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<pixelPattern[row].count, id: \.self) { col in
                        Rectangle()
                            .fill(colorForPixel(pixelPattern[row][col]))
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
    }

    private func colorForPixel(_ value: Int) -> Color {
        switch value {
        case 0: return .clear
        case 1: return primaryColor
        case 2: return secondaryColor
        case 3: return accentColor
        case 4: return .white
        case 5: return .black
        case 6: return primaryColor.opacity(0.7) // Highlight/belly color
        default: return .clear
        }
    }
}
