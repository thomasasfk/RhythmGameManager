extends Control

#region Node References
@onready var status_label: Label = $MainVBox/StatusLabel
@onready var time_label: Label = $MainVBox/TimingInfoHBox/TimeLabel
@onready var bpm_label: Label = $MainVBox/TimingInfoHBox/BPMLabel
@onready var time_sig_label: Label = $MainVBox/TimingInfoHBox/TimeSigLabel
@onready var load_button: Button = $MainVBox/TopControlsHBox/LoadButton
@onready var play_button: Button = $MainVBox/TopControlsHBox/PlayButton
@onready var pause_button: Button = $MainVBox/TopControlsHBox/PauseButton
@onready var restart_button: Button = $MainVBox/TopControlsHBox/RestartButton
@onready var seek_slider: HSlider = $MainVBox/SeekSlider
@onready var seek_line_edit: LineEdit = $MainVBox/SeekControlsHBox/SeekLineEdit
@onready var seek_button: Button = $MainVBox/SeekControlsHBox/SeekButton
@onready var seek_0s_button: Button = $MainVBox/SegmentSeekHBox/Seek0sButton
@onready var seek_5s_button: Button = $MainVBox/SegmentSeekHBox/Seek5sButton
@onready var seek_10s_button: Button = $MainVBox/SegmentSeekHBox/Seek10sButton
@onready var seek_15s_button: Button = $MainVBox/SegmentSeekHBox/Seek15sButton
@onready var note_track_area: Panel = $MainVBox/NoteTrackArea
@onready var note_container: Node = $MainVBox/NoteTrackArea/NoteContainer
@onready var hit_zone: ColorRect = $MainVBox/NoteTrackArea/HitZone
@onready var timing_feedback_label: Label = $MainVBox/TimingFeedbackLabel
@onready var feedback_clear_timer: Timer = $FeedbackClearTimer
#endregion

#region Constants & Configuration

# --- RhythmGameManager Related ---
var RhythmGameManager: Node # Will be assigned in _ready

const TEST_SONG_PATH = "res://resources/test_audio_padded.ogg"
const TEST_TIMING_MAP = [
	{"time": 2.3, "bpm": 100.0, "time_signature": [4, 4]},
	{"time": 7.7, "bpm": 150.0, "time_signature": [3, 4]},
	{"time": 13.05, "bpm": 80.0, "time_signature": [5, 4]},
	{"time": 17.3, "bpm": 120.0, "time_signature": [4, 4]}
]
# --- End RhythmGameManager Related ---


# --- Example Game Specific ---
# Generate notes based on timing map beats (example data)
const TEST_NOTES: Array = [
	# 100 BPM (0.6s/beat)
	2.5, 3.1, 3.7, 4.3, 4.9, 5.5, 6.1, 6.7, 7.3,
	# 150 BPM (0.4s/beat)
	7.9, 8.3, 8.7, 9.1, 9.5, 9.9, 10.3, 10.7, 11.1, 11.5, 11.9, 12.3,
	# 80 BPM (0.75s/beat)
	13.25, 14.0, 14.75, 15.5, 16.25, 17.0,
	# 120 BPM (0.5s/beat)
	17.5, 18.0, 18.5, 19.0, 19.5, 20.0, 20.5, 21.0, 21.5
]

const NOTE_SCROLL_SPEED_PPS = 200.0 # Pixels per second notes travel
const NOTE_SIZE = Vector2(10, 80)
const NOTE_COLOR = Color.BLUE
const NOTE_HIT_COLOR = Color.YELLOW
const HIT_ZONE_THRESHOLD_SECS = 0.08 # Time window around hit zone for visual color change
const VISUAL_OFFSET_SECS = 0.05

const PERFECT_WINDOW_SECS = 0.04 # e.g., +/- 40ms
const GREAT_WINDOW_SECS = 0.08 # e.g., +/- 80ms
const GOOD_WINDOW_SECS = 0.15 # e.g., +/- 150ms

# --- End Example Game Specific ---

#endregion

#region State Variables
var _active_note_visuals: Dictionary = {} # {note_time: note_node}
var _target_note_index: int = 0 # Index in TEST_NOTES for the next hit target
var _is_seeking_via_slider = false # Flag to prevent slider updates during user drag
var _current_rgm_time: float = 0.0 # Store the time received from the RGM signal
#endregion

