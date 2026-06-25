import AVFoundation
import Testing
@testable import WashRackPrototype

struct WashRackWashReverbTests {

    @Test
    func impulseProducesAudibleTail() {
        let reverb = WashRackWashReverb()
        reverb.prepare(sampleRate: 44_100)

        _ = reverb.process(monoInput: 1)

        var tailEnergy: AUValue = 0
        for _ in 0 ..< 8_000 {
            let wetSample = reverb.process(monoInput: 0)
            tailEnergy += abs(wetSample.left) + abs(wetSample.right)
        }

        #expect(tailEnergy > 0.01)
    }

    @Test
    func resetClearsAccumulatedTailState() {
        let reverb = WashRackWashReverb()
        reverb.prepare(sampleRate: 44_100)

        _ = reverb.process(monoInput: 1)
        for _ in 0 ..< 512 {
            _ = reverb.process(monoInput: 0)
        }

        reverb.reset()

        for _ in 0 ..< 256 {
            let wetSample = reverb.process(monoInput: 0)
            #expect(abs(wetSample.left) < 0.000_001)
            #expect(abs(wetSample.right) < 0.000_001)
        }
    }

    @Test
    func newImpulseAfterResetDoesNotBleedStaleTailState() {
        let reverb = WashRackWashReverb()
        reverb.prepare(sampleRate: 44_100)

        _ = reverb.process(monoInput: 1)
        for _ in 0 ..< 1_024 {
            _ = reverb.process(monoInput: 0)
        }

        reverb.reset()

        for _ in 0 ..< 512 {
            let wetSample = reverb.process(monoInput: 0)
            #expect(abs(wetSample.left) < 0.000_001)
            #expect(abs(wetSample.right) < 0.000_001)
        }

        _ = reverb.process(monoInput: 1)

        var tailEnergy: AUValue = 0
        for _ in 0 ..< 8_000 {
            let wetSample = reverb.process(monoInput: 0)
            tailEnergy += abs(wetSample.left) + abs(wetSample.right)
        }

        #expect(tailEnergy > 0.01)
    }

    @Test
    func processingRemainsFiniteAndBounded() {
        let reverb = WashRackWashReverb()
        reverb.prepare(sampleRate: 48_000)

        var maxMagnitude: AUValue = 0

        for sampleIndex in 0 ..< 20_000 {
            let input: AUValue = sampleIndex.isMultiple(of: 2) ? 0.35 : -0.35
            let wetSample = reverb.process(monoInput: input)

            #expect(wetSample.left.isFinite)
            #expect(wetSample.right.isFinite)

            maxMagnitude = max(maxMagnitude, abs(wetSample.left), abs(wetSample.right))
        }

        #expect(maxMagnitude < 8)
    }

    @Test
    func stereoOutputsDecorrelateAfterImpulse() {
        let reverb = WashRackWashReverb()
        reverb.prepare(sampleRate: 44_100)

        _ = reverb.process(monoInput: 1)

        var foundDifference = false
        for _ in 0 ..< 4_000 {
            let wetSample = reverb.process(monoInput: 0)
            if abs(wetSample.left - wetSample.right) > 0.000_001 {
                foundDifference = true
                break
            }
        }

        #expect(foundDifference)
    }
}
