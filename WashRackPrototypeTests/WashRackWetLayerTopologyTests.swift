import AVFoundation
import Testing
@testable import WashRackPrototype

struct WashRackWetLayerTopologyTests {

    @Test
    func wetLayerControlStateDefaultsMatchSharedSpecDefaults() {
        let state = WashRackWetLayerControlState(defaultDryWetMix: 40, defaultEffectEnabled: 1)

        #expect(state.dryWetMix() == 40)
        #expect(state.effectEnabled() == 1)
    }

    @Test
    func wetLayerControlStateStoresLatestValues() {
        let state = WashRackWetLayerControlState(defaultDryWetMix: 40, defaultEffectEnabled: 1)

        state.updateDryWetMix(75)
        state.updateEffectEnabled(0)

        #expect(state.dryWetMix() == 75)
        #expect(state.effectEnabled() == 0)
    }

    @Test
    func wetLayerControlStateCanSyncDryWetMixAndEffectEnabledTogether() {
        let state = WashRackWetLayerControlState(defaultDryWetMix: 40, defaultEffectEnabled: 1)

        state.syncAllStates(dryWetMix: 100, effectEnabled: 0)

        #expect(state.dryWetMix() == 100)
        #expect(state.effectEnabled() == 0)
    }

    @Test
    func dryWetMixZeroProducesDryAnchorOnlyScale() {
        let wetLayerGain = WashRackWetLayerMixing.wetLayerGain(fromDryWetMixPercent: 0)
        let mixedSample = WashRackWetLayerMixing.mixedSample(
            drySample: 0.5,
            wetSample: 0.5,
            wetLayerGain: wetLayerGain,
            effectEnabled: true,
            outputGainLinear: 1
        )

        #expect(wetLayerGain == 0)
        #expect(mixedSample == 0.5)
    }

    @Test
    func effectDisabledIgnoresWetLayerContribution() {
        let wetLayerGain = WashRackWetLayerMixing.wetLayerGain(fromDryWetMixPercent: 100)
        let mixedSample = WashRackWetLayerMixing.mixedSample(
            drySample: 0.5,
            wetSample: 0.25,
            wetLayerGain: wetLayerGain,
            effectEnabled: false,
            outputGainLinear: 1
        )

        #expect(wetLayerGain == 1)
        #expect(mixedSample == 0.5)
    }

    @Test
    func dryWetMixHundredPercentProducesUncompensatedDryPlusWetScale() {
        let wetLayerGain = WashRackWetLayerMixing.wetLayerGain(fromDryWetMixPercent: 100)
        let mixedSample = WashRackWetLayerMixing.mixedSample(
            drySample: 0.5,
            wetSample: 0.5,
            wetLayerGain: wetLayerGain,
            effectEnabled: true,
            outputGainLinear: 1
        )

        #expect(wetLayerGain == 1)
        #expect(mixedSample == 1)
    }
}
