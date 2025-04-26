extends GutTest

class TestInitialAndLoad:
	extends GutTest

	var manager: Node
	const TEST_SONG_PATH = "res://resources/test_audio.ogg"
	const INVALID_SONG_PATH = "res://non_existent_song.mp3"

	func before_each():
		manager = get_node_or_null("/root/RhythmGameManager")
		assert_ne(manager, null, "RhythmGameManager singleton should be loaded.")
		if manager._audio_stream_player.stream:
			manager.pause()
			manager._audio_stream_player.stream = null
			manager.song_length = 0.0
			manager.__time = 0.0
			manager._timing_map = []
			manager._current_timing_segment_index = -1
		watch_signals(manager)

	func test_initial_state():
		assert_eq(manager.get_current_time(), 0.0, "Initial time should be 0.")
		assert_eq(manager.song_length, 0.0, "Initial song length should be 0.")
		assert_false(manager.is_playing(), "Should not be playing initially.")
		assert_eq(manager.get_timing_map(), [], "Initial timing map should be empty.")
		assert_eq(manager.get_current_bpm(), 0.0, "Initial BPM should be 0.")
		assert_eq(manager.get_current_time_signature(), [4, 4], "Initial time signature should be default [4, 4].")

	func test_load_song_success() -> void:
		var loaded = manager.load_song(TEST_SONG_PATH)
		assert_true(loaded, "load_song should return true for a valid path.")
		await get_tree().process_frame
		assert_gt(manager.song_length, 0.0, "Song length should be > 0 after loading.")
		assert_almost_eq(manager.get_current_time(), 0.0, 0.001, "Current time should be reset to 0 after loading.")
		assert_signal_not_emitted(manager, "error_occurred", "error_occurred should not be emitted on successful load.")

	func test_load_song_failure_invalid_path() -> void:
		var loaded = manager.load_song(INVALID_SONG_PATH)
		assert_false(loaded, "load_song should return false for an invalid path.")
		await get_tree().process_frame
		assert_eq(manager.song_length, 0.0, "Song length should remain 0 after failed load.")
		assert_signal_not_emitted(manager, "song_loaded", "song_loaded should not be emitted on failure.")


class TestPlaybackControls:
	extends GutTest

	var manager: Node
	const TEST_SONG_PATH = "res://resources/test_audio.ogg"

	func before_each():
		manager = get_node_or_null("/root/RhythmGameManager")
		assert_ne(manager, null, "RhythmGameManager singleton should be loaded.")
		if manager._audio_stream_player.stream:
			manager.pause()
			manager._audio_stream_player.stream = null
			manager.song_length = 0.0
			manager.__time = 0.0
			manager._timing_map = []
			manager._current_timing_segment_index = -1
		watch_signals(manager)

	func test_play_without_loading() -> void:
		manager.play()
		await get_tree().process_frame
		assert_false(manager.is_playing(), "Should not be playing if no song is loaded.")
		assert_signal_not_emitted(manager, "played", "played signal should not emit if no song is loaded.")

	func test_pause_without_loading() -> void:
		manager.pause()
		await get_tree().process_frame
		assert_signal_not_emitted(manager, "paused", "paused signal should not emit if nothing is playing/loaded.")
		assert_signal_not_emitted(manager, "error_occurred", "error_occurred should not emit when pausing with nothing loaded.")

	func test_play_starts_playback_and_emits_signal() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		await get_tree().process_frame
		manager.play()
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_time(), 0.0, 0.02, "Current time should be ~0 when play starts.")
		assert_true(manager.is_playing(), "Manager should be playing after play().")
		await get_tree().create_timer(0.1).timeout
		assert_gt(manager.get_current_time(), 0.0, "Current time should advance after playing.")
		assert_signal_not_emitted(manager, "error_occurred", "No error should occur on valid play.")

	func test_pause_stops_playback_and_emits_signal() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		manager.play()
		await get_tree().process_frame
		await get_tree().create_timer(0.1).timeout
		var time_before_pause = manager.get_current_time()
		assert_gt(time_before_pause, 0.0, "Pre-condition: Time should have advanced before pause.")
		manager.pause()
		await get_tree().process_frame
		var time_after_pause = manager.get_current_time()
		assert_almost_eq(time_after_pause, time_before_pause, 0.05, "Current time should be close to time before pause.")
		assert_false(manager.is_playing(), "Manager should not be playing after pause().")
		await get_tree().create_timer(0.1).timeout
		assert_false(manager.is_playing(), "Manager should remain paused.")
		assert_almost_eq(manager.get_current_time(), time_after_pause, 0.01, "Current time should not advance while paused.")
		assert_signal_not_emitted(manager, "error_occurred", "No error should occur on valid pause.")

	func test_play_after_pause_resumes() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		manager.play()
		await get_tree().process_frame
		await get_tree().create_timer(0.1).timeout
		manager.pause()
		await get_tree().process_frame
		var pause_time = manager.get_current_time()
		assert_gt(pause_time, 0.0, "Pre-condition: Should be paused at non-zero time.")
		manager.play()
		assert_almost_eq(manager.get_current_time(), pause_time, 0.05, "Current time should be near pause time on resume.")
		assert_true(manager.is_playing(), "Manager should be playing after resuming.")
		await get_tree().create_timer(0.1).timeout
		assert_gt(manager.get_current_time(), pause_time, "Current time should be greater than pause time after resuming.")
		assert_signal_not_emitted(manager, "error_occurred", "No error should occur on valid resume.")

	func test_restart_seeks_to_zero_and_emits_signals() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		manager.play()
		await get_tree().process_frame
		await get_tree().create_timer(0.1).timeout
		assert_gt(manager.get_current_time(), 0.0, "Pre-condition: Time should be > 0 before restart.")
		manager.restart()
		assert_almost_eq(manager.get_current_time(), 0.0, 0.03, "Current time should be 0.0 after restart.")
		assert_true(manager.is_playing(), "Manager should be playing after restart (due to seek resuming).")
		assert_signal_not_emitted(manager, "error_occurred", "No error should occur on valid restart.")


