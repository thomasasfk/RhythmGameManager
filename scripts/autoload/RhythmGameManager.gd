extends Node

#region Signals
# Emitted when a new song is successfully loaded.
signal song_loaded(song_path: String, song_length: float)
# Emitted when playback starts or resumes.
signal played(start_time: float)
# Emitted when playback is paused.
signal paused(pause_time: float)
# Emitted when the playback position is changed via seek.
signal seeked(seek_time: float)
# Emitted frequently during playback, indicating the current time.
signal time_changed(current_time: float)
# Emitted when the active timing segment (BPM/Time Signature) changes during playback.
signal timing_segment_changed(segment_info: Dictionary) # Emits the new active segment dictionary
# Emitted when a new timing map is successfully set.
signal timing_map_set(map: Array)
# Emitted when a new note map is successfully set.
signal note_map_set(map: Array)
# Emitted when a note is missed (passed the judgement window).
signal note_missed(note_id, note_time: float)
# Emitted when an error occurs (e.g., loading failed, invalid seek, invalid timing map).
signal error_occurred(error_message: String)
#endregion


#region Properties
# Internal node to handle audio playback.
var _audio_stream_player: AudioStreamPlayer

# Private variable to store the time.
var __time: float = 0.0

# The current playback time in seconds. Publicly accessible.
var current_time: float:
	get: return __time

# The total length of the loaded song in seconds. Publicly accessible.
var song_length: float = 0.0

# Stores timing change events (BPM, time signature) throughout the song.
# Expected format: Array[Dictionary]
# Each Dictionary: {"time": float, "bpm": float, "time_signature": Array[int] (e.g., [4, 4])}
# Must be sorted by "time". Set using set_timing_map().
var _timing_map: Array = []

# Stores note events (taps, holds, etc.) throughout the song.
# Expected format: Array[Dictionary]
# Each Dictionary: {"id": Variant (unique), "time": float, ...other optional data}
# Must be sorted by "time". Set using set_note_map().
var _note_map: Array = []

# Stores the index of the currently active timing segment in _timing_map
var _current_timing_segment_index: int = -1

# Window (in seconds, absolute difference) around current time to look for hittable notes.
var hittable_window: float = 0.15 # Default, can be set by game

# Window (in seconds, after note time) to consider a note missed if not hit.
# Set <= 0 to disable automatic miss detection.
var miss_window: float = 0.15 # Default, can be set by game

# Tracks the state of each note (key: note_id, value: result Dictionary or "Missed")
var _hit_note_ids: Dictionary = {}
#endregion


#region Lifecycle methods
func _ready() -> void:
	_audio_stream_player = AudioStreamPlayer.new()
	add_child(_audio_stream_player)
	print("RhythmGameManager: Initialized.")

func _process(_delta: float) -> void:
	if _audio_stream_player and _audio_stream_player.is_playing():
		var new_time = _audio_stream_player.get_playback_position()
		if abs(new_time - __time) > 0.001:
			__time = min(new_time, song_length)
			time_changed.emit(__time)
			_check_and_update_timing_segment(__time)
			_check_for_missed_notes(__time) 
#endregion


#region Internal helper methods
func _check_and_update_timing_segment(p_time: float) -> void:
	var active_segment_index = _find_timing_segment_index_for_time(p_time)

	if active_segment_index != _current_timing_segment_index:
		_current_timing_segment_index = active_segment_index
		if _current_timing_segment_index != -1:
			var segment_info = _timing_map[_current_timing_segment_index]
			print("RhythmGameManager: Timing segment changed at %f s: %s" % [p_time, str(segment_info)])
			timing_segment_changed.emit(segment_info)
		else:
			print("RhythmGameManager: No active timing segment found for time %f s" % p_time)
			timing_segment_changed.emit({})

func _find_timing_segment_index_for_time(p_time: float) -> int:
	if _timing_map.is_empty():
		return -1
	for i in range(_timing_map.size() - 1, -1, -1):
		var segment = _timing_map[i]
		if segment.get("time", -1.0) <= p_time:
			return i
	return -1

