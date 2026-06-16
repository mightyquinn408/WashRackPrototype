import AVFoundation

public final class WashRackAudioUnit: AUAudioUnit, @unchecked Sendable {
    private static let outputGainStateKey = "com.QuinnTech.WashRack.outputGain"
    private static let outputGainSmoothingTimeSeconds: AUValue = 0.01

    private let washRackParameterTree: AUParameterTree
    private let outputGainParameter: AUParameter
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private let outputGainControlState: WashRackOutputGainControlState
    private var currentOutputGainLinear: AUValue
    private var targetOutputGainLinear: AUValue
    private var outputGainLinearStep: AUValue
    private var outputGainRampSamplesRemaining: AUAudioFrameCount

    @objc public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) throws {
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        washRackParameterTree = WashRackParameterTreeFactory.makeParameterTree()
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

        self.outputGainParameter = outputGainParameter
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        outputGainControlState = WashRackOutputGainControlState(defaultDecibels: defaultGainDecibels)
        currentOutputGainLinear = defaultLinearGain
        targetOutputGainLinear = defaultLinearGain
        outputGainLinearStep = 0
        outputGainRampSamplesRemaining = 0

        try super.init(componentDescription: componentDescription, options: options)

        parameterTree = washRackParameterTree
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 512

        washRackParameterTree.implementorValueObserver = { [weak self] parameter, value in
            guard let self, parameter.address == self.outputGainParameter.address else {
                return
            }

            self.outputGainControlState.noteBaseValueChange(value)
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

            return WashRackParameterSpec.spec(for: address).defaultValue
        }

        syncOutputGainStateFromParameter()
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
        try super.allocateRenderResources()
    }

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            state[Self.outputGainStateKey] = NSNumber(value: outputGainParameter.value)
            return state
        }
        set {
            super.fullState = newValue

            if let restoredValue = restoredOutputGain(from: newValue) {
                outputGainParameter.setValue(restoredValue, originator: nil)
            }

            syncOutputGainStateFromParameter()
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
            var renderedFrames = 0
            var handledOutputGainEvent = false
            var event = UnsafeMutablePointer(mutating: realtimeEventListHead)

            while let currentEvent = event {
                let nextEvent = currentEvent.pointee.head.next

                if currentEvent.pointee.head.eventType.rawValue == 1 || currentEvent.pointee.head.eventType.rawValue == 2 {
                    let parameterEvent = currentEvent.pointee.parameter

                    if parameterEvent.parameterAddress == self.outputGainParameter.address {
                        handledOutputGainEvent = true
                        let eventFrame = Self.frameOffset(
                            for: parameterEvent.eventSampleTime,
                            bufferStartSampleTime: bufferStartSampleTime,
                            totalFrames: totalFrames
                        )

                        if eventFrame > renderedFrames {
                            self.applyOutputGain(
                                to: outputBuffers,
                                startFrame: renderedFrames,
                                frameCount: eventFrame - renderedFrames
                            )
                            renderedFrames = eventFrame
                        }

                        if parameterEvent.rampDurationSampleFrames > 0 {
                            self.beginOutputGainRamp(
                                toDecibels: parameterEvent.value,
                                durationSamples: max(1, parameterEvent.rampDurationSampleFrames)
                            )
                        } else {
                            self.setImmediateOutputGain(toDecibels: parameterEvent.value)
                        }
                    }
                }

                event = nextEvent
            }

            if !handledOutputGainEvent,
               self.consumePendingOutputGainBaseValueChange() {
                let desiredOutputGainDecibels = self.outputGainControlState.desiredBaseDecibels()
                let desiredLinearGain = Self.linearGain(fromDecibels: desiredOutputGainDecibels)

                if Self.linearGainValuesDiffer(desiredLinearGain, self.targetOutputGainLinear) {
                    self.beginOutputGainRamp(
                        toLinearGain: desiredLinearGain,
                        durationSamples: self.outputGainSmoothingSampleCount()
                    )
                }
            }

            if renderedFrames < totalFrames {
                self.applyOutputGain(
                    to: outputBuffers,
                    startFrame: renderedFrames,
                    frameCount: totalFrames - renderedFrames
                )
            }

            return noErr
        }
    }

    private func consumePendingOutputGainBaseValueChange() -> Bool {
        outputGainControlState.consumePendingBaseValueChange() != nil
    }

    private func restoredOutputGain(from state: [String: Any]?) -> AUValue? {
        guard let number = state?[Self.outputGainStateKey] as? NSNumber else {
            return nil
        }

        return number.floatValue
    }

    private func syncOutputGainStateFromParameter() {
        syncOutputGainRenderState(fromDecibels: outputGainParameter.value)
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

    private func outputGainSmoothingSampleCount() -> AUAudioFrameCount {
        let sampleRate = outputBus.format.sampleRate
        return max(1, AUAudioFrameCount((sampleRate * Double(Self.outputGainSmoothingTimeSeconds)).rounded()))
    }

    private func applyOutputGain(
        to outputBuffers: UnsafeMutableAudioBufferListPointer,
        startFrame: Int,
        frameCount: Int
    ) {
        guard frameCount > 0 else {
            return
        }

        var gain = currentOutputGainLinear
        var step = outputGainLinearStep
        var remainingRampSamples = Int(outputGainRampSamplesRemaining)

        for sampleIndex in startFrame ..< startFrame + frameCount {
            let sampleGain = gain

            for buffer in outputBuffers {
                guard let channelData = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                channelData[sampleIndex] *= sampleGain
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
    var outputGainUIDisplayDecibels: AUValue {
        outputGainControlState.hostVisibleDecibels()
    }

    private func outputGainHostVisibleValue() -> AUValue {
        outputGainControlState.hostVisibleDecibels()
    }

    private static func linearGainValuesDiffer(_ lhs: AUValue, _ rhs: AUValue) -> Bool {
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
