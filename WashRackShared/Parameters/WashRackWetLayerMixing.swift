import AVFoundation

enum WashRackWetLayerMixing {
    nonisolated static func wetLayerGain(fromDryWetMixPercent dryWetMixPercent: AUValue) -> AUValue {
        min(max(dryWetMixPercent, 0), 100) / 100
    }

    // This topology proof intentionally leaves dry + wet summing uncompensated.
    nonisolated static func topologyScaleFactor(
        fromWetLayerGain wetLayerGain: AUValue,
        effectEnabled: Bool
    ) -> AUValue {
        1 + (effectEnabled ? max(wetLayerGain, 0) : 0)
    }
}
