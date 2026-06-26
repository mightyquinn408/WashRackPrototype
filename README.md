# WashRack Prototype

WashRack is a macOS-only audio effect prototype built with Swift, AudioKit, and AUv3 building blocks.

This repository currently serves two purposes:

1. A standalone prototype app for quickly auditioning DSP ideas.
2. An in-progress AUv3 effect plugin for Logic Pro and Ableton Live 12+.

The project is intentionally being built in small, understandable phases so a beginner can follow how a standalone audio app grows into a host-visible plugin.

## Current Status

The repository currently includes a standalone macOS prototype app with:

- audio file loading
- looped playback
- an output level meter
- a delay effect
- a low-pass filter

The signal flow in the app is:

`AudioPlayer -> Delay -> LowPassFilter -> Output`

The repository also includes the first real AUv3 plugin architecture work:

- a shared AU parameter contract
- a macOS AUv3 extension target
- a minimal `AUAudioUnit` shell
- host-visible parameters for Logic Pro and Ableton Live
- a minimal custom plugin UI
- a working `Output Gain` vertical slice from host automation to DSP

If your goal is learning plugin architecture, the most important parts of the project are the shared parameter contract and the AUv3 extension.

## What Is Working Today

### Standalone app

The standalone app still works as a normal macOS prototype and currently supports:

- loading an audio file from disk
- playing and stopping the file
- metering the output level
- adjusting delay time, feedback, and mix
- adjusting low-pass cutoff and resonance
- bypassing the delay and filter in the app

### AUv3 plugin

The current AUv3 implementation supports:

- loading as an audio effect in Ableton Live 12+
- exposing eight AU parameters to the host
- showing those parameters in host automation menus
- restoring parameter state when reopening the host project
- a minimal custom editor window
- a working `Output Gain` control that affects audio
- `Output Gain` automation that updates both sound and UI

Important current limitation:

- the current Alpha AU slice includes retained dry anchor behavior, wet-layer wash reverb, `Effect Enabled`, `Dry/Wet Mix`, and `Output Gain`
- delay movement, filter behavior, input gain, feedback, and the remaining AU-side parameter semantics are still intentionally incomplete

## The Shared Parameter Contract

One of the biggest architectural decisions in this project is that AU parameters are treated as the contract between:

- the host
- the plugin UI
- the DSP/render code
- preset and state restoration
- project save and reopen

That contract lives in the shared parameter files:

- [WashRackParameterAddress.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackShared/Parameters/WashRackParameterAddress.swift)
- [WashRackParameterSpec.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackShared/Parameters/WashRackParameterSpec.swift)
- [WashRackParameterTreeFactory.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackShared/Parameters/WashRackParameterTreeFactory.swift)

These files define:

- stable parameter addresses
- parameter identifiers
- parameter names shown to hosts
- units
- ranges
- defaults
- AU flags such as “can ramp”

The eight shared parameters are:

- `inputGain`
- `outputGain`
- `delayTime`
- `feedback`
- `dryWetMix`
- `lowPassCutoff`
- `lowPassResonance`
- `effectEnabled`

## Project Layout

### Standalone app

- [WashRackPrototype/ContentView.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackPrototype/ContentView.swift): basic SwiftUI prototype interface
- [WashRackPrototype/Audio/AudioEngineController.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackPrototype/Audio/AudioEngineController.swift): AudioKit engine, player, delay, filter, and meter wiring

### Shared parameter layer

- [WashRackShared/Parameters](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackShared/Parameters): shared AU parameter contract used by tests and the AUv3 target

### AUv3 extension

- [WashRackAudioUnit.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackAUv3Extension/WashRackAudioUnit.swift): the AU audio unit, parameter tree, state restore, and render block
- [WashRackAudioUnitViewController.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackAUv3Extension/WashRackAudioUnitViewController.swift): plugin editor lifecycle and SwiftUI hosting
- [WashRackMainView.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackAUv3Extension/WashRackMainView.swift): top-level plugin UI
- [ParameterSlider.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackAUv3Extension/ParameterSlider.swift): minimal output gain control
- [ObservableAUParameter.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackAUv3Extension/ObservableAUParameter.swift): UI-side observable wrapper around AU parameters
- [WashRackAUv3Extension-Info.plist](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackProjectSupport/WashRackAUv3Extension-Info.plist): extension metadata and AU registration

