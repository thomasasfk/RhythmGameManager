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
        assert_almost_eq(manager.get_current_time(), seek_time, 0.1, "Current time should be updated after seek.")
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

    func test_seek_clamps_to_song_bounds() -> void:
        assert_true(manager.load_song(TEST_SONG_PATH), "Pre-condition: Failed to load test song.")
        await get_tree().process_frame
        manager.seek(-1.0) # Seek before start
        await get_tree().process_frame
        assert_almost_eq(manager.get_current_time(), 0.0, 0.01, "Current time should be clamped to 0.0.")
        assert_signal_emitted(manager, "error_occurred", "error_occurred should emit on seek clamping.")

        manager.seek(manager.song_length + 1.0) # Seek after end
        await get_tree().process_frame
        assert_almost_eq(manager.get_current_time(), manager.song_length, 0.01, "Current time should be clamped to song length.")
        assert_signal_emitted(manager, "error_occurred", "error_occurred should emit on seek clamping.")


class TestNoteHandling:
    extends GutTest
    # This class will be removed and its tests distributed


# New classes for better organization
class TestNoteMapManagement:
    extends GutTest

    var manager: Node
    const TEST_SONG_PATH = "res://resources/test_audio.ogg"

    func before_each():
        manager = get_node_or_null("/root/RhythmGameManager")
        assert_ne(manager, null)
        assert_true(manager.load_song(TEST_SONG_PATH))
        manager._note_map = []
        manager._hit_note_ids = {}
        await get_tree().process_frame
        watch_signals(manager)

    func create_valid_note_map() -> Array:
        return [
            {"id": "note_1", "time": 1.0},
            {"id": "note_2", "time": 2.0, "lane": 1},
            {"id": "note_3", "time": 3.0},
        ]

    func test_set_note_map_success():
        var map = create_valid_note_map()
        var success = manager.set_note_map(map)
        await get_tree().process_frame
        assert_true(success)
        assert_eq_deep(manager.get_note_map(), map)
        assert_eq(manager._hit_note_ids.size(), 0)
        assert_signal_emitted(manager, "note_map_set")
        assert_signal_not_emitted(manager, "error_occurred")

    func test_set_note_map_failure_not_array():
        var success = manager.set_note_map("not an array")
        await get_tree().process_frame
        assert_false(success)
        assert_eq(manager.get_note_map(), [])
        assert_signal_emitted(manager, "error_occurred")
        assert_signal_not_emitted(manager, "note_map_set")

    func test_set_note_map_failure_invalid_structure_missing_time():
        var map = [{"id": "a"}, {"id": "b", "time": 1.0}]
        var success = manager.set_note_map(map)
        await get_tree().process_frame
        assert_false(success)
        assert_eq(manager.get_note_map(), [])
        assert_signal_emitted(manager, "error_occurred")
        assert_signal_not_emitted(manager, "note_map_set")

    func test_set_note_map_failure_invalid_structure_missing_id():
        var map = [{"time": 0.5}, {"id": "b", "time": 1.0}]
        var success = manager.set_note_map(map)
        await get_tree().process_frame
        assert_false(success)
        assert_eq(manager.get_note_map(), [])
        assert_signal_emitted(manager, "error_occurred")
        assert_signal_not_emitted(manager, "note_map_set")

    func test_set_note_map_failure_duplicate_id():
        var map = [{"id": "a", "time": 0.5}, {"id": "a", "time": 1.0}]
        var success = manager.set_note_map(map)
        await get_tree().process_frame
        assert_false(success)
        assert_eq(manager.get_note_map(), [])
        assert_signal_emitted(manager, "error_occurred")
        assert_signal_not_emitted(manager, "note_map_set")

    func test_set_note_map_failure_negative_time():
        var map = [{"id": "a", "time": -0.5}]
        var success = manager.set_note_map(map)
        await get_tree().process_frame
        assert_false(success)
        assert_eq(manager.get_note_map(), [])
        assert_signal_emitted(manager, "error_occurred")
        assert_signal_not_emitted(manager, "note_map_set")