#region Lifecycle Methods
func _ready() -> void:
	# --- Get RhythmGameManager ---
	RhythmGameManager = get_node_or_null("/root/RhythmGameManager")
	if not RhythmGameManager:
		push_error("RhythmGameManager singleton not found! Ensure it's autoloaded.")
		set_process(false)
		status_label.text = "ERROR: RhythmGameManager not found!"
		return

	# --- Connect UI Signals ---
	load_button.pressed.connect(_on_load_button_pressed)
	play_button.pressed.connect(_on_play_button_pressed)
	pause_button.pressed.connect(_on_pause_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	seek_button.pressed.connect(_on_seek_button_pressed)
	seek_slider.value_changed.connect(_on_seek_slider_value_changed)
	# Prevent slider updates interfering with drag
	seek_slider.drag_started.connect(func(): _is_seeking_via_slider = true)
	seek_slider.drag_ended.connect(func(value_changed): _is_seeking_via_slider = false; if value_changed: _on_seek_slider_value_changed(seek_slider.value))
	seek_0s_button.pressed.connect(_on_seek_0s_pressed)
	seek_5s_button.pressed.connect(_on_seek_5s_pressed)
	seek_10s_button.pressed.connect(_on_seek_10s_pressed)
	seek_15s_button.pressed.connect(_on_seek_15s_pressed)
	feedback_clear_timer.timeout.connect(_on_feedback_clear_timer_timeout)

	# --- Connect RhythmGameManager Signals ---
	RhythmGameManager.song_loaded.connect(_on_rgm_song_loaded)
	RhythmGameManager.played.connect(_on_rgm_played)
	RhythmGameManager.paused.connect(_on_rgm_paused)
	RhythmGameManager.restarted.connect(_on_rgm_restarted)
	RhythmGameManager.seeked.connect(_on_rgm_seeked)
	RhythmGameManager.time_changed.connect(_on_rgm_time_changed)
	RhythmGameManager.timing_segment_changed.connect(_on_rgm_timing_segment_changed)
	RhythmGameManager.error_occurred.connect(_on_rgm_error_occurred)

	# --- Initial UI State ---
	_update_ui_for_state()
	_update_time_label(0.0)
	timing_feedback_label.text = "Load a song!"


func _process(_delta: float) -> void:
	# --- Guard Clauses ---
	if not RhythmGameManager or RhythmGameManager.song_length <= 0:
		return # Don't process if no song loaded or manager unavailable

	var visual_time = _current_rgm_time - VISUAL_OFFSET_SECS

	var lookahead_time = 5.0
	for note_time in TEST_NOTES:
		if note_time > _current_rgm_time and note_time <= _current_rgm_time + lookahead_time and not _active_note_visuals.has(note_time):
			_spawn_note_visual(note_time)

	_update_active_notes(_current_rgm_time, visual_time)

	_check_for_missed_notes(_current_rgm_time)


func _unhandled_input(event: InputEvent) -> void:
	if not RhythmGameManager or RhythmGameManager.song_length <= 0:
		return
	
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_SPACE:
			_process_hit()
			get_viewport().set_input_as_handled()

#endregion

#region Gameplay Logic
func _process_hit() -> void:
	if not RhythmGameManager.is_playing(): return

	var current_time = RhythmGameManager.get_current_time()

	if _target_note_index >= TEST_NOTES.size():
		_show_feedback("-")
		return

	var target_note_time = TEST_NOTES[_target_note_index]
	var diff = current_time - target_note_time
	var abs_diff = abs(diff)

	var feedback_text = ""
	if abs_diff <= GOOD_WINDOW_SECS:
		if abs_diff <= PERFECT_WINDOW_SECS:
			feedback_text = "Perfect!"
		elif abs_diff <= GREAT_WINDOW_SECS:
			feedback_text = "Great!" + (" (Early)" if diff < 0 else " (Late)")
		else: # Must be within GOOD_WINDOW_SECS
			feedback_text = "Good" + (" (Early)" if diff < 0 else " (Late)")

		_show_feedback(feedback_text)
		_target_note_index += 1 # Move to the next note only on a successful hit
		# TODO: Add visual feedback for hit note (e.g., change color, particle effect)
	else:
		# Hit was outside the window for the current target note.
		# This is generally considered a 'miss' or hitting nothing.
		_show_feedback("Miss")
		# We don't advance the target index here; the miss check in _process handles notes that passed.

func _check_for_missed_notes(p_current_time: float) -> void:
	if _target_note_index < TEST_NOTES.size():
		var target_note_time = TEST_NOTES[_target_note_index]
		if p_current_time > target_note_time + GOOD_WINDOW_SECS:
			_show_feedback("Miss")
			_target_note_index += 1

func _show_feedback(text: String) -> void:
	timing_feedback_label.text = text

	if text == "Perfect!":
		timing_feedback_label.modulate = Color.GOLD
	elif text.begins_with("Great!"):
		timing_feedback_label.modulate = Color.GREEN
	elif text.begins_with("Good"):
		timing_feedback_label.modulate = Color.LIGHT_BLUE
	elif text == "Miss":
		timing_feedback_label.modulate = Color.RED
	else:
		timing_feedback_label.modulate = Color.WHITE

	feedback_clear_timer.start()

func _on_feedback_clear_timer_timeout() -> void:
	timing_feedback_label.text = ""
	timing_feedback_label.modulate = Color.WHITE

#endregion

#region Visual Note Handling
func _spawn_note_visual(note_time: float) -> void:
	if _active_note_visuals.has(note_time):
		return

	var note_node = ColorRect.new()
	note_node.size = NOTE_SIZE
	note_node.color = NOTE_COLOR
	note_node.position.y = note_track_area.position.y

	note_container.add_child(note_node)
	_active_note_visuals[note_time] = note_node

func _update_active_notes(p_current_time: float, p_visual_time: float) -> void:
	var notes_to_remove = []
	var track_width = note_track_area.size.x
	var hit_zone_x = track_width / 2.0

	for note_time in _active_note_visuals:
		var note_node: ColorRect = _active_note_visuals[note_time]

		var time_diff_for_pos = note_time - p_current_time
		var target_x = hit_zone_x - time_diff_for_pos * NOTE_SCROLL_SPEED_PPS
		note_node.position.x = target_x - NOTE_SIZE.x / 2.0 # Center the note visually

		var time_diff_for_hit = note_time - p_visual_time
		if abs(time_diff_for_hit) < HIT_ZONE_THRESHOLD_SECS:
			if note_node.color != Color.GRAY:
				note_node.color = NOTE_HIT_COLOR
		else:
			if note_node.color != Color.GRAY:
				note_node.color = NOTE_COLOR

		if target_x < -NOTE_SIZE.x * 2:
			notes_to_remove.append(note_time)
			note_node.queue_free()

	for note_time in notes_to_remove:
		_active_note_visuals.erase(note_time)

func _clear_all_note_visuals() -> void:
	for note_time in _active_note_visuals:
		var note_node = _active_note_visuals[note_time]
		if is_instance_valid(note_node):
			note_node.queue_free()
	_active_note_visuals.clear()

func _setup_notes_for_time(target_time: float) -> void:
	_clear_all_note_visuals()
	_show_feedback("")

	for note_time in TEST_NOTES:
		_spawn_note_visual(note_time)

	var visual_target_time = target_time - VISUAL_OFFSET_SECS
	_update_active_notes(target_time, visual_target_time)

	_target_note_index = TEST_NOTES.size() # Default to end
	for i in range(TEST_NOTES.size()):
		var note_time = TEST_NOTES[i]
		if note_time >= target_time - GOOD_WINDOW_SECS:
			_target_note_index = i
			break

#endregion

#region UI Signal Handlers
func _on_load_button_pressed() -> void:
	status_label.text = "Status: Loading..."
	_clear_all_note_visuals() # Clear notes from any previous song
	timing_feedback_label.text = "Loading..."
	if RhythmGameManager.load_song(TEST_SONG_PATH):
		if not RhythmGameManager.set_timing_map(TEST_TIMING_MAP):
			status_label.text = "Status: Song loaded, but failed to set timing map!"
			timing_feedback_label.text = "Timing map error!"

func _on_play_button_pressed() -> void:
	RhythmGameManager.play()
	timing_feedback_label.text = ""

func _on_pause_button_pressed() -> void:
	RhythmGameManager.pause()
	timing_feedback_label.text = "Paused"

func _on_restart_button_pressed() -> void:
	RhythmGameManager.restart()

func _on_seek_button_pressed() -> void:
	var time_text = seek_line_edit.text
	if time_text.is_valid_float():
		var seek_time = time_text.to_float()
		RhythmGameManager.seek(seek_time)
	else:
		status_label.text = "Status: Invalid seek time entered."
		timing_feedback_label.text = "Invalid seek time"

func _on_seek_slider_value_changed(value: float) -> void:
	if RhythmGameManager and RhythmGameManager.song_length > 0:
		if _is_seeking_via_slider or not RhythmGameManager.is_playing():
			RhythmGameManager.seek(value)

func _on_seek_0s_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(2.5)

func _on_seek_5s_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(7.5)

func _on_seek_10s_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(12.5)

func _on_seek_15s_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(17.5)

#endregion

#region RhythmGameManager Signal Handlers
func _on_rgm_song_loaded(_song_path: String, song_length: float) -> void:
	status_label.text = "Status: Song Loaded (%s)" % _song_path.get_file()
	seek_slider.max_value = song_length
	seek_slider.value = 0.0
	_update_time_label(0.0)
	_update_timing_labels()
	_update_ui_for_state()
	_setup_notes_for_time(2.5)
	timing_feedback_label.text = "Press SPACE to hit notes!"

func _on_rgm_played(start_time: float) -> void:
	status_label.text = "Status: Playing"
	_update_ui_for_state()
	_update_timing_labels()
	if not _is_seeking_via_slider:
		seek_slider.value = start_time
	_update_time_label(start_time)
	if timing_feedback_label.text == "Paused":
		timing_feedback_label.text = ""

func _on_rgm_paused(_pause_time: float) -> void:
	status_label.text = "Status: Paused"
	_update_ui_for_state()
	timing_feedback_label.text = "Paused"

func _on_rgm_restarted() -> void:
	status_label.text = "Status: Restarted"

func _on_rgm_seeked(seek_time: float) -> void:
	status_label.text = "Status: Seeked to %.2fs" % seek_time
	_current_rgm_time = seek_time
	if not _is_seeking_via_slider:
		seek_slider.value = seek_time
	_update_ui_for_state()
	_update_time_label(seek_time)
	_update_timing_labels()
	_setup_notes_for_time(seek_time)
	timing_feedback_label.text = ""

func _on_rgm_time_changed(current_time: float) -> void:
	_current_rgm_time = current_time
	_update_time_label(current_time)
	if not _is_seeking_via_slider:
		seek_slider.value = current_time

func _on_rgm_timing_segment_changed(_segment_info: Dictionary) -> void:
	_update_timing_labels()

func _on_rgm_error_occurred(error_message: String) -> void:
	status_label.text = "Status: ERROR - %s" % error_message
	timing_feedback_label.text = "ERROR!"
	_update_ui_for_state()

#endregion

#region UI Update Helpers
func _update_ui_for_state() -> void:
	var has_song = RhythmGameManager and RhythmGameManager.song_length > 0.0
	var is_playing = RhythmGameManager and RhythmGameManager.is_playing()

	play_button.disabled = not has_song or is_playing
	pause_button.disabled = not has_song or not is_playing
	restart_button.disabled = not has_song
	seek_button.disabled = not has_song
	seek_slider.editable = has_song
	seek_line_edit.editable = has_song
	seek_0s_button.disabled = not has_song
	seek_5s_button.disabled = not has_song
	seek_10s_button.disabled = not has_song
	seek_15s_button.disabled = not has_song

	if has_song and not is_playing and status_label.text.begins_with("Status: Playing"):
		status_label.text = "Status: Ready (Stopped)"
		if timing_feedback_label.text.is_empty():
			timing_feedback_label.text = "Stopped"
	elif not has_song:
		status_label.text = "Status: Load a song"
		timing_feedback_label.text = "Load a song!"


func _update_time_label(current_time: float) -> void:
	var total_length = RhythmGameManager.song_length if RhythmGameManager else 0.0
	time_label.text = "Time: %.2f / %.2f" % [current_time, total_length]


func _update_timing_labels() -> void:
	if not RhythmGameManager: return
	var bpm = RhythmGameManager.get_current_bpm()
	var time_sig = RhythmGameManager.get_current_time_signature()

	bpm_label.text = "BPM: %.1f" % bpm if bpm > 0 else "BPM: -"
	time_sig_label.text = "Time Sig: %d/%d" % [time_sig[0], time_sig[1]] if time_sig and time_sig.size() == 2 else "Time Sig: -/-"

#endregion