class TestSeeking:
	extends GutTest

	var manager: Node
	const TEST_SONG_PATH = "res://resources/test_audio.ogg"

	func before_each():
		manager = get_node_or_null("/root/RhythmGameManager")
		assert_ne(manager, null, "RhythmGameManager singleton should be loaded.")
		if manager._audio_stream_player.stream:
			manager.pause()
			manager._audio_stream_player.stream = null
			manager.song_length = 0.0
			manager.__time = 0.0
			manager._timing_map = []
			manager._current_timing_segment_index = -1
		else:
			# Ensure a song is loaded for seeking tests that need it
			# Some tests check seeking *without* loading, they will handle it
			pass # Loading handled in tests needing it
		watch_signals(manager)

	func test_seek_without_loading() -> void:
		manager.seek(5.0)
		await get_tree().process_frame
		assert_eq(manager.get_current_time(), 0.0, "Time should remain 0 after failed seek.")
		assert_signal_not_emitted(manager, "seeked", "seeked signal should not emit if no song is loaded.")

	func test_seek_while_paused() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		await get_tree().process_frame
		var seek_time = 2.5
		manager.seek(seek_time)
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_time(), seek_time, 0.01, "Current time should be updated after seek.")
		assert_false(manager.is_playing(), "Should remain paused after seeking while paused.")
		assert_signal_not_emitted(manager, "error_occurred", "error_occurred should not emit on valid seek.")

	func test_seek_while_playing() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		manager.play()
		await get_tree().process_frame
		var seek_time = 3.0
		manager.seek(seek_time)
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_time(), seek_time, 0.03, "Current time should be updated after seek.")
		assert_true(manager.is_playing(), "Should resume playing after seeking while playing.")
		assert_signal_not_emitted(manager, "error_occurred", "error_occurred should not emit on valid seek.")
		await get_tree().create_timer(0.1).timeout
		assert_gt(manager.get_current_time(), seek_time, "Time should advance after seeking while playing.")

	func test_seek_to_end() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		await get_tree().process_frame
		var seek_time = manager.song_length
		manager.seek(seek_time)
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_time(), seek_time, 0.01, "Current time should be song length.")
		assert_false(manager.is_playing(), "Should not be playing after seeking to end.")
		assert_signal_not_emitted(manager, "error_occurred", "error_occurred should not emit on valid seek to end.")

	func test_seek_beyond_end_clamps_and_errors() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		await get_tree().process_frame
		var seek_time = manager.song_length + 10.0
		manager.seek(seek_time)
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_time(), manager.song_length, 0.01, "Current time should be clamped to song length.")
		assert_false(manager.is_playing(), "Should not be playing after seeking beyond end.")

	func test_seek_negative_clamps_and_errors() -> void:
		assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
		await get_tree().process_frame
		manager.seek(-5.0)
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_time(), 0.0, 0.01, "Current time should be clamped to 0.0.")
		assert_false(manager.is_playing(), "Should not be playing after seeking negative.")


