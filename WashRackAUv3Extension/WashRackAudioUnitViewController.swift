import AppKit
import AudioToolbox
import CoreAudioKit
import OSLog
import SwiftUI

private let audioUnitViewControllerLogger = Logger(
    subsystem: "com.QuinnTech.WashRackPrototype",
    category: "AUv3UIViewController"
)

@MainActor
public final class WashRackAudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private static var lastCreatedAudioUnit: AUAudioUnit?

    @objc public var auAudioUnit: AUAudioUnit? {
        didSet {
            audioUnit = auAudioUnit
            audioUnitViewControllerLogger.notice(
                "auAudioUnit didSet controller=\(self.controllerIdentifier, privacy: .public) audioUnit=\(self.audioUnitIdentifier, privacy: .public) lastCreatedNil=\(Self.lastCreatedAudioUnit == nil, privacy: .public) hostExists=\(self.hostingView != nil, privacy: .public)"
            )
            if let auAudioUnit {
                Self.lastCreatedAudioUnit = auAudioUnit
                rebuildViewIfVisible(audioUnit: auAudioUnit)
            }
        }
    }

    private var audioUnit: AUAudioUnit?
    private var observableParameterTree: ObservableAUParameterGroup?
    private var hostingView: NSHostingView<WashRackMainView>?
    private var hostingViewConstraints: [NSLayoutConstraint] = []
    private var parameterRefreshTimer: Timer?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        audioUnitViewControllerLogger.notice("init controller=\(self.controllerIdentifier, privacy: .public)")
    }

    public override func loadView() {
        audioUnitViewControllerLogger.notice("loadView controller=\(self.controllerIdentifier, privacy: .public)")
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 420, height: 240)
        audioUnitViewControllerLogger.notice(
            "viewDidLoad controller=\(self.controllerIdentifier, privacy: .public) audioUnitNil=\(self.audioUnit == nil, privacy: .public) lastCreatedNil=\(Self.lastCreatedAudioUnit == nil, privacy: .public) hostExists=\(self.hostingView != nil, privacy: .public)"
        )
        guard audioUnit != nil else {
            audioUnitViewControllerLogger.notice("viewDidLoad noAudioUnit controller=\(self.controllerIdentifier, privacy: .public)")
            return
        }
        syncParametersFromAudioUnit()
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        audioUnitViewControllerLogger.notice(
            "viewWillAppear controller=\(self.controllerIdentifier, privacy: .public) audioUnitNil=\(self.audioUnit == nil, privacy: .public) lastCreatedNil=\(Self.lastCreatedAudioUnit == nil, privacy: .public) hostExists=\(self.hostingView != nil, privacy: .public)"
        )

        guard audioUnit != nil else {
            audioUnitViewControllerLogger.notice("viewWillAppear noAudioUnit controller=\(self.controllerIdentifier, privacy: .public)")
            return
        }

        syncParametersFromAudioUnit()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()

        guard let audioUnit else {
            return
        }

        rebuildViewIfVisible(audioUnit: audioUnit)
        startParameterRefreshTimer()
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        audioUnitViewControllerLogger.notice(
            "viewDidDisappear controller=\(self.controllerIdentifier, privacy: .public) audioUnit=\(self.audioUnitIdentifier, privacy: .public) hostExists=\(self.hostingView != nil, privacy: .public)"
        )
        stopParameterRefreshTimer()
        teardownHostingView()
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
        audioUnitViewControllerLogger.notice("createAudioUnit controller=\(self.controllerIdentifier, privacy: .public)")
        let audioUnit = try WashRackAudioUnit(
            componentDescription: componentDescription,
            options: []
        )

        self.audioUnit = audioUnit
        Self.lastCreatedAudioUnit = audioUnit
        audioUnitViewControllerLogger.notice(
            "createAudioUnit created controller=\(self.controllerIdentifier, privacy: .public) audioUnit=\(self.audioUnitIdentifier, privacy: .public)"
        )

        return audioUnit
    }

    private func rebuildViewIfVisible(audioUnit: AUAudioUnit) {
        guard isViewLoaded, view.window != nil else {
            return
        }

        installHostingViewIfNeeded(audioUnit: audioUnit)
    }

    private func installHostingViewIfNeeded(audioUnit: AUAudioUnit) {
        audioUnitViewControllerLogger.notice(
            "configureView controller=\(self.controllerIdentifier, privacy: .public) audioUnitArg=\(Self.identifier(for: audioUnit), privacy: .public) currentAudioUnit=\(self.audioUnitIdentifier, privacy: .public) hostExists=\(self.hostingView != nil, privacy: .public)"
        )

        if hostingView != nil, self.audioUnit === audioUnit {
            syncParametersFromAudioUnit()
            return
        }

        teardownHostingView()

        guard let observableParameterTree = audioUnit.observableParameterTree else {
            return
        }

        self.observableParameterTree = observableParameterTree

        let hostingView = NSHostingView(
            rootView: WashRackMainView(parameterTree: observableParameterTree)
        )

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        let constraints = [
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

        self.hostingView = hostingView
        self.hostingViewConstraints = constraints
        syncParametersFromAudioUnit()
    }

    private func teardownHostingView() {
        NSLayoutConstraint.deactivate(hostingViewConstraints)
        hostingViewConstraints.removeAll()
        hostingView?.removeFromSuperview()
        hostingView = nil
        observableParameterTree = nil
    }

    private func startParameterRefreshTimer() {
        guard parameterRefreshTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncParametersFromAudioUnit()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        parameterRefreshTimer = timer
    }

    private func stopParameterRefreshTimer() {
        parameterRefreshTimer?.invalidate()
        parameterRefreshTimer = nil
    }

    private func syncParametersFromAudioUnit() {
        observableParameterTree?.syncFromParameters()
        guard let washRackAudioUnit = audioUnit as? WashRackAudioUnit,
              let observableParameterTree else {
            return
        }

        let effectEnabledParameter: ObservableAUParameter = observableParameterTree.effectEnabled
        effectEnabledParameter.syncFromHostDisplayValue(washRackAudioUnit.effectEnabledUIDisplayValue)

        let dryWetMixParameter: ObservableAUParameter = observableParameterTree.dryWetMix
        dryWetMixParameter.syncFromHostDisplayValue(washRackAudioUnit.dryWetMixUIDisplayPercent)

        let outputGainParameter: ObservableAUParameter = observableParameterTree.outputGain
        outputGainParameter.syncFromHostDisplayValue(washRackAudioUnit.outputGainUIDisplayDecibels)
    }

    private var controllerIdentifier: String {
        Self.identifier(for: self)
    }

    private var audioUnitIdentifier: String {
        guard let audioUnit else {
            return "nil"
        }

        return Self.identifier(for: audioUnit)
    }

    private static func identifier(for object: AnyObject) -> String {
        String(UInt(bitPattern: ObjectIdentifier(object)), radix: 16)
    }
}
