# WashRack AI Development Guide

## Purpose

This document is the canonical guidance for AI agents working in the WashRack repository.

Its job is not to describe every implementation detail. Its job is to keep future AI-assisted work aligned with the WashRack product vision, engineering constraints, and release discipline.

If you are an AI agent modifying this repository, read this guide before proposing plans, writing code, changing parameters, or expanding scope.

## Decision Hierarchy

When making decisions, use this order:

1. Preserve the WashRack product vision.
2. Preserve the public AU parameter contract.
3. Preserve host automation, state restoration, and reopen reliability.
4. Preserve render-thread safety.
5. Prefer small vertical slices over broad architectural rewrites.
6. Improve code only when it helps the product, the contract, or long-term maintainability.

If a tempting change violates any item above, do not make it unless the product direction is explicitly redefined.

## Product Vision

### What WashRack Is

WashRack is a workflow-first AUv3 transition effect for macOS producers working primarily in Logic Pro and Ableton Live.

It is designed to help producers create buildups, transitions, breakdowns, and drops that feel bigger and more energized without losing groove, timing reference, or session trust.

At its core, WashRack is built around:

- a retained dry anchor
- a musical wet movement layer
- automation-friendly controls
- dependable host save and restore behavior
- a small, intentional control set

### Long-Term Wet-Layer Vision

Long term, WashRack's wet movement layer should evolve as one coordinated musical layer made of:

- wash reverb for size and lift
- delay for motion and momentum
- filter movement for tonal shaping and transition tension

These are not meant to become three loosely related mini-plugins inside one shell. They should behave like one transition-writing system wrapped around the retained dry anchor.

For the current MVP and immediate post-Alpha work, filter behavior remains deferred. Delay movement and real-session workflow validation come first. Future filter work is expected as part of the product's long-term evolution, but only when it strengthens the coordinated wet-layer concept rather than expanding WashRack into a generic effect rack.

### What WashRack Is Not

WashRack is not:

- a generic multi-effects suite
- a modular routing playground
- a parameter-maximizing DSP experiment
- a preset-first sound design platform
- a cross-platform strategy project
- a UI spectacle looking for a product

The product wins by being focused, musical, and trustworthy inside a producer's normal workflow.

### Target User

The target user is a macOS-based electronic music producer or DJ working in Ableton Live 12+ or Logic Pro who regularly writes transitions and wants faster results with less setup friction.

This user typically:

- wants transitions that stay rhythmically grounded
- prefers a few reliable controls over a large matrix of options
- writes automation in the DAW timeline
- values repeatable results over deep experimentation during arrangement

Beginner plugin developers may study this repository, but the product is for producers first.

### Producer Workflow Philosophy

WashRack should feel like a tool a producer reaches for during real arrangement work, not a side quest.

That means:

- the plugin should be quick to understand
- the important controls should reward automation
- the dry signal should continue to carry the groove
- the effect should help a section move forward, not smear the track into mush
- the host should remain the source of truth for automation and recall

The standard product question is not "what else can this plugin do?"

The standard product question is "does this make transition writing feel better, faster, and more musical?"

## Product Principles

### Retained Dry Signal Is a Core Invariant

WashRack is built on a retained dry anchor. `dryWetMix` is not a full dry/wet crossfade that removes the original signal. The product identity depends on preserving enough dry signal to keep pulse, timing, and anticipation intact.

Any change that turns WashRack into a wash-only effect is a product regression unless the product direction is explicitly rewritten.

### Product Decisions Outweigh DSP Cleverness

A more sophisticated algorithm is not automatically a better product decision.

Prefer the solution that better supports:

- producer confidence
- predictable automation
- groove preservation
- host reliability
- faster musical decisions

Reject changes that are technically interesting but product-diluting.

### Small Musical Workflow Beats Large Configurability

WashRack should earn trust through a compact, coherent workflow.

Do not add parameters, modes, or alternate behaviors just because the DSP can support them. New controls need product justification tied to real producer value.

### Prefer Automation Feel Over Parameter Count

WashRack lives or dies by how it behaves under automation.

The product should privilege:

- smooth ramps
- predictable transitions
- clear host-visible semantics
- easy writing in Ableton and Logic

A smaller number of automation-friendly parameters is better than a wide surface area that feels vague or brittle.

### Preserve Groove

Transitions should increase energy without erasing rhythmic identity.

If a change makes builds feel larger but less anchored, less punchy, or less readable, treat that as a product risk, not a cosmetic difference.

### Filters Serve Transition Movement, Not Standalone Tone Surgery

Filter work belongs in WashRack's future only when it supports:

- buildups
- tension shaping
- tonal motion
- coordinated interaction with reverb and delay