class TestTimingMapManagement:
	extends GutTest

	var manager: Node
	const TEST_SONG_PATH = "res://resources/test_audio.ogg"

	func before_each():
		manager = get_node_or_null("/root/RhythmGameManager")
		assert_ne(manager, null, "RhythmGameManager singleton should be loaded.")
		assert_true(manager.load_song(TEST_SONG_PATH), "Failed to load test song in before_each.")
		await get_tree().process_frame # Ensure load completes
		manager._timing_map = []
		manager._current_timing_segment_index = -1
		watch_signals(manager)

	func create_valid_timing_map() -> Array:
		return [
			{"time": 0.0, "bpm": 120.0, "time_signature": [4, 4]},
			{"time": 2.0, "bpm": 180.0, "time_signature": [3, 4]},
			{"time": 4.0, "bpm": 90.0, "time_signature": [4, 4]}
		]

	func test_set_timing_map_success() -> void:
		var map = create_valid_timing_map()
		var success = manager.set_timing_map(map)
		await get_tree().process_frame
		assert_true(success, "set_timing_map should return true for valid map.")
		assert_eq_deep(manager.get_timing_map(), map)
		assert_signal_not_emitted(manager, "error_occurred", "error_occurred should not emit on valid set_timing_map.")
		assert_signal_emitted(manager, "timing_map_set", "timing_map_set should be emitted on success.") # Need to check signal args maybe

	func test_set_timing_map_failure_not_array() -> void:
		var success = manager.set_timing_map("not an array")
		await get_tree().process_frame
		assert_false(success, "set_timing_map should return false for non-array input.")
		assert_eq(manager.get_timing_map(), [], "Timing map should remain empty after failed set.")
		assert_signal_not_emitted(manager, "timing_map_set", "timing_map_set should not emit on failure.")
		assert_signal_emitted(manager, "error_occurred", "error_occurred should be emitted.")

	func test_set_timing_map_failure_invalid_structure() -> void:
		var map = [
			{"time": 0.0, "bpm": 120.0}, # Missing time_signature
			{"time": 2.0, "bpm": 180.0, "time_signature": [3, 4]}
		]
		var success = manager.set_timing_map(map)
		await get_tree().process_frame
		assert_false(success, "set_timing_map should return false for map with missing keys.")
		assert_eq(manager.get_timing_map(), [], "Timing map should remain empty after failed set.")
		assert_signal_not_emitted(manager, "timing_map_set", "timing_map_set should not emit on failure.")
		assert_signal_emitted(manager, "error_occurred", "error_occurred should be emitted.")

	func test_set_timing_map_failure_unsorted() -> void:
		var map = [
			{"time": 2.0, "bpm": 180.0, "time_signature": [3, 4]},
			{"time": 0.0, "bpm": 120.0, "time_signature": [4, 4]}
		]
		var success = manager.set_timing_map(map)
		await get_tree().process_frame
		assert_false(success, "set_timing_map should return false for unsorted map.")
		assert_eq(manager.get_timing_map(), [], "Timing map should remain empty after failed set.")
		assert_signal_not_emitted(manager, "timing_map_set", "timing_map_set should not emit on failure.")
		assert_signal_emitted(manager, "error_occurred", "error_occurred should be emitted.")


