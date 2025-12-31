# Claude Synth: Generative Music Engine Expansion

## Overview

Transform Claude Synth from a 4-bar loop player into a full generative music creation system capable of producing original, creative, long-form instrumentals in the neo-soul/LEISURE style.

**Key Deliverables:**
- 6 new instruments (Lead, Arp, Strings, Keys, Pluck, FX)
- Song structure system with sections (Intro, Verse, Chorus, Bridge, Outro)
- Hybrid generative composition (local Markov + optional Claude API)
- Infinite/ambient mode for never-repeating generative music
- Real-time parameter evolution and pattern mutation

---

## Phase 1: Core Infrastructure

### 1.1 Song Structure & Arrangement System

**New Files:**
- `src/project/arrangement.rs` - Section and arrangement data structures
- `src/audio/timeline.rs` - Runtime section tracking

**Key Structures:**
```rust
SongSection { id, section_type, duration, intensity, patterns, transitions }
Arrangement { sections, mode (Fixed/Loop/Infinite/Generative), section_templates }
SectionTimeline { current_section_index, bars_in_section, transition_state }
```

**Modify:**
- `src/project/song.rs` - Add `arrangement: Arrangement` field
- `src/project/mod.rs` - Export arrangement module
- `src/audio/engine.rs` - Add timeline integration, section commands

### 1.2 Instrument Trait System

**New File:**
- `src/synth/instrument.rs` - Common instrument trait

```rust
trait Instrument: Send {
    fn process(&mut self, ctx: &ProcessContext) -> (f32, f32);
    fn note_on(&mut self, midi_note: u8, velocity: f32);
    fn note_off(&mut self, midi_note: u8);
    fn set_parameter(&mut self, name: &str, value: f32);
}
```

**Modify:**
- `src/synth/mod.rs` - Add LFO, export instrument trait

---

## Phase 2: New Instruments

### 2.1 LeadSynth (Monophonic Melodies)
**File:** `src/music/lead.rs`
- SuperOscillator (3 voices, 8 cents detune)
- LadderFilter with envelope
- Delayed vibrato LFO (0.3s onset)
- Portamento (50ms glide)
- Parameters: warmth, vibrato_rate, vibrato_depth, portamento

### 2.2 Arpeggiator (Rhythmic Chord Patterns)
**File:** `src/music/arp.rs`
- Takes chord input, sequences notes
- Directions: Up, Down, UpDown, Random, Order
- Tempo-synced (1/16, 1/8, dotted, triplet)
- Velocity patterns + swing
- Parameters: direction, note_value, octave_range, gate_length

### 2.3 StringPad (Lush Ensemble)
**File:** `src/music/strings.rs`
- 10 voices (vs 6 for pads)
- SuperOscillator (5 voices, 20 cents detune)
- Slow attack (1.5s), long release (3s)
- Per-voice ensemble LFO modulation
- Parameters: brightness, attack, release, ensemble_rate

### 2.4 KeysEngine (FM Rhodes/EP)
**File:** `src/music/keys.rs`
- 2-operator FM synthesis (3:1 ratio)
- Velocity-sensitive brightness
- Comping patterns (NeoSoul, Gospel, Ballad)
- 8 voices with pattern sequencer
- Parameters: brightness, fm_depth, comp_style

### 2.5 PluckSynth (Karplus-Strong)
**File:** `src/music/pluck.rs`
- Physical modeling with delay line
- Noise exciter burst
- Damping feedback filter
- 8-voice polyphony with voice stealing
- Parameters: brightness, damping

### 2.6 FXSweeps (Transitions)
**File:** `src/music/fx.rs`
- Sweep types: FilterUp, FilterDown, NoiseRiser, Impact, Swell
- Tempo-synced duration
- 4 simultaneous sweep slots
- Triggered via commands at section boundaries

### 2.7 Integration
**Modify:** `src/audio/engine.rs`
```rust
struct AudioState {
    // ... existing drums, bass, pads ...
    lead: LeadSynth,
    arp: Arpeggiator,
    strings: StringPad,
    keys: KeysEngine,
    pluck: PluckSynth,
    fx_sweeps: FXSweeps,
    // New volume controls
    lead_volume, arp_volume, strings_volume, keys_volume, pluck_volume, fx_volume: f32,
}
```

**Modify:** `src/project/song.rs` - Add TrackKind variants for new instruments

---

## Phase 3: Generative Composition System

### 3.1 Core Generation Module
**New Files:**
- `src/generation/mod.rs` - PatternGenerator trait, output types
- `src/generation/context.rs` - GenerationContext, StyleProfile
- `src/generation/markov.rs` - Order-N Markov chain with temperature

### 3.2 Pattern Generators

**Chord Progression Generator** (`src/generation/chords.rs`)
- Markov chain trained on neo-soul progressions
- Voice leading constraints (minimize semitone motion)
- Tension curves per section type
- Generate 4-16 bar progressions

**Melody Generator** (`src/generation/melody.rs`)
- Interval-based Markov chain
- Contour shapes (Arch, Wave, Ascending, etc.)
- Rhythm patterns (sparse, syncopated)
- Approach notes (chromatic, scale)

**Drum Pattern Generator** (`src/generation/rhythm.rs`)
- Style templates (leisure_main, minimal, four_floor)
- Ghost note probability
- Fill patterns for transitions
- Humanization (velocity, timing)

**Bass Line Generator** (`src/generation/bassline.rs`)
- Pattern templates (root_fifth, walking, syncopated, octave)
- Chord-aware generation
- Slide/portamento marking