class TestWindowSetting:
    extends GutTest

    var manager: Node
    const TEST_HIT_WINDOW_DEFAULT = 0.15
    const TEST_MISS_WINDOW_DEFAULT = 0.15

    func before_each():
        manager = get_node_or_null("/root/RhythmGameManager")
        assert_ne(manager, null)
        # Reset windows to known defaults
        manager.set_hittable_window(TEST_HIT_WINDOW_DEFAULT)
        manager.set_miss_window(TEST_MISS_WINDOW_DEFAULT)
        watch_signals(manager)

    func test_set_hittable_window_success():
        assert_true(manager.set_hittable_window(0.2))
        assert_almost_eq(manager.hittable_window, 0.2, 0.001)
        assert_signal_not_emitted(manager, "error_occurred")

    func test_set_hittable_window_failure_non_positive():
        assert_false(manager.set_hittable_window(0.0))
        assert_almost_eq(manager.hittable_window, TEST_HIT_WINDOW_DEFAULT, 0.001)
        assert_signal_emitted(manager, "error_occurred")

    func test_set_miss_window_success_positive():
        assert_true(manager.set_miss_window(0.25))
        assert_almost_eq(manager.miss_window, 0.25, 0.001)
        assert_signal_not_emitted(manager, "error_occurred")

    func test_set_miss_window_success_zero_disables():
        assert_true(manager.set_miss_window(0.0))
        assert_almost_eq(manager.miss_window, 0.0, 0.001)
        assert_signal_not_emitted(manager, "error_occurred")

    func test_set_miss_window_success_negative_disables():
        assert_true(manager.set_miss_window(-0.1))
        assert_almost_eq(manager.miss_window, -0.1, 0.001)
        assert_signal_not_emitted(manager, "error_occurred")


class TestHitAttempt:
    extends GutTest

    var manager: Node
    const TEST_SONG_PATH = "res://resources/test_audio.ogg"
    const TEST_HIT_WINDOW = 0.15

    func before_each():
        manager = get_node_or_null("/root/RhythmGameManager")
        assert_ne(manager, null)
        assert_true(manager.load_song(TEST_SONG_PATH))
        manager._note_map = []
        manager._hit_note_ids = {}
        manager.set_hittable_window(TEST_HIT_WINDOW)
        await get_tree().process_frame
        watch_signals(manager)

    func create_valid_note_map() -> Array:
        return [
            {"id": "note_1", "time": 1.0},
            {"id": "note_2", "time": 2.0, "lane": 1},
            {"id": "note_3", "time": 3.0},
        ]

    func test_attempt_hit_success_perfect():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var result = manager.attempt_hit(1.0)
        assert_true(result != null)
        assert_eq(result["note_id"], "note_1")
        assert_almost_eq(result["time_diff"], 0.0, 0.001)
        assert_true(manager._hit_note_ids.has("note_1"))
        assert_eq(manager._hit_note_ids["note_1"]["status"], "Hit")

    func test_attempt_hit_success_early():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var hit_time = 1.0 - TEST_HIT_WINDOW * 0.5
        var result = manager.attempt_hit(hit_time)
        assert_true(result != null)
        assert_eq(result["note_id"], "note_1")
        assert_almost_eq(result["time_diff"], hit_time - 1.0, 0.001)
        assert_lt(result["time_diff"], 0.0)
        assert_true(manager._hit_note_ids.has("note_1"))

    func test_attempt_hit_success_late():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var hit_time = 1.0 + TEST_HIT_WINDOW * 0.5
        var result = manager.attempt_hit(hit_time)
        assert_true(result != null)
        assert_eq(result["note_id"], "note_1")
        assert_almost_eq(result["time_diff"], hit_time - 1.0, 0.001)
        assert_gt(result["time_diff"], 0.0)
        assert_true(manager._hit_note_ids.has("note_1"))

    func test_attempt_hit_miss_too_early():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var hit_time = 1.0 - TEST_HIT_WINDOW - 0.01
        var result = manager.attempt_hit(hit_time)
        assert_true(result == null)
        assert_false(manager._hit_note_ids.has("note_1"))

    func test_attempt_hit_miss_too_late():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var hit_time = 1.0 + TEST_HIT_WINDOW + 0.01
        var result = manager.attempt_hit(hit_time)
        assert_true(result == null)
        assert_false(manager._hit_note_ids.has("note_1"))

    func test_attempt_hit_no_notes_nearby():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var result = manager.attempt_hit(5.0)
        assert_true(result == null)

    func test_attempt_hit_already_hit():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var result1 = manager.attempt_hit(1.0)
        assert_true(result1 != null)
        var result2 = manager.attempt_hit(1.01)
        assert_true(result2 == null)
        assert_eq(manager._hit_note_ids.size(), 1)

    func test_attempt_hit_chooses_closest():
        var map = [{"id": "a", "time": 1.0}, {"id": "b", "time": 1.1}]
        assert_true(manager.set_note_map(map))
        var result = manager.attempt_hit(1.06)
        assert_true(result != null)
        assert_eq(result["note_id"], "b")


