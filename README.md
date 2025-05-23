# Godot Rhythm Game Manager
[![Run GUT Tests](https://github.com/thomasasfk/RhythmGameManager/actions/workflows/test.yml/badge.svg)](https://github.com/thomasasfk/RhythmGameManager/actions/workflows/test.yml)

A simple autoload singleton (`RhythmGameManager.gd`) for Godot 4.x that manages audio playback, song timing (BPM/time signatures), note handling, and playback state.

## Core Concept

The manager tightly couples audio playback with timing information (BPM, time signatures) and note management. It exposes a consistent state via signals (`played`, `paused`, `seeked`, `time_changed`, `timing_segment_changed`, `note_missed`, etc.) and properties (`current_time`, `song_length`, `get_current_bpm()`, `get_notes_in_range()`).

This design allows your rhythm game logic and visuals to simply react to the manager's state. For example, if your note rendering is based on `current_time`, calling `seek()` on the manager will automatically reposition everything correctly without extra effort, as your rendering logic just follows the manager's lead.

## Features

*   Handles audio loading and playback (play, pause, seek, restart).
*   Tracks precise song time and total length.
*   Manages dynamic timing changes via a `timing_map`.
*   Supports note maps with hit detection and miss tracking.
*   Provides configurable hit windows and automatic miss detection.
*   Offers methods to query notes in specific time ranges.
*   Maintains note hit status tracking.
*   Provides reliable signals for playback, timing events, and note events.
*   Includes unit tests using the GUT framework.

## Setup (GUT Addon Required)

This project requires the GUT (Godot Unit Test) addon for testing. Because this project is built for a specific Godot version (4.4+), we need a particular commit from GUT's development branch that includes compatibility fixes not yet available in a main release.

Run the following single command **from the root directory of this project** to download and place the correct GUT version into the `addons/` folder automatically:

```bash
mkdir -p addons && (git clone -q --branch godot_4_4 https://github.com/bitwes/Gut.git g && cd g && git checkout -q e2f8c4b6220144c6665976e58d8c15ad715de244 && mv addons/gut ../addons/ && cd .. && rm -rf g)
```

## Testing

Once the GUT addon is set up (see command above), run the unit tests using the following command from the project root:

```bash
godot -s addons/gut/gut_cmdln.gd -d --path "$PWD" -gtest=res://test/test_RhythmGameManager.gd -glog=1 -gexit
```

*(Ensure `godot 4.4.*` is in your system's PATH or use the full path to the executable).* 

## Example Rhythm Game

This project includes a functional rhythm game example that demonstrates the RhythmGameManager in action. The example provides a complete implementation with UI controls for playing, pausing, seeking, and visualizing notes.

![Rhythm Game Example](example.png)

The example demonstrates:
- Audio playback controls (play, pause, restart)
- Seeking to specific timestamps
- BPM and time signature tracking
- Note visualization based on timing
- Timing feedback for note hits
- Miss detection and note hit judgement

You can find the example in the `scenes/BasicRhythmGame.tscn` file, with the implementation in `scripts/scenes/BasicRhythmGame.gd`.
