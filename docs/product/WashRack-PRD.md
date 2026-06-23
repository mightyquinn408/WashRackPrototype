# Wash Rack AUv3

- Document Status: Draft
- Product Owner: Mike Quinn
- Last Updated: 2026-06-18

## Product Vision

WashRack is a workflow-first transition effect for electronic music production and performance. The product should help a producer or DJ create energetic build-ups, transitions, and drops without destroying the groove, swallowing the dry signal, or requiring a large multi-effect routing setup.

The long-term vision is a focused "wash" tool that feels immediate and musical in a DAW, especially in Logic Pro and Ableton Live, rather than a broad generic multi-effects plugin with dozens of disconnected modes.

## Target User

The primary user is a macOS-based electronic music producer working in Ableton Live 12+ or Logic Pro who wants a fast, reliable transition effect during arrangement, automation writing, and performance-oriented editing.

Typical user traits:

- creates buildups, risers, breakdowns, and drop transitions regularly
- wants a retained dry path so the track keeps its pulse and timing reference
- prefers a few high-value controls over a deep modular interface
- automates effects from the DAW timeline rather than treating the plugin as a sound-design playground

Secondary users include beginner audio plugin developers studying a clear AUv3 architecture, but product decisions should optimize for the music workflow first.

## Problem Statement

Many transition plugins create excitement by washing out the signal, but they often over-process the source, flatten rhythmic definition, or encourage generic "everything-on" builds. Producers who want smoother, groove-preserving transitions usually end up stacking multiple plugins for reverb, filtering, delay, and gain staging, then manually balancing the dry signal.

WashRack should solve this by giving the user one focused transition tool built around:

- retained dry signal
- musical wash reverb
- controllable filter movement
- optional delay movement
- easy host automation

The intended inspiration is the D. Ramirez workflow: preserve the groove, keep the dry path grounded, then add wash, motion, and tension around it.

## Product Principles

- Workflow over feature count: every control should support fast transition writing and automation.
- Preserve groove: the dry path should remain strong enough to keep timing, impact, and dancefloor energy intact.
- Host-first behavior: automation, save/restore, and reopen reliability are required product behaviors, not implementation details.
- Focused effect identity: WashRack should feel like a transition tool, not a grab-bag multi-effects rack.
- Boring architecture, musical results: implementation should prefer clear, stable AUv3 patterns over clever abstractions.
- macOS AUv3 first: prioritize the plugin experience in Logic Pro and Ableton Live before any broader platform ambitions.

## Current Project Status

Completed:

- AUv3 shell
- parameter contract
- host automation
- state restoration
- output gain vertical slice

In Progress:

- DSP feature implementation

## Core Product Concept

WashRack is a transition processor centered on a retained dry signal plus an automatable wet movement layer. The user should be able to increase size, tension, and motion across a phrase while still hearing enough of the source track to preserve groove and anticipation.

At the product level, the expected feel is:

- dry signal remains anchored
- wash reverb adds scale and lift
- filter movement pushes energy upward or downward
- optional delay adds motion and depth
- enable/bypass behavior makes insertion easy in real sessions

Current Alpha AU slice:

- `effectEnabled = 0` means dry anchor straight to the output stage
- `effectEnabled = 1` means dry anchor plus a separate wet movement layer
- `dryWetMix` controls wet-layer amount under the retained dry anchor
- `dryWetMix` is not a full dry/wet crossfade that fades the dry path away
- the wet layer currently uses a mirrored-input placeholder with low-pass filter movement before reverb and delay are made product-complete
- `lowPassCutoff` and `lowPassResonance` act on the wet layer only; the dry anchor remains untouched
- the minimal AU editor exposes `Effect Enabled`, `Dry/Wet Mix`, `Low-Pass Cutoff`, `Low-Pass Resonance`, and `Output Gain` for in-host validation

## Core Features

### Dry Path Retention

Dry-path retention is a core product behavior, not a mix option added late. The plugin should preserve a meaningful amount of original signal during transition building so drums, syncopation, and transient timing remain readable.

Requirements:

- the dry path should remain intentionally audible in typical transition usage
- wash effects should layer around the dry source instead of replacing it by default
- product tuning should avoid the common failure mode where the source disappears too early
- `dryWetMix = 0%` should produce dry anchor only
- `dryWetMix = 100%` should produce maximum wet-layer contribution while the dry anchor remains audible

### Wash Reverb

Wash reverb is the primary spatial effect. It should create width, lift, and scale during buildups and breakdown transitions without turning into a generic "hall reverb plugin."

Requirements:

- reverb character should support musical wash and upward energy
- controls should be automation-friendly and not require deep menu diving
- wet behavior should combine naturally with retained dry signal

### Filter Movement

Filter movement is a core transition mechanism. It should help shape tension and release while supporting the retained-dry philosophy.

Requirements:

- low-pass movement should support classic sweep-down and tension-control workflows
- resonance/Q should be musical and predictable under automation
- filter behavior should complement reverb and delay instead of fighting them

### Delay Movement

Delay is optional movement, not the center of the product. It should add motion, repeats, and excitement when needed, while remaining secondary to the wash concept.