class TestMissDetection:
    extends GutTest

    var manager: Node
    const TEST_SONG_PATH = "res://resources/test_audio.ogg"
    const TEST_MISS_WINDOW = 0.15

    func before_each():
        manager = get_node_or_null("/root/RhythmGameManager")
        assert_ne(manager, null)
        assert_true(manager.load_song(TEST_SONG_PATH))
        manager._note_map = []
        manager._hit_note_ids = {}
        manager.set_miss_window(TEST_MISS_WINDOW)
        await get_tree().process_frame
        watch_signals(manager)

    func create_valid_note_map() -> Array:
        return [
            {"id": "note_1", "time": 1.0},
            {"id": "note_2", "time": 2.0, "lane": 1},
            {"id": "note_3", "time": 3.0},
        ]

    func test_automatic_miss_detection():
        assert_true(manager.set_note_map(create_valid_note_map()))
        manager.play()
        await get_tree().create_timer(1.0 + TEST_MISS_WINDOW + 0.05).timeout
        manager.pause()
        await get_tree().process_frame
        assert_true(manager._hit_note_ids.has("note_1"))
        assert_eq(manager._hit_note_ids["note_1"], "Missed")
        assert_signal_emitted(manager, "note_missed", ["note_1", 1.0])
        assert_false(manager._hit_note_ids.has("note_2"))

    func test_miss_detection_disabled():
        assert_true(manager.set_note_map(create_valid_note_map()))
        assert_true(manager.set_miss_window(0.0))
        manager.play()
        await get_tree().create_timer(1.5).timeout
        manager.pause()
        await get_tree().process_frame
        assert_false(manager._hit_note_ids.has("note_1"))
        assert_signal_not_emitted(manager, "note_missed")


class TestNoteQuerying:
    extends GutTest

    var manager: Node
    const TEST_SONG_PATH = "res://resources/test_audio.ogg"

    func before_each():
        manager = get_node_or_null("/root/RhythmGameManager")
        assert_ne(manager, null)
        assert_true(manager.load_song(TEST_SONG_PATH))
        manager._note_map = []
        manager._hit_note_ids = {}
        await get_tree().process_frame
        watch_signals(manager)

    func create_valid_note_map() -> Array:
        return [
            {"id": "note_1", "time": 1.0},
            {"id": "note_2", "time": 2.0, "lane": 1},
            {"id": "note_3", "time": 3.0},
        ]

    func test_get_notes_in_range_basic():
        assert_true(manager.set_note_map(create_valid_note_map()))
        var notes = manager.get_notes_in_range(0.5, 2.5)
        assert_eq(notes.size(), 2)
        assert_eq(notes[0]["id"], "note_1")
        assert_eq(notes[0]["status"], "Pending")
        assert_eq(notes[1]["id"], "note_2")
        assert_eq(notes[1]["status"], "Pending")

    func test_get_notes_in_range_includes_status():
        assert_true(manager.set_note_map(create_valid_note_map()))
        manager.attempt_hit(1.0)
        manager._hit_note_ids["note_2"] = "Missed"

        var notes = manager.get_notes_in_range(0.0, 4.0)
        assert_eq(notes.size(), 3)
        assert_eq(notes[0]["id"], "note_1")
        assert_eq(notes[0]["status"]["status"], "Hit")
        assert_eq(notes[1]["id"], "note_2")
        assert_eq(notes[1]["status"], "Missed")
        assert_eq(notes[2]["id"], "note_3")
        assert_eq(notes[2]["status"], "Pending")


class TestSeekReset:
    extends GutTest

    var manager: Node
    const TEST_SONG_PATH = "res://resources/test_audio.ogg"

    func before_each():
        manager = get_node_or_null("/root/RhythmGameManager")
        assert_ne(manager, null)
        assert_true(manager.load_song(TEST_SONG_PATH))
        manager._note_map = []
        manager._hit_note_ids = {}
        await get_tree().process_frame
        watch_signals(manager)

    func create_valid_note_map() -> Array:
        return [
            {"id": "note_1", "time": 1.0},
            {"id": "note_2", "time": 2.0, "lane": 1},
            {"id": "note_3", "time": 3.0},
        ]

    func test_seek_resets_future_hit_status():
        assert_true(manager.set_note_map(create_valid_note_map()))
        manager.attempt_hit(1.0)
        assert_true(manager._hit_note_ids.has("note_1"))
        manager._hit_note_ids["note_2"] = "Missed"
        assert_true(manager._hit_note_ids.has("note_2"))
        manager.seek(0.5)
        await get_tree().process_frame
        assert_false(manager._hit_note_ids.has("note_1"))
        assert_false(manager._hit_note_ids.has("note_2"))

    func test_seek_does_not_reset_past_hit_status():
        assert_true(manager.set_note_map(create_valid_note_map()))
        manager.attempt_hit(1.0)
        assert_true(manager._hit_note_ids.has("note_1"))
        manager.seek(1.5)
        await get_tree().process_frame
        assert_true(manager._hit_note_ids.has("note_1"))
        assert_eq(manager._hit_note_ids["note_1"]["status"], "Hit")
        assert_false(manager._hit_note_ids.has("note_2"))
