# Claude Synth - Implementation Plan

## Overview
A TUI-based music creation tool for crafting LEISURE-style neo-soul tracks with embedded Claude AI for natural language parameter control.

## Technology Stack
| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | Rust | <5ms latency for real-time audio |
| TUI | ratatui + crossterm | Best performance, OpenCode-style elegance |
| Audio I/O | cpal | Cross-platform, Core Audio on macOS |
| Synthesis | fundsp | Functional DSP, bandlimited oscillators |
| Thread Comm | rtrb | Lock-free ring buffer for audio thread |
| AI | anthropic-sdk or reqwest | Claude API for embedded chat |
| Serialization | serde + ron | Human-readable project files |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        TUI Layer                            │
│  ┌─────────┐ ┌──────────┐ ┌─────────┐ ┌─────────────────┐  │
│  │ Tracks  │ │ Params   │ │Transport│ │  Claude Chat    │  │
│  │ Panel   │ │ Editor   │ │ + Wave  │ │  Panel          │  │
│  └─────────┘ └──────────┘ └─────────┘ └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                    Message Passing (crossbeam)
                              │
┌─────────────────────────────────────────────────────────────┐
│                      App State                              │
│  Song { tracks, tempo, key, swing } + UI State + AI State   │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
       Lock-free Ring    HTTP Client    File I/O
        Buffer (rtrb)     (reqwest)      (tokio)
              │               │               │
┌─────────────▼───┐  ┌────────▼────┐  ┌───────▼──────┐
│  Audio Thread   │  │ Claude API  │  │   Projects   │
│  (cpal+fundsp)  │  │  (Anthropic)│  │   (.ron)     │
└─────────────────┘  └─────────────┘  └──────────────┘
```

## Project Structure

```
claude-synth/
├── Cargo.toml
├── src/
│   ├── main.rs              # Entry point, app loop
│   ├── app.rs               # App state, message handling
│   ├── ui/
│   │   ├── mod.rs
│   │   ├── layout.rs        # Main layout composition
│   │   ├── tracks.rs        # Track list panel
│   │   ├── params.rs        # Parameter editor
│   │   ├── transport.rs     # Play/stop, BPM, position
│   │   ├── waveform.rs      # Real-time waveform viz
│   │   ├── chat.rs          # Claude chat panel
│   │   └── theme.rs         # Colors, styling
│   ├── audio/
│   │   ├── mod.rs
│   │   ├── engine.rs        # Audio thread, cpal setup
│   │   ├── mixer.rs         # Multi-track mixing
│   │   └── buffer.rs        # Ring buffer communication
│   ├── synth/
│   │   ├── mod.rs
│   │   ├── oscillator.rs    # Saw, sine, square, noise
│   │   ├── filter.rs        # LPF, HPF, resonance
│   │   ├── envelope.rs      # ADSR
│   │   ├── lfo.rs           # Modulation sources
│   │   ├── voice.rs         # Polyphonic voice manager
│   │   └── effects.rs       # Reverb, delay, compression
│   ├── music/
│   │   ├── mod.rs
│   │   ├── theory.rs        # Scales, chords, modes
│   │   ├── chord_prog.rs    # Progression generator
│   │   ├── drums.rs         # Pattern sequencer + swing
│   │   ├── bass.rs          # Bass line generator
│   │   └── pads.rs          # Pad voicing engine
│   ├── ai/
│   │   ├── mod.rs
│   │   ├── client.rs        # Anthropic API
│   │   ├── parser.rs        # NL → parameter mapping
│   │   └── context.rs       # Song state for prompts
│   └── project/
│       ├── mod.rs
│       ├── song.rs          # Song data structure
│       ├── preset.rs        # Factory presets
│       └── io.rs            # Save/load (.ron files)
└── presets/
    ├── moody_afternoon.ron
    ├── late_night_groove.ron
    └── bright_dream.ron
```

## Key Data Structures

### Song State
```rust
pub struct Song {
    pub name: String,
    pub tempo: Tempo,
    pub key: Key,
    pub time_sig: TimeSignature,
    pub tracks: Vec<Track>,
}

pub struct Tempo {
    pub bpm: f32,           // 60-200, default 88
    pub swing: f32,         // 0.0-1.0, default 0.6
    pub swing_resolution: SwingRes, // Eighth, Sixteenth
}

