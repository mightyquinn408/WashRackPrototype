import AVFoundation

public final class WashRackAudioUnit: AUAudioUnit, @unchecked Sendable {
    private static let outputGainStateKey = "com.QuinnTech.WashRack.outputGain"
    private static let parameterStateKey = "com.QuinnTech.WashRack.parameters"
    private static let outputGainSmoothingTimeSeconds: AUValue = 0.01
    private static let wetLayerMixSmoothingTimeSeconds: AUValue = 0.01

    private let washRackParameterTree: AUParameterTree
    private let dryWetMixParameter: AUParameter
    private let effectEnabledParameter: AUParameter
    private let outputGainParameter: AUParameter
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private let hostParameterValueStore: WashRackHostParameterValueStore
    private let wetLayerControlState: WashRackWetLayerControlState
    private let outputGainControlState: WashRackOutputGainControlState
    private let washReverb = WashRackWashReverb()
    private var currentWetLayerGain: AUValue
    private var targetWetLayerGain: AUValue
    private var wetLayerGainStep: AUValue
    private var wetLayerGainRampSamplesRemaining: AUAudioFrameCount
    private var currentOutputGainLinear: AUValue
    private var targetOutputGainLinear: AUValue
    private var outputGainLinearStep: AUValue
    private var outputGainRampSamplesRemaining: AUAudioFrameCount
    private var wasEffectEnabledLastRender: Bool

