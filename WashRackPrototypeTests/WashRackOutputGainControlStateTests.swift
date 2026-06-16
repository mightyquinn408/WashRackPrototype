import AVFoundation
import Testing
@testable import WashRackPrototype

struct WashRackOutputGainControlStateTests {

    @Test
    func defaultsExposeUnityAndNoPendingBaseChange() {
        let state = WashRackOutputGainControlState(defaultDecibels: 0)

        #expect(state.desiredBaseDecibels() == 0)
        #expect(state.hostVisibleDecibels() == 0)
        #expect(state.consumePendingBaseValueChange() == nil)
    }

    @Test
    func baseValueChangesAreConsumedOnce() {
        let state = WashRackOutputGainControlState(defaultDecibels: 0)

        state.noteBaseValueChange(-12)

        #expect(state.desiredBaseDecibels() == -12)
        #expect(state.consumePendingBaseValueChange() == -12)
        #expect(state.consumePendingBaseValueChange() == nil)
    }

    @Test
    func syncAllStatesClearsPendingChangesAndUpdatesVisibleValue() {
        let state = WashRackOutputGainControlState(defaultDecibels: 0)

        state.noteBaseValueChange(-6)
        state.syncAllStates(to: -6)

        #expect(state.desiredBaseDecibels() == -6)
        #expect(state.hostVisibleDecibels() == -6)
        #expect(state.consumePendingBaseValueChange() == nil)
    }

    @Test
    func hostVisibleAutomationStateDoesNotCreateFallbackToDefault() {
        let state = WashRackOutputGainControlState(defaultDecibels: 0)

        state.noteBaseValueChange(-24)
        #expect(state.consumePendingBaseValueChange() == -24)

        state.updateHostVisibleDecibels(6.81)

        #expect(state.hostVisibleDecibels() == 6.81)
        #expect(state.desiredBaseDecibels() == -24)
        #expect(state.consumePendingBaseValueChange() == nil)
    }
}