Filter work does not justify turning WashRack into a standalone EQ, surgical filter, or generic sweep plugin. If a proposed filter feature reads like independent channel processing rather than transition movement design, it is probably outside product scope.

## Engineering Principles

### Stable AU Parameter Contract

The AU parameter contract is a public product interface.

The current contract includes these host-visible parameters:

- `inputGain`
- `outputGain`
- `delayTime`
- `feedback`
- `dryWetMix`
- `lowPassCutoff`
- `lowPassResonance`
- `effectEnabled`

For these parameters, stability matters across:

- addresses
- identifiers
- names
- ranges
- defaults
- units
- flags

Do not change those casually. Changes here can break automation lanes, saved projects, UI bindings, tests, and user trust.

### Render-Safe DSP

Audio render code must stay production-safe.

Do not introduce:

- allocation in the render path
- locks
- blocking work
- file I/O
- logging
- main-thread hops
- host lifecycle assumptions inside DSP code

Use render-safe mirrored state for host-controlled values. Apply smoothing where audible zippering or discontinuity would harm automation feel.

### Incremental Vertical Slices

WashRack should continue to evolve in narrow end-to-end slices.

Preferred pattern:

1. define product behavior
2. confirm parameter semantics
3. wire host-visible control path
4. implement render-safe behavior
5. validate UI sync
6. validate save/restore
7. validate in Logic and Ableton

Avoid large speculative rewrites that move many layers at once.

For filter-related work specifically, do not pull implementation ahead of product validation. The correct order remains:

1. retained dry topology
2. wash reverb behavior
3. delay movement
4. loudness and workflow tuning
5. filter exploration inside the coordinated wet layer

### Testability

Important behavior should be encoded in tests when practical, especially:

- parameter contract stability
- topology semantics
- state restoration behavior
- smoothing-sensitive control behavior
- core helper logic with deterministic outcomes

Tests should protect product intent, not just implementation trivia.

### State Restoration Is a Feature

Project reopen behavior is part of the product.

Anything that affects:

- `fullState`
- parameter default handling
- host-visible values
- UI startup sync
- restore ordering

must be treated as product-critical work.

If a producer reopens a project and WashRack behaves differently, the feature is not complete.

### Logic + Ableton Validation

WashRack is intentionally host-first. Logic Pro and Ableton Live are not optional compatibility targets. They are the primary product environment.

When a change affects host-visible behavior, success is not real until it has been validated in those hosts.

## AI Development Principles

### Never Expand Scope Without Product Justification

Do not turn a targeted request into:

- a new control surface
- a new DSP subsystem
- a broad refactor
- a new host strategy
- a redesign of product semantics

unless there is explicit product reasoning for it.

AI agents should resist the common failure mode of "while we are here" expansion.

This is especially important for filter requests. A request to explore or refine filter behavior is not permission to:

- redesign the plugin around filter macros
- promote filter control ahead of delay movement
- add standalone EQ-style workflows
- expand the AU contract without explicit product approval

### Prefer Planning Before Coding

Before implementation, identify:

- the user-facing workflow being improved
- the public contract at risk
- the validation path
- what is intentionally out of scope

If the work touches product behavior, host semantics, or parameter meaning, planning is required before code changes.

### Preserve Backward Compatibility

Backward compatibility matters most for:

- AU parameter addresses
- identifiers
- names and units
- automation semantics
- state restoration
- host project reopen behavior

Prefer additive or internal changes over breaking public behavior.

If a breaking change is truly needed, it should be called out explicitly as a product decision, not hidden inside implementation work.

### Keep DSP Helpers Replaceable

Internal DSP structures should be allowed to evolve.

That means AI agents should avoid entangling:

- parameter metadata
- host plumbing
- UI state
- DSP internals

in ways that make future replacement hard.

Internal DSP code can change. The product contract should not churn with it.

### Separate Public Contracts From Internal Implementation

Public contract layers should remain explicit and stable.

Examples of public or semi-public contracts:

- shared parameter specs
- parameter addresses and identifiers
- host-visible semantics
- state restoration keys and behavior
- UI meaning of exposed controls

Examples of internal implementation:

- specific reverb tuning
- helper object boundaries
- smoothing implementation details
- internal wet-layer algorithms

AI agents should preserve this separation so internal experiments do not leak into the product interface.

### Ask "What Producer Workflow Improves?" Before Any DSP Work

Before implementing or expanding DSP behavior, answer:

- what producer action becomes easier?
- what arrangement or automation workflow improves?
- how does this preserve or improve groove?
- why does this deserve to exist before another control is added?

If the answer is mostly technical curiosity, the work is not product-ready.

For future filter work, the expected answer should sound like:

- this improves buildup writing
- this reduces the need to stack an external transition-filter tool
- this shapes the wet movement layer without removing the dry anchor

If the answer sounds more like "this makes WashRack a better filter," the direction is probably wrong.