class TestTimingInfoRetrieval:
	extends GutTest

	var manager: Node
	const TEST_SONG_PATH = "res://resources/test_audio.ogg"

	func before_each():
		manager = get_node_or_null("/root/RhythmGameManager")
		assert_ne(manager, null, "RhythmGameManager singleton should be loaded.")
		assert_true(manager.load_song(TEST_SONG_PATH), "Failed to load test song in before_each.")
		var map = create_valid_timing_map() # Set up the map needed for these tests
		assert_true(manager.set_timing_map(map), "Failed to set timing map in before_each.")
		await get_tree().process_frame
		watch_signals(manager)

	func create_valid_timing_map() -> Array:
		return [
			{"time": 0.0, "bpm": 120.0, "time_signature": [4, 4]},
			{"time": 2.0, "bpm": 180.0, "time_signature": [3, 4]},
			{"time": 4.0, "bpm": 90.0, "time_signature": [4, 4]}
		]

	func test_get_timing_info_at_time() -> void:
		var map = create_valid_timing_map() # Get the map again for comparison
		assert_eq_deep(manager.get_timing_info_at_time(-1.0), {})
		assert_eq_deep(manager.get_timing_info_at_time(0.0), map[0])
		assert_eq_deep(manager.get_timing_info_at_time(1.5), map[0])
		assert_eq_deep(manager.get_timing_info_at_time(2.0), map[1])
		assert_eq_deep(manager.get_timing_info_at_time(3.99), map[1])
		assert_eq_deep(manager.get_timing_info_at_time(4.0), map[2])
		assert_eq_deep(manager.get_timing_info_at_time(10.0), map[2])

	func test_get_bpm_at_time() -> void:
		assert_almost_eq(manager.get_bpm_at_time(-1.0), 0.0, 0.01, "BPM should be 0 before first segment.")
		assert_almost_eq(manager.get_bpm_at_time(0.0), 120.0, 0.01, "BPM at 0.0s")
		assert_almost_eq(manager.get_bpm_at_time(1.5), 120.0, 0.01, "BPM at 1.5s")
		assert_almost_eq(manager.get_bpm_at_time(2.0), 180.0, 0.01, "BPM at 2.0s")
		assert_almost_eq(manager.get_bpm_at_time(3.99), 180.0, 0.01, "BPM at 3.99s")
		assert_almost_eq(manager.get_bpm_at_time(4.0), 90.0, 0.01, "BPM at 4.0s")
		assert_almost_eq(manager.get_bpm_at_time(10.0), 90.0, 0.01, "BPM at 10.0s")

	func test_get_time_signature_at_time() -> void:
		assert_eq_deep(manager.get_time_signature_at_time(-1.0), [4, 4])
		assert_eq_deep(manager.get_time_signature_at_time(0.0), [4, 4])
		assert_eq_deep(manager.get_time_signature_at_time(1.5), [4, 4])
		assert_eq_deep(manager.get_time_signature_at_time(2.0), [3, 4])
		assert_eq_deep(manager.get_time_signature_at_time(3.99), [3, 4])
		assert_eq_deep(manager.get_time_signature_at_time(4.0), [4, 4])
		assert_eq_deep(manager.get_time_signature_at_time(10.0), [4, 4])

	func test_get_current_bpm_and_time_sig() -> void:
		assert_almost_eq(manager.get_current_bpm(), 120.0, 0.01, "Current BPM at 0.0s")
		assert_eq_deep(manager.get_current_time_signature(), [4, 4])

		manager.seek(2.5)
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_bpm(), 180.0, 0.01, "Current BPM at 2.5s")
		assert_eq_deep(manager.get_current_time_signature(), [3, 4])

		manager.seek(4.1)
		await get_tree().process_frame
		assert_almost_eq(manager.get_current_bpm(), 90.0, 0.01, "Current BPM at 4.1s")
		assert_eq_deep(manager.get_current_time_signature(), [4, 4])

		manager.seek(1.8)
		await get_tree().process_frame
		manager.play()
		await get_tree().create_timer(0.5).timeout # Should push time past 2.0s
		assert_true(manager.get_current_time() > 2.0, "Time should be past 2.0s")
		assert_almost_eq(manager.get_current_bpm(), 180.0, 0.01, "Current BPM should update after crossing segment boundary during play")
		assert_eq_deep(manager.get_current_time_signature(), [3, 4])
