import AVFoundation
import Testing
@testable import WashRackPrototype

struct WashRackHostParameterValueStoreTests {

    @Test
    func initializesFromSharedSpecDefaults() {
        let store = WashRackHostParameterValueStore()

        for spec in WashRackParameterSpec.all {
            #expect(store.value(for: spec.address) == spec.defaultValue)
        }
    }

    @Test
    func storesNonOutputParameterValuesInsteadOfFallingBackToDefaults() {
        let store = WashRackHostParameterValueStore()

        store.setValue(1.25, for: .delayTime)
        store.setValue(72, for: .feedback)

        #expect(store.value(for: .delayTime) == 1.25)
        #expect(store.value(for: .feedback) == 72)
    }

    @Test
    func snapshotRoundTripsUpdatedParameterValues() {
        let store = WashRackHostParameterValueStore()

        store.setValue(-9, for: .inputGain)
        store.setValue(14, for: .outputGain)
        store.setValue(1.5, for: .delayTime)
        store.setValue(58, for: .dryWetMix)
        store.setValue(2_400, for: .lowPassCutoff)
        store.setValue(8, for: .lowPassResonance)
        store.setValue(0, for: .effectEnabled)

        let snapshot = store.snapshotByIdentifier()
        let restoredStore = WashRackHostParameterValueStore()
        let restoredValues = restoredStore.applySnapshotByIdentifier(snapshot)

        #expect(restoredValues[.inputGain] == -9)
        #expect(restoredValues[.outputGain] == 14)
        #expect(restoredValues[.delayTime] == 1.5)
        #expect(restoredValues[.dryWetMix] == 58)
        #expect(restoredValues[.lowPassCutoff] == 2_400)
        #expect(restoredValues[.lowPassResonance] == 8)
        #expect(restoredValues[.effectEnabled] == 0)

        #expect(restoredStore.value(for: .inputGain) == -9)
        #expect(restoredStore.value(for: .outputGain) == 14)
        #expect(restoredStore.value(for: .delayTime) == 1.5)
        #expect(restoredStore.value(for: .dryWetMix) == 58)
        #expect(restoredStore.value(for: .lowPassCutoff) == 2_400)
        #expect(restoredStore.value(for: .lowPassResonance) == 8)
        #expect(restoredStore.value(for: .effectEnabled) == 0)
    }
}