pub struct Key {
    pub root: Note,         // C, C#, D, ...
    pub mode: Mode,         // Major, Minor, Dorian, etc.
}
```

### Track Types
```rust
pub enum Track {
    Drums(DrumTrack),
    Bass(BassTrack),
    Pads(PadTrack),
    Lead(LeadTrack),
}

pub struct PadTrack {
    pub synth: PadSynth,
    pub progression: ChordProgression,
    pub volume: f32,
    pub pan: f32,
    pub effects: EffectChain,
}

pub struct PadSynth {
    pub warmth: f32,        // 0.0=bright, 1.0=warm (controls LPF)
    pub attack: f32,        // 0.1-2.0s
    pub release: f32,       // 0.5-3.0s
    pub detune: f32,        // 0.0-0.5 (oscillator spread)
    pub osc_mix: OscMix,    // Saw/Square/Sine blend
}
```

### Audio Messages (Lock-free)
```rust
pub enum AudioMessage {
    Play,
    Stop,
    SetTempo(f32),
    SetTrackParam { track_id: usize, param: ParamChange },
    NoteOn { track_id: usize, note: u8, velocity: f32 },
    NoteOff { track_id: usize, note: u8 },
}

pub enum UiMessage {
    WaveformData(Vec<f32>),
    PlaybackPosition(f64),
    AudioError(String),
}
```

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
- [ ] Project setup with Cargo workspace
- [ ] Basic TUI shell with ratatui (empty panels)
- [ ] cpal audio output test (sine wave)
- [ ] Ring buffer communication scaffold

**Deliverable**: TUI that plays a test tone

### Phase 2: Core Synthesis (Week 3-4)
- [ ] FunDSP oscillators (saw, sine, square)
- [ ] ADSR envelope implementation
- [ ] LPF with resonance
- [ ] Single voice playback
- [ ] Polyphonic voice manager (8 voices)

**Deliverable**: Play chords with synth sounds

### Phase 3: Music Engine (Week 5-6)
- [ ] Music theory module (scales, chords)
- [ ] Chord progression data structure
- [ ] Drum pattern sequencer with swing
- [ ] Bass line generator (root + fifth patterns)
- [ ] Pad voicing engine

**Deliverable**: Full 4-bar loop with drums/bass/pads

### Phase 4: Effects & Polish (Week 7-8)
- [ ] Reverb (FunDSP built-in or custom)
- [ ] Delay with feedback
- [ ] Compression/limiting
- [ ] Sidechain (kick → pad ducking)
- [ ] Real-time waveform visualization

**Deliverable**: Professional-sounding output

### Phase 5: TUI Excellence (Week 9-10)
- [ ] OpenCode-inspired layout
- [ ] Parameter sliders (Unicode blocks)
- [ ] Track list with selection
- [ ] Transport controls (space=play/stop)
- [ ] Keyboard shortcuts
- [ ] Color theming

**Deliverable**: Beautiful, usable interface

### Phase 6: Claude Integration (Week 11-12)
- [ ] Anthropic API client
- [ ] Chat panel UI
- [ ] Song context serialization for prompts
- [ ] Natural language → parameter parser
- [ ] Streaming response display
- [ ] "Make it dreamier" → warmth++, reverb++

**Deliverable**: Full AI-assisted workflow

### Phase 7: Presets & Export (Week 13+)
- [ ] LEISURE-style factory presets
- [ ] Project save/load (.ron)
- [ ] WAV export
- [ ] MIDI export (optional)

## LEISURE-Style Defaults

```rust
// Moody Afternoon preset
Tempo { bpm: 88.0, swing: 0.65, swing_resolution: Sixteenth }
Key { root: E, mode: Dorian }
PadSynth {
    warmth: 0.8,      // Very warm (20% LPF cutoff)
    attack: 0.8,      // 800ms
    release: 1.5,     // 1.5s
    detune: 0.15,     // Slight chorus effect
}
DrumTrack {
    pattern: "kick_offbeat",
    velocity_variation: 0.4,
    timing_humanize: 0.02,  // ±20ms
}
Effects {
    reverb_mix: 0.2,
    delay_feedback: 0.3,
    sidechain_amount: 0.4,
}
```

## Key Dependencies (Cargo.toml)

```toml
[dependencies]
# TUI
ratatui = "0.29"
crossterm = "0.28"

