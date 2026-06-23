import AVFoundation
import Testing
@testable import WashRackPrototype

struct WashRackLowPassControlStateTests {

    @Test
    func defaultsMatchSharedSpecDefaults() {
        let state = WashRackLowPassControlState(defaultCutoff: 6_000, defaultResonance: 0)

        #expect(state.cutoff() == 6_000)
        #expect(state.resonance() == 0)
    }

    @Test
    func updatesStoreLatestCutoffAndResonance() {
        let state = WashRackLowPassControlState(defaultCutoff: 6_000, defaultResonance: 0)

        state.updateCutoff(900)
        state.updateResonance(6)

        #expect(state.cutoff() == 900)
        #expect(state.resonance() == 6)
    }

    @Test
    func syncAllStatesUpdatesCutoffAndResonanceTogether() {
        let state = WashRackLowPassControlState(defaultCutoff: 6_000, defaultResonance: 0)

        state.syncAllStates(cutoff: 1_800, resonance: -6)

        #expect(state.cutoff() == 1_800)
        #expect(state.resonance() == -6)
    }
}