    @objc public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) throws {
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        washRackParameterTree = WashRackParameterTreeFactory.makeParameterTree()
        guard let dryWetMixParameter = washRackParameterTree.parameter(
            withAddress: WashRackParameterAddress.dryWetMix.rawValue
        ) else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_InvalidParameter)
            )
        }
        guard let effectEnabledParameter = washRackParameterTree.parameter(
            withAddress: WashRackParameterAddress.effectEnabled.rawValue
        ) else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_InvalidParameter)
            )
        }
        guard washRackParameterTree.parameter(
            withAddress: WashRackParameterAddress.lowPassCutoff.rawValue
        ) != nil else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_InvalidParameter)
            )
        }
        guard washRackParameterTree.parameter(
            withAddress: WashRackParameterAddress.lowPassResonance.rawValue
        ) != nil else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_InvalidParameter)
            )
        }
        guard let outputGainParameter = washRackParameterTree.parameter(
            withAddress: WashRackParameterAddress.outputGain.rawValue
        ) else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_InvalidParameter)
            )
        }

        let defaultGainDecibels = outputGainParameter.value
        let defaultLinearGain = Self.linearGain(fromDecibels: defaultGainDecibels)
        let defaultDryWetMix = dryWetMixParameter.value
        let defaultEffectEnabled = effectEnabledParameter.value
        let defaultWetLayerGain = WashRackWetLayerMixing.wetLayerGain(
            fromDryWetMixPercent: defaultDryWetMix
        )

        self.dryWetMixParameter = dryWetMixParameter
        self.effectEnabledParameter = effectEnabledParameter
        self.outputGainParameter = outputGainParameter
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        hostParameterValueStore = WashRackHostParameterValueStore()
        wetLayerControlState = WashRackWetLayerControlState(
            defaultDryWetMix: defaultDryWetMix,
            defaultEffectEnabled: defaultEffectEnabled
        )
        outputGainControlState = WashRackOutputGainControlState(defaultDecibels: defaultGainDecibels)
        currentWetLayerGain = defaultWetLayerGain
        targetWetLayerGain = defaultWetLayerGain
        wetLayerGainStep = 0
        wetLayerGainRampSamplesRemaining = 0
        currentOutputGainLinear = defaultLinearGain
        targetOutputGainLinear = defaultLinearGain
        outputGainLinearStep = 0
        outputGainRampSamplesRemaining = 0
        wasEffectEnabledLastRender = defaultEffectEnabled >= 0.5

        try super.init(componentDescription: componentDescription, options: options)

        parameterTree = washRackParameterTree
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 512

        washRackParameterTree.implementorValueObserver = { [weak self] parameter, value in
            guard let self,
                  let address = WashRackParameterAddress(rawValue: parameter.address) else {
                return
            }

            self.hostParameterValueStore.setValue(value, for: address)

            if address == .dryWetMix {
                self.wetLayerControlState.updateDryWetMix(value)
            } else if address == .effectEnabled {
                self.wetLayerControlState.updateEffectEnabled(value)
            } else if address == .outputGain {
                self.outputGainControlState.noteBaseValueChange(value, updateVisibleValue: true)
            }
        }

        washRackParameterTree.implementorValueProvider = { [weak self] parameter in
            guard let self else {
                return 0
            }

            if parameter.address == self.outputGainParameter.address {
                return self.outputGainHostVisibleValue()
            }

            guard let address = WashRackParameterAddress(rawValue: parameter.address) else {
                return 0
            }

            return self.hostParameterValueStore.value(for: address)
        }

        syncOutputGainStateFromParameter()
        syncWetLayerStateFromParameter()
        washReverb.prepare(sampleRate: outputBus.format.sampleRate)
    }

    public override var inputBusses: AUAudioUnitBusArray {
        inputBusArray
    }

    public override var outputBusses: AUAudioUnitBusArray {
        outputBusArray
    }

    public override var canProcessInPlace: Bool {
        true
    }

    public override var channelCapabilities: [NSNumber] {
        [1, 1, 2, 2]
    }

    public override func allocateRenderResources() throws {
        let inputFormat = inputBus.format
        let outputFormat = outputBus.format

        guard inputFormat.channelCount == outputFormat.channelCount,
              inputFormat.sampleRate == outputFormat.sampleRate else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_FormatNotSupported)
            )
        }

        syncOutputGainStateFromParameter()
        syncWetLayerStateFromParameter()
        washReverb.prepare(sampleRate: outputFormat.sampleRate)
        wasEffectEnabledLastRender = wetLayerControlState.effectEnabled() >= 0.5
        try super.allocateRenderResources()
    }

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            state[Self.parameterStateKey] = hostParameterValueStore.snapshotByIdentifier()
            state[Self.outputGainStateKey] = NSNumber(value: hostParameterValueStore.value(for: .outputGain))
            return state
        }
        set {
            super.fullState = newValue

            let restoredValues = restoredParameterValues(from: newValue)

            if let restoredOutputGain = restoredValues[.outputGain] {
                syncOutputGainRenderState(fromDecibels: restoredOutputGain)
            }

            for spec in WashRackParameterSpec.all {
                guard let restoredValue = restoredValues[spec.address],
                      let parameter = washRackParameterTree.parameter(withAddress: spec.address.rawValue) else {
                    continue
                }

                parameter.setValue(restoredValue, originator: nil)
            }

            if restoredValues[.outputGain] == nil {
                syncOutputGainStateFromParameter()
            }

            syncWetLayerStateFromParameter()
            washReverb.reset()
            wasEffectEnabledLastRender = wetLayerControlState.effectEnabled() >= 0.5
        }
    }

    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let self, self.renderResourcesAllocated else {
                return kAudioUnitErr_Uninitialized
            }

            guard outputBusNumber == 0 else {
                return kAudioUnitErr_InvalidElement
            }

            guard let pullInputBlock else {
                return kAudioUnitErr_NoConnection
            }

            let status = pullInputBlock(actionFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else {
                return status
            }

            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            let totalFrames = Int(frameCount)
            let bufferStartSampleTime = AUEventSampleTime(timestamp.pointee.mSampleTime)
            let desiredWetLayerGain = WashRackWetLayerMixing.wetLayerGain(
                fromDryWetMixPercent: self.wetLayerControlState.dryWetMix()
            )
            var effectEnabled = self.wetLayerControlState.effectEnabled() >= 0.5
            var renderedFrames = 0
            var handledOutputGainEvent = false
            var event = UnsafeMutablePointer(mutating: realtimeEventListHead)

            if Self.valuesDiffer(desiredWetLayerGain, self.targetWetLayerGain) {
                self.beginWetLayerGainRamp(
                    toWetLayerGain: desiredWetLayerGain,
                    durationSamples: self.wetLayerMixSmoothingSampleCount()
                )
            }

            if self.wasEffectEnabledLastRender && !effectEnabled {
                self.washReverb.reset()
            }

            while let currentEvent = event {
                let nextEvent = currentEvent.pointee.head.next

                if currentEvent.pointee.head.eventType.rawValue == 1 || currentEvent.pointee.head.eventType.rawValue == 2 {
                    let parameterEvent = currentEvent.pointee.parameter
                    let isRelevantParameter = parameterEvent.parameterAddress == self.outputGainParameter.address
                        || parameterEvent.parameterAddress == self.dryWetMixParameter.address
                        || parameterEvent.parameterAddress == self.effectEnabledParameter.address

                    guard isRelevantParameter else {
                        event = nextEvent
                        continue
                    }

                    let eventFrame = Self.frameOffset(
                        for: parameterEvent.eventSampleTime,
                        bufferStartSampleTime: bufferStartSampleTime,
                        totalFrames: totalFrames
                    )

                    if eventFrame > renderedFrames {
                        self.applyTopologyAndOutputGain(
                            to: outputBuffers,
                            startFrame: renderedFrames,
                            frameCount: eventFrame - renderedFrames,
                            effectEnabled: effectEnabled
                        )
                        renderedFrames = eventFrame
                    }

                    if parameterEvent.parameterAddress == self.outputGainParameter.address {
                        handledOutputGainEvent = true
                        if parameterEvent.rampDurationSampleFrames > 0 {
                            self.beginOutputGainRamp(
                                toDecibels: parameterEvent.value,
                                durationSamples: max(1, parameterEvent.rampDurationSampleFrames)
                            )
                        } else {
                            self.setImmediateOutputGain(toDecibels: parameterEvent.value)
                        }
                    } else if parameterEvent.parameterAddress == self.dryWetMixParameter.address {
                        if parameterEvent.rampDurationSampleFrames > 0 {
                            self.beginWetLayerGainRamp(
                                toDryWetMixPercent: parameterEvent.value,
                                durationSamples: max(1, parameterEvent.rampDurationSampleFrames)
                            )
                        } else {
                            self.setImmediateWetLayerGain(toDryWetMixPercent: parameterEvent.value)
                        }
                    } else if parameterEvent.parameterAddress == self.effectEnabledParameter.address {
                        if effectEnabled, parameterEvent.value < 0.5 {
                            self.washReverb.reset()
                        }
                        self.wetLayerControlState.updateEffectEnabled(parameterEvent.value)
                        effectEnabled = parameterEvent.value >= 0.5
                    }
                }

                event = nextEvent
            }

            if !handledOutputGainEvent,
               let desiredOutputGainDecibels = self.consumePendingOutputGainBaseValueChange() {
                let desiredLinearGain = Self.linearGain(fromDecibels: desiredOutputGainDecibels)

                if Self.valuesDiffer(desiredLinearGain, self.targetOutputGainLinear) {
                    self.beginOutputGainRamp(
                        toLinearGain: desiredLinearGain,
                        durationSamples: self.outputGainSmoothingSampleCount()
                    )
                }
            }

            if renderedFrames < totalFrames {
                self.applyTopologyAndOutputGain(
                    to: outputBuffers,
                    startFrame: renderedFrames,
                    frameCount: totalFrames - renderedFrames,
                    effectEnabled: effectEnabled
                )
            }

            self.wasEffectEnabledLastRender = effectEnabled

            return noErr
        }
    }

    private func consumePendingOutputGainBaseValueChange() -> AUValue? {
        outputGainControlState.consumePendingBaseValueChange()
    }

    private func restoredParameterValues(from state: [String: Any]?) -> [WashRackParameterAddress: AUValue] {
        guard let state else {
            return [:]
        }

        var restoredValues: [WashRackParameterAddress: AUValue] = [:]

        if let parameterSnapshot = state[Self.parameterStateKey] as? [String: Any] {
            restoredValues = hostParameterValueStore.applySnapshotByIdentifier(parameterSnapshot)
        }

        if restoredValues[.outputGain] == nil,
           let legacyOutputGain = state[Self.outputGainStateKey] as? NSNumber {
            let restoredOutputGain = legacyOutputGain.floatValue
            hostParameterValueStore.setValue(restoredOutputGain, for: .outputGain)
            restoredValues[.outputGain] = restoredOutputGain
        }

        return restoredValues
    }

    private func syncOutputGainStateFromParameter() {
        syncOutputGainRenderState(fromDecibels: hostParameterValueStore.value(for: .outputGain))
    }

    private func syncWetLayerStateFromParameter() {
        syncWetLayerRenderState(
            dryWetMix: hostParameterValueStore.value(for: .dryWetMix),
            effectEnabled: hostParameterValueStore.value(for: .effectEnabled)
        )
    }

    private func syncWetLayerRenderState(dryWetMix: AUValue, effectEnabled: AUValue) {
        let wetLayerGain = WashRackWetLayerMixing.wetLayerGain(fromDryWetMixPercent: dryWetMix)
        wetLayerControlState.syncAllStates(dryWetMix: dryWetMix, effectEnabled: effectEnabled)
        currentWetLayerGain = wetLayerGain
        targetWetLayerGain = wetLayerGain
        wetLayerGainStep = 0
        wetLayerGainRampSamplesRemaining = 0
    }

    private func syncOutputGainRenderState(fromDecibels decibels: AUValue) {
        let linearGain = Self.linearGain(fromDecibels: decibels)
        outputGainControlState.syncAllStates(to: decibels)
        currentOutputGainLinear = linearGain
        targetOutputGainLinear = linearGain
        outputGainLinearStep = 0
        outputGainRampSamplesRemaining = 0
    }

    private func setImmediateOutputGain(toDecibels decibels: AUValue) {
        let linearGain = Self.linearGain(fromDecibels: decibels)
        targetOutputGainLinear = linearGain
        currentOutputGainLinear = linearGain
        outputGainControlState.updateHostVisibleDecibels(decibels)
        outputGainLinearStep = 0
        outputGainRampSamplesRemaining = 0
    }

    private func beginOutputGainRamp(toDecibels targetDecibels: AUValue, durationSamples: AUAudioFrameCount) {
        beginOutputGainRamp(
            toLinearGain: Self.linearGain(fromDecibels: targetDecibels),
            durationSamples: durationSamples
        )
    }

    private func beginOutputGainRamp(toLinearGain targetLinearGain: AUValue, durationSamples: AUAudioFrameCount) {
        let safeDurationSamples = max(1, durationSamples)
        targetOutputGainLinear = targetLinearGain
        outputGainRampSamplesRemaining = safeDurationSamples
        outputGainLinearStep = (targetLinearGain - currentOutputGainLinear) / AUValue(safeDurationSamples)
    }

    private func setImmediateWetLayerGain(toDryWetMixPercent dryWetMixPercent: AUValue) {
        setImmediateWetLayerGain(
            toWetLayerGain: WashRackWetLayerMixing.wetLayerGain(fromDryWetMixPercent: dryWetMixPercent)
        )
        wetLayerControlState.updateDryWetMix(dryWetMixPercent)
    }

    private func setImmediateWetLayerGain(toWetLayerGain wetLayerGain: AUValue) {
        targetWetLayerGain = wetLayerGain
        currentWetLayerGain = wetLayerGain
        wetLayerGainStep = 0
        wetLayerGainRampSamplesRemaining = 0
    }

    private func beginWetLayerGainRamp(toDryWetMixPercent dryWetMixPercent: AUValue, durationSamples: AUAudioFrameCount) {
        beginWetLayerGainRamp(
            toWetLayerGain: WashRackWetLayerMixing.wetLayerGain(fromDryWetMixPercent: dryWetMixPercent),
            durationSamples: durationSamples
        )
        wetLayerControlState.updateDryWetMix(dryWetMixPercent)
    }

    private func beginWetLayerGainRamp(toWetLayerGain wetLayerGain: AUValue, durationSamples: AUAudioFrameCount) {
        let safeDurationSamples = max(1, durationSamples)
        targetWetLayerGain = wetLayerGain
        wetLayerGainRampSamplesRemaining = safeDurationSamples
        wetLayerGainStep = (wetLayerGain - currentWetLayerGain) / AUValue(safeDurationSamples)
    }

    private func outputGainSmoothingSampleCount() -> AUAudioFrameCount {
        let sampleRate = outputBus.format.sampleRate
        return max(1, AUAudioFrameCount((sampleRate * Double(Self.outputGainSmoothingTimeSeconds)).rounded()))
    }

    private func wetLayerMixSmoothingSampleCount() -> AUAudioFrameCount {
        let sampleRate = outputBus.format.sampleRate
        return max(1, AUAudioFrameCount((sampleRate * Double(Self.wetLayerMixSmoothingTimeSeconds)).rounded()))
    }

    private func applyTopologyAndOutputGain(
        to outputBuffers: UnsafeMutableAudioBufferListPointer,
        startFrame: Int,
        frameCount: Int,
        effectEnabled: Bool
    ) {
        guard frameCount > 0 else {
            return
        }

        var wetLayerGain = currentWetLayerGain
        var wetLayerStep = wetLayerGainStep
        var remainingWetLayerRampSamples = Int(wetLayerGainRampSamplesRemaining)
        var gain = currentOutputGainLinear
        var step = outputGainLinearStep
        var remainingRampSamples = Int(outputGainRampSamplesRemaining)

        for sampleIndex in startFrame ..< startFrame + frameCount {
            var dryMonoInput: AUValue = 0
            var activeChannelCount = 0

            for buffer in outputBuffers {
                guard let channelData = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                dryMonoInput += channelData[sampleIndex]
                activeChannelCount += 1
            }

            if activeChannelCount > 1 {
                dryMonoInput /= AUValue(activeChannelCount)
            }

            let wetStereoSample = effectEnabled
                ? washReverb.process(monoInput: dryMonoInput)
                : (left: AUValue(0), right: AUValue(0))

            for channelIndex in outputBuffers.indices {
                let buffer = outputBuffers[channelIndex]
                guard let channelData = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                let drySample = channelData[sampleIndex]
                let wetSample = channelIndex == 0 ? wetStereoSample.left : wetStereoSample.right
                channelData[sampleIndex] = WashRackWetLayerMixing.mixedSample(
                    drySample: drySample,
                    wetSample: wetSample,
                    wetLayerGain: wetLayerGain,
                    effectEnabled: effectEnabled,
                    outputGainLinear: gain
                )
            }

            if remainingWetLayerRampSamples > 0 {
                wetLayerGain += wetLayerStep
                remainingWetLayerRampSamples -= 1

                if remainingWetLayerRampSamples == 0 {
                    wetLayerGain = targetWetLayerGain
                    wetLayerStep = 0
                }
            }

            if remainingRampSamples > 0 {
                gain += step
                remainingRampSamples -= 1

                if remainingRampSamples == 0 {
                    gain = targetOutputGainLinear
                    step = 0
                }
            }
        }

        currentWetLayerGain = wetLayerGain
        wetLayerGainStep = wetLayerStep
        wetLayerGainRampSamplesRemaining = AUAudioFrameCount(remainingWetLayerRampSamples)
        currentOutputGainLinear = gain
        outputGainLinearStep = step
        outputGainRampSamplesRemaining = AUAudioFrameCount(remainingRampSamples)
        outputGainControlState.updateHostVisibleDecibels(
            Self.decibels(fromLinearGain: currentOutputGainLinear)
        )
    }

    private static func linearGain(fromDecibels decibels: AUValue) -> AUValue {
        if decibels == 0 {
            return 1
        }

        return powf(10, decibels / 20)
    }

    private static func decibels(fromLinearGain linearGain: AUValue) -> AUValue {
        let safeLinearGain = max(linearGain, 0.000_001)
        return 20 * log10f(safeLinearGain)
    }

    @MainActor
    var effectEnabledUIDisplayValue: AUValue {
        wetLayerControlState.effectEnabled()
    }

    @MainActor
    var dryWetMixUIDisplayPercent: AUValue {
        wetLayerControlState.dryWetMix()
    }

    @MainActor
    var outputGainUIDisplayDecibels: AUValue {
        outputGainControlState.hostVisibleDecibels()
    }

    private func outputGainHostVisibleValue() -> AUValue {
        outputGainControlState.hostVisibleDecibels()
    }

    private static func valuesDiffer(_ lhs: AUValue, _ rhs: AUValue) -> Bool {
        abs(lhs - rhs) > 0.0001
    }

    private static func frameOffset(
        for eventSampleTime: AUEventSampleTime,
        bufferStartSampleTime: AUEventSampleTime,
        totalFrames: Int
    ) -> Int {
        let rawOffset = Int(eventSampleTime - bufferStartSampleTime)
        return min(totalFrames, max(0, rawOffset))
    }
}
