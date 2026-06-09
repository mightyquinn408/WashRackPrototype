import AVFoundation
import OSLog
import Synchronization

public final class WashRackAudioUnit: AUAudioUnit, @unchecked Sendable {
    private static let outputGainStateKey = "com.QuinnTech.WashRack.outputGain"
    private static let outputGainObserverRampMinimumTimeSeconds: AUValue = 0.0015
    private static let outputGainObserverRampMaximumTimeSeconds: AUValue = 0.008
    private static let outputGainObserverRampIntervalFraction = 0.25
    private static let diagnosticsLogger = Logger(
        subsystem: "com.QuinnTech.WashRackPrototype",
        category: "OutputGainDiagnostics"
    )

    private let washRackParameterTree: AUParameterTree
    private let outputGainParameter: AUParameter
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private let desiredOutputGainDecibelsBits: Atomic<UInt32>
    private let currentOutputGainDecibelsBits: Atomic<UInt32>
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private var currentOutputGainDecibels: AUValue
    private var targetOutputGainDecibels: AUValue
    private var outputGainDecibelStep: AUValue
    private var outputGainRampSamplesRemaining: AUAudioFrameCount
    private let outputGainProviderCallCount: Atomic<UInt64>
    private let outputGainObserverCallCount: Atomic<UInt64>
    private let outputGainObserverRampSamples: Atomic<UInt32>
    private let outputGainLastObserverTimestampNanoseconds: Atomic<UInt64>
    private let outputGainLastObserverIntervalNanoseconds: Atomic<UInt64>
    private let outputGainMinDesiredDecibelsBits: Atomic<UInt32>
    private let outputGainMaxDesiredDecibelsBits: Atomic<UInt32>
    private let outputGainMinCurrentDecibelsBits: Atomic<UInt32>
    private let outputGainMaxCurrentDecibelsBits: Atomic<UInt32>
    private let outputGainRenderBufferCount: Atomic<UInt64>
    private let outputGainEventBufferCount: Atomic<UInt64>
    private let outputGainImmediateEventCount: Atomic<UInt64>
    private let outputGainRampEventCount: Atomic<UInt64>
    private let outputGainMaxEventsPerBuffer: Atomic<UInt32>
    private let outputGainMaxRampDurationSamples: Atomic<UInt32>
    private var diagnosticsTimer: DispatchSourceTimer?

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

        self.outputGainParameter = outputGainParameter
        inputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        desiredOutputGainDecibelsBits = Atomic(outputGainParameter.value.bitPattern)
        currentOutputGainDecibelsBits = Atomic(outputGainParameter.value.bitPattern)
        currentOutputGainDecibels = outputGainParameter.value
        targetOutputGainDecibels = outputGainParameter.value
        outputGainDecibelStep = 0
        outputGainRampSamplesRemaining = 0
        outputGainProviderCallCount = Atomic(0)
        outputGainObserverCallCount = Atomic(0)
        outputGainObserverRampSamples = Atomic(0)
        outputGainLastObserverTimestampNanoseconds = Atomic(0)
        outputGainLastObserverIntervalNanoseconds = Atomic(0)
        outputGainMinDesiredDecibelsBits = Atomic(outputGainParameter.value.bitPattern)
        outputGainMaxDesiredDecibelsBits = Atomic(outputGainParameter.value.bitPattern)
        outputGainMinCurrentDecibelsBits = Atomic(outputGainParameter.value.bitPattern)
        outputGainMaxCurrentDecibelsBits = Atomic(outputGainParameter.value.bitPattern)
        outputGainRenderBufferCount = Atomic(0)
        outputGainEventBufferCount = Atomic(0)
        outputGainImmediateEventCount = Atomic(0)
        outputGainRampEventCount = Atomic(0)
        outputGainMaxEventsPerBuffer = Atomic(0)
        outputGainMaxRampDurationSamples = Atomic(0)

        try super.init(componentDescription: componentDescription, options: options)

        parameterTree = washRackParameterTree
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 512

        washRackParameterTree.implementorValueObserver = { [weak self] parameter, value in
            guard let self, parameter.address == self.outputGainParameter.address else {
                return
            }

            self.outputGainObserverCallCount.add(1, ordering: .relaxed)
            self.updateObserverDrivenRampSamples()
            self.storeOutputGainDecibels(value)
        }

        washRackParameterTree.implementorValueProvider = { [weak self] parameter in
            guard let self else {
                return Self.defaultValue(for: parameter.address)
            }

            if parameter.address == self.outputGainParameter.address {
                self.outputGainProviderCallCount.add(1, ordering: .relaxed)
                return self.loadDesiredOutputGainDecibels()
            }

            return Self.defaultValue(for: parameter.address)
        }

