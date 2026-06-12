import AppKit
import AudioToolbox
import CoreAudioKit
import SwiftUI

@MainActor
public final class WashRackAudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private static var lastCreatedAudioUnit: AUAudioUnit?

    @objc public var auAudioUnit: AUAudioUnit? {
        didSet {
            audioUnit = auAudioUnit
            if let auAudioUnit {
                Self.lastCreatedAudioUnit = auAudioUnit
                configureViewIfPossible(audioUnit: auAudioUnit)
                startParameterRefreshTimer()
            }
        }
    }

    private var audioUnit: AUAudioUnit?
    private var observableParameterTree: ObservableAUParameterGroup?
    private var hostingController: NSHostingController<WashRackMainView>?
    private var parameterRefreshTimer: Timer?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 360, height: 140)
        if audioUnit == nil {
            audioUnit = Self.lastCreatedAudioUnit
        }

        guard let audioUnit else {
            return
        }
        configureViewIfPossible(audioUnit: audioUnit)
    }

    public override func viewWillAppear() {
        super.viewWillAppear()

        if audioUnit == nil {
            audioUnit = Self.lastCreatedAudioUnit
        }

        guard let audioUnit else {
            return
        }

        configureViewIfPossible(audioUnit: audioUnit)
        startParameterRefreshTimer()
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        stopParameterRefreshTimer()
    }

    nonisolated public func createAudioUnit(
        with componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try makeAudioUnit(componentDescription: componentDescription)
            }
        }

        return try DispatchQueue.main.sync {
            try self.makeAudioUnit(componentDescription: componentDescription)
        }
    }

    private func makeAudioUnit(
        componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        let audioUnit = try WashRackAudioUnit(
            componentDescription: componentDescription,
            options: []
        )

        self.audioUnit = audioUnit
        Self.lastCreatedAudioUnit = audioUnit

        DispatchQueue.main.async {
            self.configureViewIfPossible(audioUnit: audioUnit)
            self.startParameterRefreshTimer()
        }

        return audioUnit
    }

    private func configureViewIfPossible(audioUnit: AUAudioUnit) {
        if let hostingController {
            hostingController.removeFromParent()
            hostingController.view.removeFromSuperview()
        }

        guard let observableParameterTree = audioUnit.observableParameterTree else {
            return
        }

        self.observableParameterTree = observableParameterTree

        let hostingController = NSHostingController(
            rootView: WashRackMainView(parameterTree: observableParameterTree)
        )

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.hostingController = hostingController
        syncOutputGainDisplayFromAudioUnit()
    }

    private func startParameterRefreshTimer() {
        guard parameterRefreshTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncOutputGainDisplayFromAudioUnit()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        parameterRefreshTimer = timer
    }

    private func stopParameterRefreshTimer() {
        parameterRefreshTimer?.invalidate()
        parameterRefreshTimer = nil
    }

    private func syncOutputGainDisplayFromAudioUnit() {
        guard let washRackAudioUnit = audioUnit as? WashRackAudioUnit,
              let observableParameterTree else {
            return
        }

        let outputGainParameter: ObservableAUParameter = observableParameterTree.outputGain
        outputGainParameter.syncFromHostDisplayValue(washRackAudioUnit.outputGainUIDisplayDecibels)
    }
}