func _validate_timing_map(p_map) -> String:
	if not p_map is Array:
		return "Invalid timing map: Input must be an Array."
	var last_time = -1.0
	for i in range(p_map.size()):
		var segment = p_map[i]
		if not segment is Dictionary:
			return "Invalid timing map: Element at index %d is not a Dictionary." % i
		if not segment.has("time") or not segment["time"] is float:
			return "Invalid timing map: Element %d missing or invalid 'time' (float)." % i
		if not segment.has("bpm") or not segment["bpm"] is float or segment["bpm"] <= 0:
			return "Invalid timing map: Element %d missing or invalid 'bpm' (positive float)." % i
		if segment.has("time_signature"):
			if not segment["time_signature"] is Array or segment["time_signature"].size() != 2:
				return "Invalid timing map: Element %d has invalid 'time_signature' (must be Array[int] of size 2)." % i
			if not segment["time_signature"][0] is int or not segment["time_signature"][1] is int:
				return "Invalid timing map: Element %d 'time_signature' elements must be integers." % i
			if segment["time_signature"][0] <= 0 or segment["time_signature"][1] <= 0:
				return "Invalid timing map: Element %d 'time_signature' values must be positive." % i
		else:
			return "Invalid timing map: Element %d missing 'time_signature'." % i
		var current_time_in_map = segment["time"]
		if current_time_in_map < 0.0:
			return "Invalid timing map: Element %d has negative 'time' (%f)." % [i, current_time_in_map]
		if current_time_in_map < last_time:
			return "Invalid timing map: Elements are not sorted by 'time'. Element %d (%f) < previous (%f)." % [i, current_time_in_map, last_time]
		last_time = current_time_in_map
	return ""

func _validate_note_map(p_map) -> String:
	if not p_map is Array:
		return "Invalid note map: Input must be an Array."
	var ids_seen = {}
	for i in range(p_map.size()):
		var note = p_map[i]
		if not note is Dictionary:
			return "Invalid note map: Element at index %d is not a Dictionary." % i
		if not note.has("time") or not note["time"] is float:
			return "Invalid note map: Element %d missing or invalid 'time' (float)." % i
		if not note.has("id"):
			return "Invalid note map: Element %d missing 'id'." % i
		var current_id = note["id"]
		if ids_seen.has(current_id):
			return "Invalid note map: Duplicate note 'id' found: %s" % str(current_id)
		ids_seen[current_id] = true

		var current_time_in_map = note["time"]
		if current_time_in_map < 0.0:
			return "Invalid note map: Element %d has negative 'time' (%f)." % [i, current_time_in_map]
	return ""

func _check_for_missed_notes(p_current_time: float) -> void:
	if _note_map.is_empty():
		return

	if miss_window <= 0:
		return

	for note in _note_map:
		var note_id = note["id"]
		var note_time = note["time"]
		if not _hit_note_ids.has(note_id):
			if p_current_time > note_time + miss_window:
				_hit_note_ids[note_id] = "Missed"
				note_missed.emit(note_id, note_time)

func _reset_hit_status_after(p_time: float) -> void:
	var ids_to_remove = []
	for note_id in _hit_note_ids:
		var note_time = -1.0
		for note in _note_map:
			if note["id"] == note_id:
				note_time = note["time"]
				break
		if note_time >= p_time:
			ids_to_remove.append(note_id)

	if not ids_to_remove.is_empty():
		pass

	for note_id in ids_to_remove:
		_hit_note_ids.erase(note_id)

#endregion


#region Public API methods
func load_song(p_song_path: String) -> bool:
	print("RhythmGameManager: Attempting to load song: %s" % p_song_path)
	var stream = load(p_song_path) as AudioStream
	if not stream:
		var error_msg = "Failed to load audio stream from path: %s. Ensure the file exists and is a valid audio format." % p_song_path
		print("RhythmGameManager: ERROR - %s" % error_msg)
		error_occurred.emit(error_msg)
		return false

	if _audio_stream_player.is_playing():
		_audio_stream_player.stop()

	_audio_stream_player.stream = stream
	song_length = stream.get_length()
	__time = 0.0
	_timing_map = []
	_note_map = [] # Reset note map
	_hit_note_ids = {} # Reset hit status
	_current_timing_segment_index = -1

	print("RhythmGameManager: Song loaded successfully. Length: %f seconds. Timing map reset." % song_length)
	song_loaded.emit(p_song_path, song_length)
	time_changed.emit(__time)
	timing_segment_changed.emit({})
	return true

