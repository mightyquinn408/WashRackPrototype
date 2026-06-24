import AVFoundation

final class WashRackWashReverb: @unchecked Sendable {
    private static let referenceSampleRate = 44_100.0
    private static let inputGain: AUValue = 0.45
    private static let combOutputScale: AUValue = 0.3
    private static let stereoRightInputSkew: AUValue = 0.94
    private static let diffuserStages: [(samples: Int, feedback: AUValue)] = [
        (149, 0.72),
        (211, 0.68),
    ]
    private static let combStages: [(samples: Int, feedback: AUValue)] = [
        (1_687, 0.78),
        (1_601, 0.8),
        (2_053, 0.76),
        (2_251, 0.82),
    ]
    private static let stereoStages: [(samples: Int, feedback: AUValue)] = [
        (331, 0.45),
        (401, 0.5),
    ]

    private var diffuserA = AllPassDelay()
    private var diffuserB = AllPassDelay()
    private var combA = FeedbackCombDelay()
    private var combB = FeedbackCombDelay()
    private var combC = FeedbackCombDelay()
    private var combD = FeedbackCombDelay()
    private var stereoLeft = AllPassDelay()
    private var stereoRight = AllPassDelay()
    private var preparedSampleRate = 0.0

    func prepare(sampleRate: Double) {
        let safeSampleRate = max(sampleRate, 8_000)
        preparedSampleRate = safeSampleRate

        let diffuserConfig = Self.diffuserStages.map {
            (scaledLength($0.samples, sampleRate: safeSampleRate), $0.feedback)
        }
        diffuserA.configure(length: diffuserConfig[0].0, feedback: diffuserConfig[0].1)
        diffuserB.configure(length: diffuserConfig[1].0, feedback: diffuserConfig[1].1)

        let combConfig = Self.combStages.map {
            (scaledLength($0.samples, sampleRate: safeSampleRate), $0.feedback)
        }
        combA.configure(length: combConfig[0].0, feedback: combConfig[0].1)
        combB.configure(length: combConfig[1].0, feedback: combConfig[1].1)
        combC.configure(length: combConfig[2].0, feedback: combConfig[2].1)
        combD.configure(length: combConfig[3].0, feedback: combConfig[3].1)

        let stereoConfig = Self.stereoStages.map {
            (scaledLength($0.samples, sampleRate: safeSampleRate), $0.feedback)
        }
        stereoLeft.configure(length: stereoConfig[0].0, feedback: stereoConfig[0].1)
        stereoRight.configure(length: stereoConfig[1].0, feedback: stereoConfig[1].1)

        reset()
    }

    func reset() {
        diffuserA.reset()
        diffuserB.reset()
        combA.reset()
        combB.reset()
        combC.reset()
        combD.reset()
        stereoLeft.reset()
        stereoRight.reset()
    }

    func process(monoInput: AUValue) -> (left: AUValue, right: AUValue) {
        if preparedSampleRate == 0 {
            prepare(sampleRate: Self.referenceSampleRate)
        }

        var diffusedInput = monoInput * Self.inputGain
        diffusedInput = diffuserA.process(diffusedInput)
        diffusedInput = diffuserB.process(diffusedInput)

        let combSum = combA.process(diffusedInput)
            + combB.process(diffusedInput)
            + combC.process(diffusedInput)
            + combD.process(diffusedInput)
        let wetCore = combSum * Self.combOutputScale

        let left = stereoLeft.process(wetCore)
        let right = stereoRight.process(wetCore * Self.stereoRightInputSkew)
        return (left, right)
    }

    private func scaledLength(_ referenceSamples: Int, sampleRate: Double) -> Int {
        max(1, Int((Double(referenceSamples) * sampleRate / Self.referenceSampleRate).rounded()))
    }

    private struct AllPassDelay: Sendable {
        private var buffer: [AUValue] = [0]
        private var index = 0
        private var feedback: AUValue = 0.5

        mutating func configure(length: Int, feedback: AUValue) {
            buffer = Array(repeating: 0, count: max(1, length))
            index = 0
            self.feedback = feedback
        }

        mutating func reset() {
            for bufferIndex in buffer.indices {
                buffer[bufferIndex] = 0
            }
            index = 0
        }

        mutating func process(_ input: AUValue) -> AUValue {
            let delayedSample = buffer[index]
            let output = -input + delayedSample
            buffer[index] = input + (delayedSample * feedback)
            advanceIndex()
            return output
        }

        private mutating func advanceIndex() {
            index += 1
            if index == buffer.count {
                index = 0
            }
        }
    }

    private struct FeedbackCombDelay: Sendable {
        private var buffer: [AUValue] = [0]
        private var index = 0
        private var feedback: AUValue = 0.8

        mutating func configure(length: Int, feedback: AUValue) {
            buffer = Array(repeating: 0, count: max(1, length))
            index = 0
            self.feedback = feedback
        }

        mutating func reset() {
            for bufferIndex in buffer.indices {
                buffer[bufferIndex] = 0
            }
            index = 0
        }

        mutating func process(_ input: AUValue) -> AUValue {
            let delayedSample = buffer[index]
            buffer[index] = input + (delayedSample * feedback)
            advanceIndex()
            return delayedSample
        }

        private mutating func advanceIndex() {
            index += 1
            if index == buffer.count {
                index = 0
            }
        }
    }
}
