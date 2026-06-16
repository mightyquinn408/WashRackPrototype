import AVFoundation
import Synchronization

final class WashRackOutputGainControlState: @unchecked Sendable {
    private let desiredBaseDecibelsBits: Atomic<UInt32>
    private let hostVisibleDecibelsBits: Atomic<UInt32>
    private let baseValueGeneration: Atomic<UInt32>
    private var consumedBaseValueGeneration: UInt32

    init(defaultDecibels: AUValue) {
        desiredBaseDecibelsBits = Atomic(defaultDecibels.bitPattern)
        hostVisibleDecibelsBits = Atomic(defaultDecibels.bitPattern)
        baseValueGeneration = Atomic(0)
        consumedBaseValueGeneration = 0
    }

    func desiredBaseDecibels() -> AUValue {
        AUValue(bitPattern: desiredBaseDecibelsBits.load(ordering: .relaxed))
    }

    func hostVisibleDecibels() -> AUValue {
        AUValue(bitPattern: hostVisibleDecibelsBits.load(ordering: .relaxed))
    }

    func noteBaseValueChange(_ decibels: AUValue) {
        desiredBaseDecibelsBits.store(decibels.bitPattern, ordering: .relaxed)
        baseValueGeneration.wrappingAdd(1, ordering: .relaxed)
    }

    func consumePendingBaseValueChange() -> AUValue? {
        let generation = baseValueGeneration.load(ordering: .relaxed)
        guard generation != consumedBaseValueGeneration else {
            return nil
        }

        consumedBaseValueGeneration = generation
        return desiredBaseDecibels()
    }

    func syncAllStates(to decibels: AUValue) {
        desiredBaseDecibelsBits.store(decibels.bitPattern, ordering: .relaxed)
        hostVisibleDecibelsBits.store(decibels.bitPattern, ordering: .relaxed)
        consumedBaseValueGeneration = baseValueGeneration.load(ordering: .relaxed)
    }

    func updateHostVisibleDecibels(_ decibels: AUValue) {
        hostVisibleDecibelsBits.store(decibels.bitPattern, ordering: .relaxed)
    }
}
