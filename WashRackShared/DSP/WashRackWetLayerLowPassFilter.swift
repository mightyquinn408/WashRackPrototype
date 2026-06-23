import AVFoundation

struct WashRackWetLayerLowPassFilter: Sendable {
    struct Coefficients: Sendable {
        let b0: AUValue
        let b1: AUValue
        let b2: AUValue
        let a1: AUValue
        let a2: AUValue
    }

    private struct ChannelState: Sendable {
        var x1: AUValue = 0
        var x2: AUValue = 0
        var y1: AUValue = 0
        var y2: AUValue = 0
    }

    private var leftState = ChannelState()
    private var rightState = ChannelState()

    mutating func reset() {
        leftState = ChannelState()
        rightState = ChannelState()
    }

    mutating func process(
        sample: AUValue,
        channelIndex: Int,
        coefficients: Coefficients
    ) -> AUValue {
        var state = channelIndex == 0 ? leftState : rightState

        let output = coefficients.b0 * sample
            + coefficients.b1 * state.x1
            + coefficients.b2 * state.x2
            - coefficients.a1 * state.y1
            - coefficients.a2 * state.y2

        state.x2 = state.x1
        state.x1 = sample
        state.y2 = state.y1
        state.y1 = output

        if channelIndex == 0 {
            leftState = state
        } else {
            rightState = state
        }

        return output
    }

    nonisolated static func resonanceQ(fromDecibels resonanceDecibels: AUValue) -> AUValue {
        let normalizedQ = 0.707 * powf(10, resonanceDecibels / 20)
        return min(max(normalizedQ, 0.25), 10)
    }

    nonisolated static func coefficients(
        sampleRate: Double,
        cutoff: AUValue,
        resonance: AUValue
    ) -> Coefficients {
        let safeCutoff = clampedCutoff(cutoff, sampleRate: sampleRate)
        let q = resonanceQ(fromDecibels: resonance)
        let omega = 2 * AUValue.pi * safeCutoff / AUValue(sampleRate)
        let cosOmega = cosf(omega)
        let sinOmega = sinf(omega)
        let alpha = sinOmega / (2 * q)

        let b0 = (1 - cosOmega) / 2
        let b1 = 1 - cosOmega
        let b2 = (1 - cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha

        return Coefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }

    private nonisolated static func clampedCutoff(_ cutoff: AUValue, sampleRate: Double) -> AUValue {
        let minimumCutoff: AUValue = 10
        let nyquistMargin = AUValue(sampleRate * 0.45)
        return min(max(cutoff, minimumCutoff), nyquistMargin)
    }
}