# Audio
cpal = "0.15"
fundsp = "0.18"
rtrb = "0.3"            # Lock-free ring buffer

# Async
tokio = { version = "1", features = ["full"] }

# AI
reqwest = { version = "0.12", features = ["json", "stream"] }
futures = "0.3"

# Serialization
serde = { version = "1", features = ["derive"] }
ron = "0.8"

# Utils
anyhow = "1"
tracing = "0.1"
```

## UI Layout (ASCII Mockup)

```
┌─ Claude Synth ──────────────────────────────────────────────────┐
│ ┌─ Tracks ─────┐ ┌─ Parameters ──────────────────────────────┐  │
│ │ ▸ Drums      │ │ PADS - Warm Synth                         │  │
│ │   Bass       │ │                                           │  │
│ │ ● Pads ←     │ │ Warmth    [████████░░] 80%               │  │
│ │   Lead       │ │ Attack    [████░░░░░░] 800ms             │  │
│ │              │ │ Release   [██████░░░░] 1.5s              │  │
│ │              │ │ Detune    [██░░░░░░░░] 15%               │  │
│ │              │ │                                           │  │
│ │ + Add Track  │ │ ─ Effects ─                               │  │
│ │              │ │ Reverb    [████░░░░░░] 20%               │  │
│ │              │ │ Delay     [███░░░░░░░] 30%               │  │
│ └──────────────┘ └───────────────────────────────────────────┘  │
│ ┌─ Transport ───────────────────────────────────────────────┐   │
│ │ ▶ PLAYING   ♩ 88 BPM   Key: E Dorian   Swing: 65%        │   │
│ │ ▁▂▃▅▆▇█▇▅▃▂▁▂▄▆▇█▇▆▄▂▁  [====●===============] 1:24     │   │
│ └───────────────────────────────────────────────────────────┘   │
│ ┌─ Claude ──────────────────────────────────────────────────┐   │
│ │ You: make it more dreamy and spacious                     │   │
│ │ Claude: I've increased the reverb to 35%, added more      │   │
│ │ delay feedback, and softened the attack. The pads now     │   │
│ │ have a more ethereal, floating quality.                   │   │
│ │ > _                                                       │   │
│ └───────────────────────────────────────────────────────────┘   │
│ [Space] Play/Stop  [Tab] Switch Panel  [?] Help  [Q] Quit       │
└─────────────────────────────────────────────────────────────────┘
```

## Claude Integration Design

### System Prompt for Embedded Claude
```
You are an AI music producer assistant embedded in claude-synth, a neo-soul
music creation tool. The user is creating LEISURE-style tracks.

Current song state:
{serialized_song_json}

When the user describes changes:
1. Interpret their intent ("dreamier" = more reverb, warmer, slower attack)
2. Respond with specific parameter changes as JSON
3. Explain what you changed and why in a brief, musical way

Response format:
{
  "changes": [
    {"track": "pads", "param": "warmth", "value": 0.85},
    {"track": "pads", "param": "reverb_mix", "value": 0.35}
  ],
  "explanation": "I increased warmth and reverb for a more ethereal feel."
}
```

### Example Mappings
| User Says | Parameter Changes |
|-----------|-------------------|
| "make it dreamier" | reverb↑, warmth↑, attack↑ |
| "more groove" | swing↑, bass syncopation↑ |
| "brighter" | warmth↓ (LPF opens), high shelf↑ |
| "more energy" | tempo↑, compression↑ |
| "chill it out" | tempo↓, swing↓, dynamics↓ |

## Risk Mitigation

1. **Audio thread starvation**: Use lock-free rtrb, never block in audio callback
2. **FunDSP complexity**: Start with simple graphs, add effects incrementally
3. **Claude latency**: Stream responses, show typing indicator
4. **Scope creep**: Strict phase gates, MVP each phase before moving on

## Success Criteria

- [ ] Plays back a 4-bar neo-soul loop with drums/bass/pads
- [ ] Real-time parameter tweaking with immediate audio feedback
- [ ] Elegant TUI that's a joy to use
- [ ] Claude can interpret "make it warmer" and adjust parameters
- [ ] Save/load projects
- [ ] Export to WAV