Requirements:

- delay should support transition motion and rhythmic lift
- feedback and wet balance should remain safe and automation-friendly
- the product should still feel complete even when delay use is minimal

### Effect Enable / Bypass

Effect enable/bypass should support real session workflow and automation clarity.

Requirements:

- bypass should behave predictably in hosts
- effect enable should support arrangement and comparison workflows
- toggling the effect should not create avoidable surprises in project recall or automation playback
- `effectEnabled` should control the WashRack movement layer rather than relying on host bypass
- when `effectEnabled = 0`, the signal should pass through the output stage as dry anchor only

## Product Differentiation

WashRack should differentiate through focus and workflow, not through the number of algorithms.

### Compared to Endless Smile

The intended positioning is similar in outcome, but WashRack should be more explicit about retained dry signal, groove preservation, and host-automation clarity. The goal is not to clone a one-knob macro wash effect. The goal is to give the user enough control to shape transitions musically while keeping the product immediate.

### Compared to Toolroom Infinite

WashRack should compete by being narrower, faster, and more automation-native. Rather than presenting as a broad cinematic transition environment, it should feel like a practical production tool for writing arrangements inside Logic and Ableton with a small set of dependable controls.

## Technical Architecture Goals

### Stable Parameter Contract

AU parameters are the product contract between:

- host automation
- plugin UI
- DSP/render code
- state restoration
- future preset behavior

Requirements:

- stable parameter addresses and identifiers
- host-visible names, ranges, defaults, and units defined in one shared layer
- no SwiftUI-only product state for automatable controls

### Real-Time Safety

The render path must remain safe for production host use.

Requirements:

- no allocation, locks, file I/O, logging, or UI work in the render callback
- DSP parameter updates must use render-safe mirrored state
- smoothing should be applied where needed to avoid zipper noise

### Shared DSP Core

The long-term architecture should converge toward a shared DSP core or at least shared DSP behavior between the standalone prototype app and the AUv3 plugin. Product behavior should not drift into two unrelated implementations.

Requirements:

- reuse logic where practical
- keep host-specific AU code separate from core signal behavior
- make future DSP slices portable between prototype and plugin where it supports clarity

## MVP Success Criteria

The MVP is successful when:

- the plugin loads reliably as a macOS AUv3 effect in Logic Pro and Ableton Live 12+
- the core transition workflow feels musical and repeatable
- retained dry signal clearly preserves groove during builds
- wash reverb, filter movement, and delay movement work as a coherent effect concept
- host automation is smooth, visible, and project-safe
- project reopen restores parameters and expected behavior reliably
- the plugin feels like a focused transition tool rather than a generic effects bundle

## Recommended Development Order

### Foundation (Completed)

Completed foundation work:

- standalone AudioKit prototype app
- AUv3 shell
- shared parameter contract
- host-visible automation plumbing
- state restoration
- custom AU editor shell
- `Output Gain` end-to-end vertical slice

This phase has already de-risked the main AUv3 integration concerns and established the architectural pattern for future DSP slices.

### Wash Rack Alpha

Alpha should focus on making the core product concept real in the AU:

1. prove retained dry-anchor plus wet-layer AU topology
2. define AU-side `Effect Enabled` semantics as movement-layer enable, not host bypass
3. define `Dry/Wet Mix` semantics as wet-layer amount under a retained dry anchor
4. ship the first wet-layer placeholder using mirrored input with no hidden gain compensation
5. validate automation and recall in Logic and Ableton for `Effect Enabled`, `Dry/Wet Mix`, and `Output Gain`
6. defer filter, wash reverb, delay movement, and loudness balancing to later slices

Alpha outcome:

- the plugin proves the retained dry-path product concept in-host
- `effectEnabled = 0` produces dry input through the output stage
- `effectEnabled = 1` plus `dryWetMix` adds a wet-layer placeholder without removing the dry anchor
- louder output at `dryWetMix = 100%`, including an approximately `+6 dB` summed result from correlated dry plus mirrored wet, is expected in this proof slice and deferred for later tuning
- DAW automation and state recall remain trustworthy for the parameters used in the slice

### Beta

Beta should focus on product fit, polish, and confidence:

1. add wash reverb behavior to the wet layer
2. add delay movement as a secondary wet-layer element
3. tune gain staging and perceived loudness across transitions
4. improve the custom UI for production usability
5. expand test coverage for state restore and parameter behavior
6. evaluate whether DSP should consolidate further into a shared core
7. decide when the standalone graph should align with the AU architecture
8. run repeated host validation passes in Logic and Ableton on real projects

Beta outcome:

- the plugin feels intentional and production-ready for real transition writing
- workflow is fast enough that users reach for it by default
- the product identity is clear before broader release planning

## Non-Goals (MVP)

The MVP should not try to be:

- a cross-platform plugin strategy
- a VST3, AAX, or Windows product
- an iOS-first product
- a generic all-purpose multi-effects suite
- a highly modular routing environment
- a deep preset ecosystem
- a large custom UI redesign before core DSP behavior is proven

The immediate goal is a macOS AUv3 transition tool with strong host behavior and a clear musical identity.
