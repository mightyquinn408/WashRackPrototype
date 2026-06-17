import AVFoundation
import Synchronization

final class WashRackHostParameterValueStore: @unchecked Sendable {
    private let inputGainBits: Atomic<UInt32>
    private let outputGainBits: Atomic<UInt32>
    private let delayTimeBits: Atomic<UInt32>
    private let feedbackBits: Atomic<UInt32>
    private let dryWetMixBits: Atomic<UInt32>
    private let lowPassCutoffBits: Atomic<UInt32>
    private let lowPassResonanceBits: Atomic<UInt32>
    private let effectEnabledBits: Atomic<UInt32>

    init(specs: [WashRackParameterSpec] = WashRackParameterSpec.all) {
        let defaults = Dictionary(uniqueKeysWithValues: specs.map { spec in
            (spec.address, spec.defaultValue.bitPattern)
        })

        inputGainBits = Atomic(defaults[.inputGain] ?? 0)
        outputGainBits = Atomic(defaults[.outputGain] ?? 0)
        delayTimeBits = Atomic(defaults[.delayTime] ?? 0)
        feedbackBits = Atomic(defaults[.feedback] ?? 0)
        dryWetMixBits = Atomic(defaults[.dryWetMix] ?? 0)
        lowPassCutoffBits = Atomic(defaults[.lowPassCutoff] ?? 0)
        lowPassResonanceBits = Atomic(defaults[.lowPassResonance] ?? 0)
        effectEnabledBits = Atomic(defaults[.effectEnabled] ?? 0)
    }

    func value(for address: WashRackParameterAddress) -> AUValue {
        let bits: UInt32

        switch address {
        case .inputGain:
            bits = inputGainBits.load(ordering: .relaxed)
        case .outputGain:
            bits = outputGainBits.load(ordering: .relaxed)
        case .delayTime:
            bits = delayTimeBits.load(ordering: .relaxed)
        case .feedback:
            bits = feedbackBits.load(ordering: .relaxed)
        case .dryWetMix:
            bits = dryWetMixBits.load(ordering: .relaxed)
        case .lowPassCutoff:
            bits = lowPassCutoffBits.load(ordering: .relaxed)
        case .lowPassResonance:
            bits = lowPassResonanceBits.load(ordering: .relaxed)
        case .effectEnabled:
            bits = effectEnabledBits.load(ordering: .relaxed)
        }

        return AUValue(bitPattern: bits)
    }

    func setValue(_ value: AUValue, for address: WashRackParameterAddress) {
        switch address {
        case .inputGain:
            inputGainBits.store(value.bitPattern, ordering: .relaxed)
        case .outputGain:
            outputGainBits.store(value.bitPattern, ordering: .relaxed)
        case .delayTime:
            delayTimeBits.store(value.bitPattern, ordering: .relaxed)
        case .feedback:
            feedbackBits.store(value.bitPattern, ordering: .relaxed)
        case .dryWetMix:
            dryWetMixBits.store(value.bitPattern, ordering: .relaxed)
        case .lowPassCutoff:
            lowPassCutoffBits.store(value.bitPattern, ordering: .relaxed)
        case .lowPassResonance:
            lowPassResonanceBits.store(value.bitPattern, ordering: .relaxed)
        case .effectEnabled:
            effectEnabledBits.store(value.bitPattern, ordering: .relaxed)
        }
    }

    func snapshotByIdentifier() -> [String: NSNumber] {
        Dictionary(uniqueKeysWithValues: WashRackParameterSpec.all.map { spec in
            (spec.identifier, NSNumber(value: value(for: spec.address)))
        })
    }

    @discardableResult
    func applySnapshotByIdentifier(_ snapshot: [String: Any]) -> [WashRackParameterAddress: AUValue] {
        var restoredValues: [WashRackParameterAddress: AUValue] = [:]

        for spec in WashRackParameterSpec.all {
            guard let number = snapshot[spec.identifier] as? NSNumber else {
                continue
            }

            let restoredValue = number.floatValue
            setValue(restoredValue, for: spec.address)
            restoredValues[spec.address] = restoredValue
        }

        return restoredValues
    }
}
