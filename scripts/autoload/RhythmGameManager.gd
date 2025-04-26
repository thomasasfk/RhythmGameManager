extends Node

# Signals
# Emitted when a new song is successfully loaded.
signal song_loaded(song_path: String, song_length: float)
# Emitted when playback starts or resumes.
signal played(start_time: float)
# Emitted when playback is paused.
signal paused(pause_time: float)
# Emitted when the song is restarted (seeked to 0).
signal restarted() # Kept for semantic clarity, even if it follows a seek(0)
# Emitted when the playback position is changed via seek.
signal seeked(seek_time: float)
# Emitted frequently during playback, indicating the current time.
signal time_changed(current_time: float)
# Emitted when the active timing segment (BPM/Time Signature) changes during playback.
signal timing_segment_changed(segment_info: Dictionary) # Emits the new active segment dictionary
# Emitted when a new timing map is successfully set.
signal timing_map_set(map: Array)
# Emitted when an error occurs (e.g., loading failed, invalid seek, invalid timing map).
signal error_occurred(error_message: String)
# End of signals



# Properties
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

# Stores the index of the currently active timing segment in _timing_map
var _current_timing_segment_index: int = -1
# End of properties


# Lifecycle methods
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
# End of lifecycle methods


# Internal helper methods
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
# End of internal helper methods


# Public API methods
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

func play() -> void:
	if not _audio_stream_player.stream:
		var error_msg = "Cannot play, no song loaded."
		print("RhythmGameManager: ERROR - %s" % error_msg)
		error_occurred.emit(error_msg)
		return
	if not _audio_stream_player.is_playing():
		print("RhythmGameManager: Playing from time: %f" % __time)
		_check_and_update_timing_segment(__time)
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
	_check_and_update_timing_segment(__time)
	print("RhythmGameManager: Seeked to time: %f" % __time)
	seeked.emit(__time)
	time_changed.emit(__time)
	if was_playing:
		_audio_stream_player.play(__time)

func restart() -> void:
	print("RhythmGameManager: Restarting song.")
	seek(0.0)
	restarted.emit()
# End of public API methods


# Public getters
func get_current_time() -> float:
	if _audio_stream_player and _audio_stream_player.is_playing():
		__time = min(_audio_stream_player.get_playback_position(), song_length)
	return __time

func is_playing() -> bool:
	return _audio_stream_player and _audio_stream_player.is_playing()

func get_timing_map() -> Array:
	return _timing_map.duplicate(true)

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
# End of public getters