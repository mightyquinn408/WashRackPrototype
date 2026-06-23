import AVFoundation
import Synchronization

final class WashRackWetLayerControlState: @unchecked Sendable {
    private let dryWetMixBits: Atomic<UInt32>
    private let effectEnabledBits: Atomic<UInt32>

    init(defaultDryWetMix: AUValue, defaultEffectEnabled: AUValue) {
        dryWetMixBits = Atomic(defaultDryWetMix.bitPattern)
        effectEnabledBits = Atomic(defaultEffectEnabled.bitPattern)
    }

    func dryWetMix() -> AUValue {
        AUValue(bitPattern: dryWetMixBits.load(ordering: .relaxed))
    }

    func effectEnabled() -> AUValue {
        AUValue(bitPattern: effectEnabledBits.load(ordering: .relaxed))
    }

    func updateDryWetMix(_ value: AUValue) {
        dryWetMixBits.store(value.bitPattern, ordering: .relaxed)
    }

    func updateEffectEnabled(_ value: AUValue) {
        effectEnabledBits.store(value.bitPattern, ordering: .relaxed)
    }

    func syncAllStates(dryWetMix: AUValue, effectEnabled: AUValue) {
        updateDryWetMix(dryWetMix)
        updateEffectEnabled(effectEnabled)
    }
}
