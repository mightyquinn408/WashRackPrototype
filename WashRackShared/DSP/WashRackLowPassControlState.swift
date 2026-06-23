import AVFoundation
import Synchronization

final class WashRackLowPassControlState: @unchecked Sendable {
    private let cutoffBits: Atomic<UInt32>
    private let resonanceBits: Atomic<UInt32>

    init(defaultCutoff: AUValue, defaultResonance: AUValue) {
        cutoffBits = Atomic(defaultCutoff.bitPattern)
        resonanceBits = Atomic(defaultResonance.bitPattern)
    }

    func cutoff() -> AUValue {
        AUValue(bitPattern: cutoffBits.load(ordering: .relaxed))
    }

    func resonance() -> AUValue {
        AUValue(bitPattern: resonanceBits.load(ordering: .relaxed))
    }

    func updateCutoff(_ value: AUValue) {
        cutoffBits.store(value.bitPattern, ordering: .relaxed)
    }

    func updateResonance(_ value: AUValue) {
        resonanceBits.store(value.bitPattern, ordering: .relaxed)
    }

    func syncAllStates(cutoff: AUValue, resonance: AUValue) {
        updateCutoff(cutoff)
        updateResonance(resonance)
    }
}