func set_timing_map(p_map) -> bool:
	print("RhythmGameManager: Attempting to set timing map.")
	var validation_error = _validate_timing_map(p_map)
	if validation_error != "":
		print("RhythmGameManager: ERROR - %s" % validation_error)
		error_occurred.emit(validation_error)
		return false

	_timing_map = p_map.duplicate(true)
	print("RhythmGameManager: Timing map set successfully with %d entries." % _timing_map.size())

	_check_and_update_timing_segment(__time)
	timing_map_set.emit(_timing_map)
	return true

func set_note_map(p_map) -> bool:
	print("RhythmGameManager: Attempting to set note map.")
	var validation_error = _validate_note_map(p_map)
	if validation_error != "":
		print("RhythmGameManager: ERROR - %s" % validation_error)
		error_occurred.emit(validation_error)
		_note_map = [] # Ensure map is empty on error
		_hit_note_ids = {}
		return false

	_note_map = p_map.duplicate(true)
	_hit_note_ids = {} # Reset hit status when map changes
	print("RhythmGameManager: Note map set successfully with %d notes." % _note_map.size())

	note_map_set.emit(_note_map)
	return true

func set_hittable_window(p_window: float) -> bool:
	if p_window <= 0:
		var error_msg = "Invalid hittable window: Must be positive."
		print("RhythmGameManager: ERROR - %s" % error_msg)
		error_occurred.emit(error_msg)
		return false

	hittable_window = p_window
	print("RhythmGameManager: Hittable window set: %.3fs" % hittable_window)
	return true

func set_miss_window(p_window: float) -> bool:
	miss_window = p_window
	if miss_window > 0:
		print("RhythmGameManager: Miss window set: %.3fs" % miss_window)
	else:
		print("RhythmGameManager: Automatic miss detection disabled.")
	return true

func play() -> void:
	if not _audio_stream_player.stream:
		var error_msg = "Cannot play, no song loaded."
		print("RhythmGameManager: ERROR - %s" % error_msg)
		error_occurred.emit(error_msg)
		return
	if not _audio_stream_player.is_playing():
		print("RhythmGameManager: Playing from time: %f" % __time)
		_check_and_update_timing_segment(__time)
		_check_for_missed_notes(__time)
		_audio_stream_player.play(__time)
		played.emit(__time)
	else:
		print("RhythmGameManager: Already playing.")

func pause() -> void:
	if not _audio_stream_player.stream or not _audio_stream_player.is_playing():
		print("RhythmGameManager: Cannot pause, no song loaded or not playing.")
		return
	if _audio_stream_player.is_playing():
		__time = _audio_stream_player.get_playback_position()
	_audio_stream_player.stop()
	print("RhythmGameManager: Paused at time: %f" % __time)
	paused.emit(__time)
	time_changed.emit(__time)

func seek(p_time: float) -> void:
	if not _audio_stream_player.stream:
		var error_msg = "Cannot seek, no song loaded."
		print("RhythmGameManager: ERROR - %s" % error_msg)
		error_occurred.emit(error_msg)
		return

	var target_time = clampf(p_time, 0.0, song_length)
	if not is_equal_approx(p_time, target_time):
		print("RhythmGameManager: Seek time %f clamped to %f" % [p_time, target_time])
		error_occurred.emit("Seek time %f out of bounds [0, %f], clamped to %f." % [p_time, song_length, target_time])

	var was_playing = _audio_stream_player.is_playing()
	__time = target_time
	_reset_hit_status_after(__time) # Clear status of notes after the seek target
	_check_and_update_timing_segment(__time)
	_check_for_missed_notes(__time) # Check misses *at* the new seek time
	print("RhythmGameManager: Seeked to time: %f" % __time)
	seeked.emit(__time)
	time_changed.emit(__time) # Emit time change immediately after seek
	if was_playing:
		_audio_stream_player.play(__time)

