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

var RhythmGameManager: Node # Will be assigned in _ready

const TEST_SONG_PATH = "res://resources/test_audio_padded.ogg"
const TEST_TIMING_MAP = [
	{"time": 2.3, "bpm": 100.0, "time_signature": [4, 4]},
	{"time": 7.7, "bpm": 150.0, "time_signature": [3, 4]},
	{"time": 13.05, "bpm": 80.0, "time_signature": [5, 4]},
	{"time": 17.3, "bpm": 120.0, "time_signature": [4, 4]}
]


const _INTERNAL_TEST_NOTE_TIMES: Array = [
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

const PERFECT_WINDOW = 0.04
const GREAT_WINDOW = 0.08
const GOOD_WINDOW = 0.15

#endregion

#region State Variables
var _active_note_visuals: Dictionary = {} # {note_id: note_node}
var _is_seeking_via_slider = false # Flag to prevent slider updates during user drag
var _current_rgm_time: float = 0.0 # Store the time received from the RGM signal
var _visual_note_render_range_secs: float = 10.0 # How many seconds around current time to render visuals
#endregion

#region Lifecycle Methods
func _ready() -> void:
	RhythmGameManager = get_node_or_null("/root/RhythmGameManager")
	if not RhythmGameManager:
		push_error("RhythmGameManager singleton not found! Ensure it's autoloaded.")
		set_process(false)
		status_label.text = "ERROR: RhythmGameManager not found!"
		return

	load_button.pressed.connect(_on_load_button_pressed)
	play_button.pressed.connect(_on_play_button_pressed)
	pause_button.pressed.connect(_on_pause_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	seek_button.pressed.connect(_on_seek_button_pressed)
	seek_slider.value_changed.connect(_on_seek_slider_value_changed)
	seek_slider.drag_started.connect(func(): _is_seeking_via_slider = true)
	seek_slider.drag_ended.connect(func(value_changed): _is_seeking_via_slider = false; if value_changed: _on_seek_slider_value_changed(seek_slider.value))
	seek_0s_button.pressed.connect(_on_seek_a_pressed)
	seek_5s_button.pressed.connect(_on_seek_b_pressed)
	seek_10s_button.pressed.connect(_on_seek_c_pressed)
	seek_15s_button.pressed.connect(_on_seek_d_pressed)
	feedback_clear_timer.timeout.connect(_on_feedback_clear_timer_timeout)

	RhythmGameManager.song_loaded.connect(_on_rgm_song_loaded)
	RhythmGameManager.note_map_set.connect(_on_rgm_note_map_set)
	RhythmGameManager.played.connect(_on_rgm_played)
	RhythmGameManager.paused.connect(_on_rgm_paused)
	RhythmGameManager.seeked.connect(_on_rgm_seeked)
	RhythmGameManager.time_changed.connect(_on_rgm_time_changed)
	RhythmGameManager.timing_segment_changed.connect(_on_rgm_timing_segment_changed)
	RhythmGameManager.note_missed.connect(_on_rgm_note_missed)
	RhythmGameManager.error_occurred.connect(_on_rgm_error_occurred)

	_update_ui_for_state()
	_update_time_label(0.0)
	timing_feedback_label.text = "Load a song!"


func _process(_delta: float) -> void:
	if not RhythmGameManager or RhythmGameManager.song_length <= 0:
		return # Don't process if no song loaded or manager unavailable

	if RhythmGameManager.is_playing() and not _is_seeking_via_slider:
		var render_start_time = _current_rgm_time - (_visual_note_render_range_secs / 2.0)
		var render_end_time = _current_rgm_time + (_visual_note_render_range_secs / 2.0)
		var notes_in_view = RhythmGameManager.get_notes_in_range(render_start_time, render_end_time)
		_update_note_visuals(notes_in_view, _current_rgm_time)

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
	if not RhythmGameManager or not RhythmGameManager.is_playing(): return

	var current_time = RhythmGameManager.get_current_time()

	var hit_attempt_result: Variant = RhythmGameManager.attempt_hit(current_time)

	if hit_attempt_result == null:
		_show_feedback("Miss (Input)")
	else:
		var time_diff: float = hit_attempt_result["time_diff"]
		var note_id = hit_attempt_result["note_id"]
		var abs_diff = abs(time_diff)

		var judgement_text = ""
		if abs_diff <= PERFECT_WINDOW:
			judgement_text = "Perfect!"
		elif abs_diff <= GREAT_WINDOW:
			judgement_text = "Great!"
		elif abs_diff <= GOOD_WINDOW:
			judgement_text = "Good"
		else:
			judgement_text = "OK"

		if judgement_text != "Perfect!" and judgement_text != "OK":
			judgement_text += " (" + ("Early" if time_diff < 0 else "Late") + ")"

		_show_feedback(judgement_text)

		_trigger_hit_visual_effect(note_id, judgement_text)

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
func _spawn_note_visual(note_data: Dictionary) -> void:
	var note_id = note_data["id"]
	if _active_note_visuals.has(note_id):
		return # Don't spawn if a visual for this ID already exists


	var note_node = ColorRect.new()
	note_node.size = NOTE_SIZE
	note_node.color = NOTE_COLOR # Default color
	note_node.position.y = note_track_area.position.y # Align vertically
	note_node.set_meta("note_data", note_data) # Store all data for positioning

	note_container.add_child(note_node)
	_active_note_visuals[note_id] = note_node

func _update_note_visuals(notes_in_view: Array, p_current_time: float) -> void:
	var track_width = note_track_area.size.x
	var hit_zone_x = track_width / 2.0

	var notes_in_view_ids = {} # Keep track of IDs that should be visible
	for note_data in notes_in_view:
		var note_id = note_data["id"]
		notes_in_view_ids[note_id] = true

		var note_node: ColorRect
		if _active_note_visuals.has(note_id):
			note_node = _active_note_visuals[note_id]
		else:
			_spawn_note_visual(note_data)
			note_node = _active_note_visuals[note_id]

		var note_time = note_data["time"]
		var time_diff_for_pos = note_time - p_current_time
		var target_x = hit_zone_x - time_diff_for_pos * NOTE_SCROLL_SPEED_PPS
		note_node.position.x = target_x - NOTE_SIZE.x / 2.0 # Center the note visually

		var status = note_data.get("status")
		if status is Dictionary:
			pass
		elif status == "Pending":
			var visual_time = p_current_time - VISUAL_OFFSET_SECS
			var time_diff_for_hit_zone = note_time - visual_time
			if abs(time_diff_for_hit_zone) < HIT_ZONE_THRESHOLD_SECS:
				note_node.color = NOTE_HIT_COLOR
			else:
				if note_node.color != Color.GRAY and note_node.modulate == Color.WHITE:
					note_node.color = NOTE_COLOR
		elif status == "Missed":
			note_node.color = Color.GRAY

	var ids_to_remove = []
	for note_id in _active_note_visuals:
		if not notes_in_view_ids.has(note_id):
			ids_to_remove.append(note_id)
			var note_node = _active_note_visuals[note_id]
			if is_instance_valid(note_node):
				note_node.queue_free()

	for note_id in ids_to_remove:
		_active_note_visuals.erase(note_id)

func _clear_all_note_visuals() -> void:
	for note_id in _active_note_visuals:
		var note_node = _active_note_visuals[note_id]
		if is_instance_valid(note_node):
			note_node.queue_free()

	_active_note_visuals.clear()

func _setup_visuals_for_time(target_time: float) -> void:
	_clear_all_note_visuals()
	_show_feedback("")

	if not RhythmGameManager or RhythmGameManager.song_length <= 0:
		return

	var render_start_time = target_time - (_visual_note_render_range_secs / 2.0)
	var render_end_time = target_time + (_visual_note_render_range_secs / 2.0)
	var notes_in_view = RhythmGameManager.get_notes_in_range(render_start_time, render_end_time)

	_update_note_visuals(notes_in_view, target_time)

#endregion

#region Visual Effects

func _trigger_hit_visual_effect(note_id, judgement: String) -> void:
	if _active_note_visuals.has(note_id):
		var note_node = _active_note_visuals[note_id]

		var flash_color = Color.WHITE
		if judgement == "Perfect!":
			flash_color = Color.GOLD
		elif judgement.begins_with("Great"):
			flash_color = Color.LIME_GREEN
		elif judgement.begins_with("Good"):
			flash_color = Color.LIGHT_SKY_BLUE

		var tween = create_tween().set_parallel(true)
		tween.tween_property(note_node, "modulate", flash_color, 0.05)
		tween.tween_property(note_node, "modulate", Color.WHITE, 0.1).set_delay(0.05)
		tween.tween_property(note_node, "scale", Vector2(0.8, 0.8), 0.05)
		tween.tween_property(note_node, "scale", Vector2(1.0, 1.0), 0.1).set_delay(0.05)

#endregion

#region UI Signal Handlers
func _on_load_button_pressed() -> void:
	status_label.text = "Status: Loading..."
	_clear_all_note_visuals() # Clear visuals from any previous song
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

func _on_seek_a_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(2.3)

func _on_seek_b_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(7.7)

func _on_seek_c_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(13.05)

func _on_seek_d_pressed() -> void:
	if RhythmGameManager: RhythmGameManager.seek(17.3)

#endregion

#region RhythmGameManager Signal Handlers
func _create_example_note_map() -> Array:
	var note_map = []
	for i in range(_INTERNAL_TEST_NOTE_TIMES.size()):
		var note_time = _INTERNAL_TEST_NOTE_TIMES[i]
		note_map.append({
			"id": "note_%d" % i, # Simple unique ID
			"time": note_time
			# Add other fields like type or lane here if needed
		})
	return note_map

func _on_rgm_song_loaded(_song_path: String, song_length: float) -> void:
	status_label.text = "Status: Song Loaded (%s)" % _song_path.get_file()
	seek_slider.max_value = song_length
	seek_slider.value = 0.0
	_update_time_label(0.0)
	_update_timing_labels()
	_update_ui_for_state()

	var example_note_map = _create_example_note_map()
	if not RhythmGameManager.set_note_map(example_note_map):
		status_label.text = "Status: Song loaded, but failed to set note map!"
		timing_feedback_label.text = "Note map error!"
		return # Stop if note map fails

	if not RhythmGameManager.set_hittable_window(GOOD_WINDOW + 0.02): # Look slightly beyond Good window
		status_label.text = "Status: Song loaded, failed to set judgement windows!"
		timing_feedback_label.text = "Judgement window error!"
		return

	if not RhythmGameManager.set_miss_window(GOOD_WINDOW + 0.02): # Miss slightly after Good window
		status_label.text = "Status: Song loaded, failed to set miss window!"
		timing_feedback_label.text = "Miss window error!"
		return

	_setup_visuals_for_time(0.0) # Show notes from the beginning
	timing_feedback_label.text = "Press SPACE to hit notes!"

func _on_rgm_note_map_set(_map: Array) -> void:
	print("BasicRhythmGame: Note map successfully set/updated in manager.")
	_setup_visuals_for_time(RhythmGameManager.get_current_time() if RhythmGameManager else 0.0)

func _on_rgm_played(start_time: float) -> void:
	status_label.text = "Status: Playing"
	_update_ui_for_state()
	_update_timing_labels()
	if not _is_seeking_via_slider:
		seek_slider.value = start_time
	_update_time_label(start_time)
	if timing_feedback_label.text == "Paused":
		timing_feedback_label.text = ""
	_setup_visuals_for_time(start_time) # Crucial: Update visuals based on new time

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
	_setup_visuals_for_time(seek_time)
	timing_feedback_label.text = ""

func _on_rgm_time_changed(current_time: float) -> void:
	_current_rgm_time = current_time
	_update_time_label(current_time)
	if not _is_seeking_via_slider:
		seek_slider.value = current_time

func _on_rgm_timing_segment_changed(_segment_info: Dictionary) -> void:
	_update_timing_labels()

func _on_rgm_note_missed(note_id, note_time: float) -> void:
	_show_feedback("Miss")

	if _active_note_visuals.has(note_id):
		var note_node = _active_note_visuals[note_id]
		note_node.color = Color.GRAY # Make missed notes gray

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