        syncOutputGainStateFromParameter()
        startDiagnosticsTimerIfNeeded()
    }

    deinit {
        diagnosticsTimer?.cancel()
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

        outputGainObserverRampSamples.store(defaultObserverRampSampleCount(), ordering: .relaxed)
        syncOutputGainRenderState(fromDecibels: loadDesiredOutputGainDecibels())
        try super.allocateRenderResources()
    }

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            state[Self.outputGainStateKey] = NSNumber(value: loadDesiredOutputGainDecibels())
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
            var immediateEventCount = 0
            var rampEventCount = 0
            var maxRampDurationSamplesInBuffer: AUAudioFrameCount = 0
            var event = UnsafeMutablePointer(mutating: realtimeEventListHead)

            self.outputGainRenderBufferCount.add(1, ordering: .relaxed)

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

                        self.storeOutputGainDecibels(parameterEvent.value)
                        if parameterEvent.rampDurationSampleFrames > 0 {
                            rampEventCount += 1
                            maxRampDurationSamplesInBuffer = max(
                                maxRampDurationSamplesInBuffer,
                                parameterEvent.rampDurationSampleFrames
                            )
                            self.beginOutputGainRamp(
                                toDecibels: parameterEvent.value,
                                durationSamples: max(1, parameterEvent.rampDurationSampleFrames)
                            )
                        } else {
                            immediateEventCount += 1
                            self.targetOutputGainDecibels = parameterEvent.value
                            self.outputGainDecibelStep = 0
                            self.outputGainRampSamplesRemaining = 0
                        }
                    }
                }

                event = nextEvent
            }

            if !handledOutputGainEvent {
                let mirroredTargetDecibels = self.loadDesiredOutputGainDecibels()

                if Self.decibelValuesDiffer(mirroredTargetDecibels, self.targetOutputGainDecibels) {
                    self.beginOutputGainRamp(
                        toDecibels: mirroredTargetDecibels,
                        durationSamples: self.loadObserverDrivenRampSampleCount()
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

            let totalOutputGainEventsInBuffer = immediateEventCount + rampEventCount
            if totalOutputGainEventsInBuffer > 0 {
                self.outputGainEventBufferCount.add(1, ordering: .relaxed)
                self.outputGainImmediateEventCount.add(UInt64(immediateEventCount), ordering: .relaxed)
                self.outputGainRampEventCount.add(UInt64(rampEventCount), ordering: .relaxed)
                Self.updateMax(
                    self.outputGainMaxEventsPerBuffer,
                    candidate: UInt32(totalOutputGainEventsInBuffer)
                )
                Self.updateMax(
                    self.outputGainMaxRampDurationSamples,
                    candidate: UInt32(maxRampDurationSamplesInBuffer)
                )
            }

            return noErr
        }
    }

    private func loadDesiredOutputGainDecibels() -> AUValue {
        AUValue(bitPattern: desiredOutputGainDecibelsBits.load(ordering: .relaxed))
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

    private func updateObserverDrivenRampSamples() {
        let now = DispatchTime.now().uptimeNanoseconds
        let previous = outputGainLastObserverTimestampNanoseconds.exchange(now, ordering: .relaxed)

        guard previous != 0 else {
            return
        }

        let elapsedNanoseconds = now &- previous
        let sampleRate = outputBus.format.sampleRate
        guard sampleRate > 0 else {
            return
        }

        let elapsedSeconds = Double(elapsedNanoseconds) / 1_000_000_000
        let minimumSeconds = Double(Self.outputGainObserverRampMinimumTimeSeconds)
        let maximumSeconds = Double(Self.outputGainObserverRampMaximumTimeSeconds)
        let rampSeconds = elapsedSeconds * Self.outputGainObserverRampIntervalFraction
        let clampedSeconds = min(maximumSeconds, max(minimumSeconds, rampSeconds))
        let sampleCount = UInt32(max(1, Int((sampleRate * clampedSeconds).rounded())))
        outputGainLastObserverIntervalNanoseconds.store(elapsedNanoseconds, ordering: .relaxed)
        outputGainObserverRampSamples.store(sampleCount, ordering: .relaxed)
    }

    private func loadObserverDrivenRampSampleCount() -> AUAudioFrameCount {
        let storedSampleCount = outputGainObserverRampSamples.load(ordering: .relaxed)
        if storedSampleCount > 0 {
            return AUAudioFrameCount(storedSampleCount)
        }

        return defaultObserverRampSampleCount()
    }

    private func defaultObserverRampSampleCount() -> AUAudioFrameCount {
        let sampleRate = outputBus.format.sampleRate
        let defaultDurationSeconds = Double(Self.outputGainObserverRampMaximumTimeSeconds)
        return max(1, AUAudioFrameCount((sampleRate * defaultDurationSeconds).rounded()))
    }

    private func storeOutputGainDecibels(_ value: AUValue) {
        desiredOutputGainDecibelsBits.store(value.bitPattern, ordering: .relaxed)
        Self.updateMinBits(outputGainMinDesiredDecibelsBits, candidate: value.bitPattern) { lhs, rhs in
            AUValue(bitPattern: lhs) < AUValue(bitPattern: rhs)
        }
        Self.updateMaxBits(outputGainMaxDesiredDecibelsBits, candidate: value.bitPattern) { lhs, rhs in
            AUValue(bitPattern: lhs) > AUValue(bitPattern: rhs)
        }
    }

    private func storeCurrentOutputGainDecibels(_ value: AUValue) {
        currentOutputGainDecibelsBits.store(value.bitPattern, ordering: .relaxed)
        Self.updateMinBits(outputGainMinCurrentDecibelsBits, candidate: value.bitPattern) { lhs, rhs in
            AUValue(bitPattern: lhs) < AUValue(bitPattern: rhs)
        }
        Self.updateMaxBits(outputGainMaxCurrentDecibelsBits, candidate: value.bitPattern) { lhs, rhs in
            AUValue(bitPattern: lhs) > AUValue(bitPattern: rhs)
        }
    }

    private func applyOutputGain(
        to outputBuffers: UnsafeMutableAudioBufferListPointer,
        startFrame: Int,
        frameCount: Int
    ) {
        guard frameCount > 0 else {
            return
        }

        var decibels = currentOutputGainDecibels
        var step = outputGainDecibelStep
        var remainingRampSamples = Int(outputGainRampSamplesRemaining)

        if remainingRampSamples > 0 {
            var gain = Self.linearGain(fromDecibels: decibels)
            let gainStepMultiplier = Self.linearGain(fromDecibels: step)

            for sampleIndex in startFrame ..< startFrame + frameCount {
                let sampleGain = gain

                for buffer in outputBuffers {
                    guard let channelData = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                        continue
                    }

                    channelData[sampleIndex] *= sampleGain
                }

                if remainingRampSamples > 0 {
                    gain *= gainStepMultiplier
                    decibels += step
                    remainingRampSamples -= 1

                    if remainingRampSamples == 0 {
                        decibels = targetOutputGainDecibels
                        step = 0
                        gain = Self.linearGain(fromDecibels: decibels)
                    }
                }
            }
        } else {
            let sampleGain = Self.linearGain(fromDecibels: decibels)

            for buffer in outputBuffers {
                guard let channelData = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                for sampleIndex in startFrame ..< startFrame + frameCount {
                    channelData[sampleIndex] *= sampleGain
                }
            }
        }

        currentOutputGainDecibels = decibels
        outputGainDecibelStep = step
        outputGainRampSamplesRemaining = AUAudioFrameCount(remainingRampSamples)
        storeCurrentOutputGainDecibels(decibels)
    }

    private func beginOutputGainRamp(toDecibels targetDecibels: AUValue, durationSamples: AUAudioFrameCount) {
        let safeDurationSamples = max(1, durationSamples)
        targetOutputGainDecibels = targetDecibels
        outputGainRampSamplesRemaining = safeDurationSamples
        outputGainDecibelStep = (targetDecibels - currentOutputGainDecibels) / AUValue(safeDurationSamples)
    }

    private func syncOutputGainRenderState(fromDecibels decibels: AUValue) {
        storeOutputGainDecibels(decibels)
        storeCurrentOutputGainDecibels(decibels)
        currentOutputGainDecibels = decibels
        targetOutputGainDecibels = decibels
        outputGainDecibelStep = 0
        outputGainRampSamplesRemaining = 0
    }

    private static func linearGain(fromDecibels decibels: AUValue) -> AUValue {
        if decibels == 0 {
            return 1
        }

        return powf(10, decibels / 20)
    }

    private func startDiagnosticsTimerIfNeeded() {
        #if DEBUG
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.logOutputGainDiagnosticsIfNeeded()
        }
        timer.resume()
        diagnosticsTimer = timer
        #endif
    }

    private func logOutputGainDiagnosticsIfNeeded() {
        let providerCalls = outputGainProviderCallCount.exchange(0, ordering: .relaxed)
        let observerCalls = outputGainObserverCallCount.exchange(0, ordering: .relaxed)
        let renderBuffers = outputGainRenderBufferCount.exchange(0, ordering: .relaxed)
        let eventBuffers = outputGainEventBufferCount.exchange(0, ordering: .relaxed)
        let immediateEvents = outputGainImmediateEventCount.exchange(0, ordering: .relaxed)
        let rampEvents = outputGainRampEventCount.exchange(0, ordering: .relaxed)
        let maxEventsPerBuffer = outputGainMaxEventsPerBuffer.exchange(0, ordering: .relaxed)
        let maxRampDurationSamples = outputGainMaxRampDurationSamples.exchange(0, ordering: .relaxed)
        let observerRampSamples = outputGainObserverRampSamples.load(ordering: .relaxed)
        let observerIntervalNanoseconds = outputGainLastObserverIntervalNanoseconds.exchange(0, ordering: .relaxed)

        guard providerCalls > 0 || observerCalls > 0 || renderBuffers > 0 || eventBuffers > 0 else {
            return
        }

        let desiredDecibels = loadDesiredOutputGainDecibels()
        let currentDecibels = AUValue(bitPattern: currentOutputGainDecibelsBits.load(ordering: .relaxed))
        let minDesiredDecibels = AUValue(
            bitPattern: outputGainMinDesiredDecibelsBits.exchange(desiredDecibels.bitPattern, ordering: .relaxed)
        )
        let maxDesiredDecibels = AUValue(
            bitPattern: outputGainMaxDesiredDecibelsBits.exchange(desiredDecibels.bitPattern, ordering: .relaxed)
        )
        let minCurrentDecibels = AUValue(
            bitPattern: outputGainMinCurrentDecibelsBits.exchange(currentDecibels.bitPattern, ordering: .relaxed)
        )
        let maxCurrentDecibels = AUValue(
            bitPattern: outputGainMaxCurrentDecibelsBits.exchange(currentDecibels.bitPattern, ordering: .relaxed)
        )

        Self.diagnosticsLogger.notice(
            "outputGain diag providerCalls=\(providerCalls, privacy: .public) observerCalls=\(observerCalls, privacy: .public) observerRampSamples=\(observerRampSamples, privacy: .public) observerIntervalNs=\(observerIntervalNanoseconds, privacy: .public) renderBuffers=\(renderBuffers, privacy: .public) eventBuffers=\(eventBuffers, privacy: .public) immediateEvents=\(immediateEvents, privacy: .public) rampEvents=\(rampEvents, privacy: .public) maxEventsPerBuffer=\(maxEventsPerBuffer, privacy: .public) maxRampDurationSamples=\(maxRampDurationSamples, privacy: .public) desiredDb=\(desiredDecibels, privacy: .public) desiredRangeDb=[\(minDesiredDecibels, privacy: .public), \(maxDesiredDecibels, privacy: .public)] currentDb=\(currentDecibels, privacy: .public) currentRangeDb=[\(minCurrentDecibels, privacy: .public), \(maxCurrentDecibels, privacy: .public)]"
        )
    }

    private static func decibelValuesDiffer(_ lhs: AUValue, _ rhs: AUValue) -> Bool {
        abs(lhs - rhs) > 0.001
    }

    private static func defaultValue(for address: AUParameterAddress) -> AUValue {
        guard let washRackAddress = WashRackParameterAddress(rawValue: address) else {
            return 0
        }

        return WashRackParameterSpec.spec(for: washRackAddress).defaultValue
    }

    private static func frameOffset(
        for eventSampleTime: AUEventSampleTime,
        bufferStartSampleTime: AUEventSampleTime,
        totalFrames: Int
    ) -> Int {
        let rawOffset = Int(eventSampleTime - bufferStartSampleTime)
        return min(totalFrames, max(0, rawOffset))
    }

    private static func updateMax(_ atomic: borrowing Atomic<UInt32>, candidate: UInt32) {
        var current = atomic.load(ordering: .relaxed)

        while candidate > current {
            let result = atomic.compareExchange(
                expected: current,
                desired: candidate,
                ordering: .relaxed
            )

            if result.exchanged {
                return
            }

            current = result.original
        }
    }

    private static func updateMinBits(
        _ atomic: borrowing Atomic<UInt32>,
        candidate: UInt32,
        isPreferred: (UInt32, UInt32) -> Bool
    ) {
        var current = atomic.load(ordering: .relaxed)

        while isPreferred(candidate, current) {
            let result = atomic.compareExchange(
                expected: current,
                desired: candidate,
                ordering: .relaxed
            )

            if result.exchanged {
                return
            }

            current = result.original
        }
    }

    private static func updateMaxBits(
        _ atomic: borrowing Atomic<UInt32>,
        candidate: UInt32,
        isPreferred: (UInt32, UInt32) -> Bool
    ) {
        var current = atomic.load(ordering: .relaxed)

        while isPreferred(candidate, current) {
            let result = atomic.compareExchange(
                expected: current,
                desired: candidate,
                ordering: .relaxed
            )

            if result.exchanged {
                return
            }

            current = result.original
        }
    }
}