func restart() -> void:
	print("RhythmGameManager: Restarting song.")
	seek(0.0)

func attempt_hit(p_current_time: float) -> Variant:
	if _note_map.is_empty():
		return null

	var best_note_id = null
	var min_abs_diff = INF
	var actual_diff = 0.0
	var best_note_data: Dictionary = {}

	if hittable_window <= 0:
		print("RhythmGameManager: Warning - attempt_hit called with hittable_window <= 0.")
		return null

	for note in _note_map:
		var note_id = note["id"]
		if not _hit_note_ids.has(note_id):
			var note_time = note["time"]
			var diff = p_current_time - note_time
			var abs_diff = abs(diff)

			if abs_diff <= hittable_window:
				if abs_diff < min_abs_diff:
					min_abs_diff = abs_diff
					actual_diff = diff
					best_note_id = note_id
					best_note_data = note

	if best_note_id != null:
		var hit_info = {
			"status": "Hit",
			"hit_time": p_current_time,
			"time_diff": actual_diff
		}
		_hit_note_ids[best_note_id] = hit_info

		var result = {
			"note_id": best_note_id,
			"note_time": best_note_data["time"],
			"time_diff": actual_diff,
			"note_data": best_note_data.duplicate(true) # Return a copy of note data
		}

		return result
	else:
		return null

#endregion


#region Public getters
func get_current_time() -> float:
	if _audio_stream_player and _audio_stream_player.is_playing():
		__time = min(_audio_stream_player.get_playback_position(), song_length)
	return __time

func is_playing() -> bool:
	return _audio_stream_player and _audio_stream_player.is_playing()

func get_timing_map() -> Array:
	return _timing_map.duplicate(true)

func get_note_map() -> Array:
	return _note_map.duplicate(true) # Return a copy

func get_notes_in_range(start_time: float, end_time: float) -> Array:
	var notes_in_view: Array = []
	if _note_map.is_empty():
		return notes_in_view

	for note in _note_map:
		var note_time = note["time"]
		if note_time >= start_time and note_time <= end_time:
			var note_copy = note.duplicate(true)
			if _hit_note_ids.has(note["id"]):
				note_copy["status"] = _hit_note_ids[note["id"]]
			else:
				note_copy["status"] = "Pending"
			notes_in_view.append(note_copy)
	return notes_in_view

func get_timing_info_at_time(p_time: float) -> Dictionary:
	var index = _find_timing_segment_index_for_time(p_time)
	if index != -1:
		return _timing_map[index].duplicate(true)
	return {}

func get_bpm_at_time(p_time: float) -> float:
	var info = get_timing_info_at_time(p_time)
	return info.get("bpm", 0.0)

func get_time_signature_at_time(p_time: float) -> Array:
	var info = get_timing_info_at_time(p_time)
	return info.get("time_signature", [4, 4]).duplicate()

func get_current_bpm() -> float:
	if _current_timing_segment_index != -1 and _current_timing_segment_index < _timing_map.size():
		var cached_segment = _timing_map[_current_timing_segment_index]
		var next_segment_index = _current_timing_segment_index + 1
		if next_segment_index < _timing_map.size() and __time >= _timing_map[next_segment_index].get("time", INF):
			pass
		else:
			return cached_segment.get("bpm", 0.0)
	return get_bpm_at_time(__time)

func get_current_time_signature() -> Array:
	if _current_timing_segment_index != -1 and _current_timing_segment_index < _timing_map.size():
		var cached_segment = _timing_map[_current_timing_segment_index]
		var next_segment_index = _current_timing_segment_index + 1
		if next_segment_index < _timing_map.size() and __time >= _timing_map[next_segment_index].get("time", INF):
			pass # Fall through to lookup
		else:
			return cached_segment.get("time_signature", [4, 4]).duplicate()
	return get_time_signature_at_time(__time)
#endregion