## PR Expectations

Every PR should clearly state:

- what producer workflow or product behavior it improves
- whether the AU parameter contract changed
- whether host automation semantics changed
- whether state restoration behavior changed
- what tests were run
- what manual host validation was run
- what remains intentionally out of scope

### Expected Test Coverage

PRs should add or update tests when they affect:

- shared parameter metadata
- control-state semantics
- wet-layer topology rules
- render-safe helper logic
- state restoration behavior

If a behavior is important but hard to automate, the PR should at least document the manual validation performed.

### When Manual Ableton Validation Is Required

Manual Ableton validation is required when a PR changes:

- host-visible parameter behavior
- automation timing or smoothing
- state restoration or reopen behavior
- UI-to-parameter synchronization
- effect enable semantics
- dry/wet semantics
- output gain behavior
- render-path DSP that affects audible automation results

Recommended validation:

- load the plugin
- confirm parameters appear correctly
- write automation
- play back automation
- save and reopen the project
- confirm audio behavior and visible control state still match

### When Manual Logic Validation Is Required

Manual Logic validation is required for the same categories as Ableton.

WashRack should not assume one host's behavior generalizes cleanly to the other. If the PR changes host-facing behavior, both should be checked when feasible.

## Planning Workflow

The default development workflow for meaningful feature work is:

`PM Review -> Plan Mode -> Implementation -> Tests -> Ableton/Logic Validation -> Producer Evaluation -> Retrospective`

### PM Review

Confirm the request matches the WashRack product direction.

Questions to answer:

- is this a workflow improvement or just more functionality?
- does it preserve retained dry identity?
- is it the right next slice for the product?

### Plan Mode

Define:

- product behavior
- public contract impact
- implementation boundaries
- test strategy
- host validation strategy

The plan should explicitly name what is not being changed.

### Implementation

Implement the smallest viable vertical slice that proves the behavior end to end.

Prefer explicit code over clever abstractions when the code touches product-critical AU behavior.

### Tests

Protect the contract and the intended semantics. Do not rely on manual memory alone for rules that can be encoded.

### Ableton/Logic Validation

Validate host loading, automation, UI readback, and reopen behavior in the primary DAWs whenever host-visible behavior is affected.

### Producer Evaluation

Ask whether the result feels useful in a real transition-writing workflow.

Passing tests is not enough if the feature makes the product slower, noisier, or less musical.

### Retrospective

Capture what was learned:

- did the slice improve workflow?
- did the contract stay stable?
- what surprised us in hosts?
- what should be deferred rather than expanded now?

## Product Roadmap Philosophy

WashRack should research and validate producer workflow before adding more controls.

This is deliberate.

Reasons:

- more controls can dilute the product identity
- more parameters increase automation complexity
- more public contract surface creates long-term compatibility cost
- host trust is harder to maintain as semantics multiply
- strong workflow products usually beat broad-but-blurry effect suites

The roadmap should therefore favor:

- validating the retained dry transition concept
- tuning the existing workflow
- confirming real-session usefulness
- adding controls only when user workflow clearly demands them

Do not treat unused room in the UI or spare DSP capacity as a reason to expand the product.

Current long-term intent should be interpreted this way:

- reverb is the primary wash behavior
- delay is the next movement priority
- filter movement is a later layer of tonal tension and shaping
- all three should eventually behave as one coordinated wet-layer system

That is a product evolution path, not a mandate to build every layer immediately.

## Future Architecture

WashRack's internal DSP should be allowed to evolve while preserving the public AU contract.

That means the following may change over time:

- internal wet-layer implementation
- reverb algorithm details
- delay architecture
- gain staging approach
- shared-core boundaries between prototype and AU
- helper types and object ownership

The following should remain stable unless there is an explicit product migration decision:

- parameter addresses
- parameter identifiers
- host-visible control meanings
- retained dry-anchor product identity
- host automation expectations
- state restoration behavior

### Architectural Direction

The preferred long-term direction is:

- shared product semantics across standalone prototype and AU
- increasing reuse of DSP behavior where it improves clarity
- continued separation of host plumbing from DSP core behavior
- flexible internal helpers behind a stable host-facing contract
- long-term coordination of reverb, delay, and filter behavior inside one wet movement layer

The goal is not to freeze the internals. The goal is to keep evolution from breaking the parts producers and hosts depend on.

## Default AI Checklist

Before making a change, an AI agent should confirm:

- does this help the producer workflow?
- does this preserve the retained dry identity?
- does this change the public AU contract?
- does this affect automation, restore, or reopen behavior?
- does this require Logic and Ableton validation?
- is the scope still a small vertical slice?
- did I avoid adding controls without product justification?

If any answer is unclear, stop and clarify the product intent before changing the code.
