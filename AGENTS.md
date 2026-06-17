# AGENTS.md

This file provides guidance to Codex when working with code in this repository.

## Project Overview

WashRackPrototype is a macOS-only audio effect prototype built in small phases.

The project currently has two active layers:

- a standalone AudioKit app for quick DSP experimentation
- an AUv3 extension that is being built as a careful vertical slice

The most important architectural boundary in this repo is the shared AU parameter contract in `WashRackShared/Parameters`. That contract must stay stable across the host, plugin UI, state restoration, and render code.

## Current Intentional Limitations

Treat these as known project state, not as bugs by default:

- Only `outputGain` is currently wired all the way through the AU render path.
- The other shared AU parameters are intentionally exposed to hosts before their AU-side DSP is implemented.
- The custom AU UI is intentionally minimal.
- The standalone app signal chain is not yet reused inside the AU implementation.

Do flag a problem if a change claims to implement one of these areas but leaves the end-to-end path broken or inconsistent.

## Review Guidelines

When reviewing pull requests, prioritize high-signal correctness issues over style feedback.

Focus most on:

- AU parameter contract stability. Changes to addresses, identifiers, names, ranges, defaults, units, or flags can break host automation and project restoration.
- Host automation behavior. Parameter updates must stay correct for live automation, reopen/restore, and UI readback.
- Render-thread safety. Avoid allocations, locks, blocking work, main-thread hops, file I/O, logging spam, or other non-realtime-safe work inside the audio render path.
- State restoration. `fullState`, parameter defaults, and startup sync should not cause jumps, resets, or fallback-to-default behavior when reopening host projects.
- UI and audio-unit lifecycle correctness. Be careful around `AUAudioUnit` creation, view-controller attachment, host reopen flows, and synchronization between the editor and the audio unit.
- Channel and bus assumptions. Changes should not silently break the current stereo-oriented AU setup or in-place processing expectations.
- Beginner-friendly architecture. Prefer small, explicit, understandable steps over clever abstractions that hide how AUv3 wiring works.

De-emphasize or avoid:

- generic style nits unless they affect clarity or correctness
- requests to fully implement still-intentional missing DSP paths
- suggestions that collapse the teaching-oriented step-by-step structure without a strong payoff

## Change Guidance

If a PR touches the shared parameter layer, verify all affected places stay aligned:

- `WashRackParameterAddress.swift`
- `WashRackParameterSpec.swift`
- `WashRackParameterTreeFactory.swift`
- `WashRackAudioUnit.swift`
- AU UI bindings in `WashRackAUv3Extension`
- tests in `WashRackPrototypeTests`

If a PR touches AU parameter behavior, check the full path:

`AUParameter -> host automation -> render-safe state -> DSP -> UI readback -> project restore`

If a PR touches the standalone app, preserve the current audible signal flow unless the PR explicitly changes it:

`AudioPlayer -> Delay -> LowPassFilter -> Output`

## Validation Commands

Use these commands from the repository root:

```bash
# Build the macOS app target
xcodebuild -project WashRackPrototype.xcodeproj -scheme WashRackPrototype -destination 'platform=macOS'

# Run the current test suite
xcodebuild -project WashRackPrototype.xcodeproj -scheme WashRackPrototype -destination 'platform=macOS' test

# Build only the AUv3 extension target
xcodebuild -project WashRackPrototype.xcodeproj -target WashRackAUv3Extension build
```

Prefer focused validation that matches the files changed. For parameter-contract work, the test target is especially important. For AU lifecycle or render-path changes, the AUv3 extension build is important even if tests are unchanged.

## Notes For Codex Reviews

Useful review comments in this repo usually answer one of these:

- Could this break host-visible parameter stability?
- Could this desynchronize host automation, UI state, or restored state?
- Could this cause audio glitches or unsafe work on the realtime thread?
- Could this make the AU load, reopen, or attach its UI less reliably in hosts?

If none of those are at risk, keep review feedback brief.