### Tests

- [WashRackParameterContractTests.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackPrototypeTests/WashRackParameterContractTests.swift): verifies addresses, names, identifiers, ranges, defaults, units, and tree shape

## Beginner-Friendly Architecture Notes

### Why the standalone app exists

It is much easier to learn DSP and signal flow in a normal macOS app first. You can load audio, hear changes immediately, and avoid host/plugin complexity while you are still learning the basics.

### Why the shared parameter contract matters

In a plugin, a knob is not just a knob. The host needs to know what the parameter is called, how it is automated, what values are legal, and how that value is restored later. A shared contract keeps that information in one place.

### Why the AUv3 shell is minimal

The AUv3 side is being built as a “boring” shell first:

- make the plugin load
- make parameters appear in the host
- make state restore work
- make one parameter affect audio correctly

That is slower at the start, but it usually leads to fewer confusing bugs later.

### Why the AU DSP is still intentionally incomplete

This project uses a vertical-slice approach. It started by proving one complete path first:

`AUParameter -> host automation -> render-safe state -> DSP -> UI readback -> project restore`

That pattern has now been extended into the retained dry-anchor plus wet-layer wash reverb Alpha slice. The remaining AU-side behaviors are still being added carefully so host automation, restore behavior, and product semantics stay stable as the plugin evolves.

## How To Build

Open:

- [WashRackPrototype.xcodeproj](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackPrototype.xcodeproj)

Useful targets:

- `WashRackPrototype`: standalone macOS app
- `WashRackAUv3Extension`: AUv3 plugin extension
- `WashRackPrototypeTests`: contract tests

## How To Explore The Project

If you are new to audio programming, a good reading order is:

1. [AudioEngineController.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackPrototype/Audio/AudioEngineController.swift)
2. [ContentView.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackPrototype/ContentView.swift)
3. [WashRackParameterSpec.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackShared/Parameters/WashRackParameterSpec.swift)
4. [WashRackParameterTreeFactory.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackShared/Parameters/WashRackParameterTreeFactory.swift)
5. [WashRackAudioUnit.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackAUv3Extension/WashRackAudioUnit.swift)
6. [WashRackAudioUnitViewController.swift](/Users/michaelquinn/Code/AudioKit/WashRackPrototype/WashRackAUv3Extension/WashRackAudioUnitViewController.swift)

That order moves from easiest concepts to the more advanced AUv3 topics.

## What Has Been Completed So Far

### Standalone prototype milestone

- AudioKit dependency added
- local AudioKit package wiring updated
- standalone prototype app created
- file import and playback implemented
- output meter implemented
- delay implemented
- low-pass filter implemented

### AUv3 foundation milestone

- shared AU parameter contract extracted
- contract tests added
- AUv3 extension target added
- minimal audio unit shell added
- host-visible parameters exposed
- AU full-state save/restore added for `Output Gain`
- minimal custom SwiftUI-based plugin UI added
- `Output Gain` render-path DSP implemented
- `Output Gain` smoothing implemented
- Live automation, UI sync, and reopen lifecycle issues fixed
- host automation startup/plateau state sync fixed

## What Is Not Done Yet

- the AU does not yet reuse the standalone AudioKit graph
- delay movement, filter behavior, input gain, and feedback are not yet product-complete in AU DSP
- broader bypass workflow and later movement-layer refinement are still ahead
- the custom plugin UI is still intentionally minimal
- beginner documentation can still grow as more phases land

## Suggested Next Learning Steps

If you are studying this project, the most natural next topics are:

- wire `inputGain` through the same AU path as `outputGain`
- add AU-side bypass behavior
- move delay and filter parameters into the AU render architecture
- decide how much DSP should stay in AudioKit graph code versus lower-level AU render code
