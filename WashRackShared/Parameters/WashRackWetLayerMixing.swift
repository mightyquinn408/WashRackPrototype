import AVFoundation

enum WashRackWetLayerMixing {
    nonisolated static func wetLayerGain(fromDryWetMixPercent dryWetMixPercent: AUValue) -> AUValue {
        min(max(dryWetMixPercent, 0), 100) / 100
    }

    // This topology proof intentionally leaves dry + wet summing uncompensated.
    nonisolated static func mixedSample(
        drySample: AUValue,
        wetSample: AUValue,
        wetLayerGain: AUValue,
        effectEnabled: Bool,
        outputGainLinear: AUValue
    ) -> AUValue {
        let wetContribution = effectEnabled ? wetSample * max(wetLayerGain, 0) : 0
        return (drySample + wetContribution) * outputGainLinear
    }
}