### 3.3 Real-time Variation System
**File:** `src/generation/variation.rs`
- `ParameterDrift` - Slow interpolation with LFO modulation
- `PatternMutator` - Subtle per-loop variations
- Section-specific parameter targets

### 3.4 Claude API Integration (Optional)
**File:** `src/generation/api_bridge.rs`
- Response caching (50 entries)
- Structured JSON prompts for chord progressions
- Fallback to local generation if no API key
- Background/async generation (non-blocking)

### 3.5 Infinite Mode
**File:** `src/generation/arrangement.rs` - `InfiniteGenerator`
- Never-repeat algorithm with similarity detection
- Gradual tension/energy evolution
- Pattern history tracking (10 entries)
- User intent handling ("dreamier", "more energy", "surprise me")

---

## Phase 4: Section Transitions

### 4.1 Transition Types
- HardCut - Immediate switch at bar boundary
- Crossfade - Smooth gain crossover
- BuildUp - Filter sweep + noise riser
- Breakdown - Cut then rebuild
- DrumFill - Fill pattern into next section

### 4.2 TransitionEngine
**Location:** `src/audio/engine.rs`
- Manages active transition state
- Applies crossfade gains
- Generates build-up effects
- Triggers at section boundaries via timeline

---

## Phase 5: UI Integration

### 5.1 New Panels
**Modify:** `src/ui/layout.rs`
- Arrangement timeline view (show sections)
- New instrument parameters
- Generation mode indicator (Fixed/Infinite)

### 5.2 New Commands
**Modify:** `src/app.rs`
- Switch generation mode (Fixed/Infinite)
- Trigger regeneration
- Apply user intent via chat

### 5.3 Chat Integration
**Modify:** `src/ai/parser.rs`
- Parse generative commands
- "make it dreamier" → update tension/parameters
- "surprise me" → force regeneration
- "more groovy" → increase swing + syncopation

---

## Implementation Order

### Milestone 1: Song Structure (Est: 2-3 sessions)
1. Create `src/project/arrangement.rs` with SongSection, Arrangement
2. Create `src/audio/timeline.rs` with SectionTimeline
3. Update Song to include arrangement
4. Add section tracking to AudioEngine
5. Implement HardCut transitions

### Milestone 2: New Instruments (Est: 3-4 sessions)
1. Add LFO to synth module
2. Implement LeadSynth
3. Implement Arpeggiator (with chord sync)
4. Implement StringPad
5. Implement KeysEngine (FM)
6. Implement PluckSynth (Karplus-Strong)
7. Implement FXSweeps
8. Integrate all into AudioState

### Milestone 3: Local Generation (Est: 2-3 sessions)
1. Create generation module structure
2. Implement Markov chain infrastructure
3. Implement ChordProgressionGenerator
4. Implement DrumPatternGenerator
5. Implement BassLineGenerator
6. Implement MelodyGenerator
7. Add real-time variation (ParameterDrift)

### Milestone 4: Arrangement & Infinite Mode (Est: 2 sessions)
1. Implement ArrangementGenerator
2. Implement InfiniteGenerator
3. Add user intent handling
4. Integrate with chat system

### Milestone 5: API & Polish (Est: 1-2 sessions)
1. Implement Claude API bridge (optional)
2. Add response caching
3. UI updates for new features
4. Testing and tuning

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `src/project/song.rs` | Add arrangement, new TrackKinds |
| `src/project/mod.rs` | Export arrangement module |
| `src/audio/engine.rs` | Add instruments, timeline, transitions |
| `src/music/mod.rs` | Export new instrument modules |
| `src/synth/mod.rs` | Export LFO, instrument trait |
| `src/app.rs` | Generation mode, new parameters |
| `src/ui/layout.rs` | Section display, new panels |
| `src/ai/parser.rs` | Generative intent parsing |

## New Files to Create

| File | Purpose |
|------|---------|
| `src/project/arrangement.rs` | Section, Arrangement, Transition structs |
| `src/audio/timeline.rs` | Runtime section tracking |
| `src/synth/instrument.rs` | Instrument trait |
| `src/music/lead.rs` | LeadSynth |
| `src/music/arp.rs` | Arpeggiator |
| `src/music/strings.rs` | StringPad |
| `src/music/keys.rs` | KeysEngine |
| `src/music/pluck.rs` | PluckSynth |
| `src/music/fx.rs` | FXSweeps |
| `src/generation/mod.rs` | Generator traits, exports |
| `src/generation/context.rs` | GenerationContext |
| `src/generation/markov.rs` | Markov chain |
| `src/generation/chords.rs` | Chord generator |
| `src/generation/melody.rs` | Melody generator |
| `src/generation/rhythm.rs` | Drum generator |
| `src/generation/bassline.rs` | Bass generator |
| `src/generation/variation.rs` | Parameter drift, mutation |
| `src/generation/arrangement.rs` | Arrangement & infinite generators |
| `src/generation/api_bridge.rs` | Claude API integration |

---

## Success Criteria

1. **Play a 3-minute song** with Intro → Verse → Chorus → Verse → Chorus → Outro
2. **All 9 instruments playing** (Drums, Bass, Pads, Lead, Arp, Strings, Keys, Pluck, FX)
3. **Infinite mode** that runs for 10+ minutes without exact repetition
4. **Real-time parameter evolution** visible in UI
5. **Chat commands work**: "make it dreamier" actually affects the sound
6. **Section transitions** are smooth (no clicks, crossfades work)
7. **Neo-soul aesthetic** maintained throughout
