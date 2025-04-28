extends SceneTree

func _init():
    print("SceneExporter: _init()")
    pass

func _initialize():
    print("SceneExporter: _initialize() starting...")
    var args = OS.get_cmdline_user_args()
    print("SceneExporter: Args: ", args)
    if args.size() < 2:
        printerr("Usage: godot --headless --script scripts/utils/scene_exporter.gd -- <scene_path> <output_png_path> [width] [height]")
        quit(1)
        return

    var scene_path = args[0]
    var output_path = args[1]
    # 1080p
    # var width = 1920 # Default width
    # var height = 1080 # Default height
    # 480p
    var width = 854
    var height = 480

    if args.size() >= 3:
        width = int(args[2])
    if args.size() >= 4:
        height = int(args[3])

    print("SceneExporter: Scene Path: ", scene_path)
    print("SceneExporter: Output Path: ", output_path)
    print("SceneExporter: Dimensions: ", width, "x", height)

    if not ResourceLoader.exists(scene_path):
        printerr("Error: Scene file not found at path: ", scene_path)
        quit(1)
        return
    print("SceneExporter: Scene exists.")

    DisplayServer.window_set_size(Vector2i(width, height))
    print("SceneExporter: Viewport size set.")

    print("SceneExporter: Loading scene...")
    var packed_scene = ResourceLoader.load(scene_path)
    if packed_scene == null or not packed_scene is PackedScene:
        printerr("Error: Failed to load scene or invalid scene file: ", scene_path)
        quit(1)
        return
    print("SceneExporter: Scene loaded.")

    var scene_instance = packed_scene.instantiate()
    print("SceneExporter: Scene instantiated.")
    root.add_child(scene_instance)
    print("SceneExporter: Scene added to root.")

    print("SceneExporter: Scheduling capture...")
    call_deferred("_capture_and_save", output_path)
    print("SceneExporter: _initialize() finished.")


func _capture_and_save(output_path: String):
    print("SceneExporter: _capture_and_save() starting...")
    print("SceneExporter: Waiting for 0.5 seconds...")
    await root.get_tree().create_timer(0.5).timeout
    print("SceneExporter: Wait finished.")

    RenderingServer.force_draw()
    await root.get_tree().process_frame 
    print("SceneExporter: Forced draw and waited one frame.")

    print("SceneExporter: Capturing viewport...")
    var img = root.get_viewport().get_texture().get_image()
    if img == null or img.is_empty():
        printerr("Error: Failed to capture viewport image.")
        quit(1)
        return
    print("SceneExporter: Viewport captured successfully. Image valid: ", not img.is_empty())

    var dir = output_path.get_base_dir()
    print("SceneExporter: Ensuring output directory exists: ", dir)
    var dir_access = DirAccess.open("res://") # Use DirAccess relative to project
    var relative_dir = dir.replace("res://", "")
    if not dir_access.dir_exists(relative_dir):
        print("SceneExporter: Directory does not exist, attempting to create: ", relative_dir)
        var err = dir_access.make_dir_recursive(relative_dir)
        if err != OK:
            printerr("Error: Could not create output directory: ", dir, " Error code: ", err)
            quit(1)
            return
        print("SceneExporter: Directory created successfully.")
    else:
        print("SceneExporter: Output directory already exists.")


    print("SceneExporter: Saving image to: ", output_path)
    var err = img.save_png(output_path)
    if err != OK:
        printerr("Error: Failed to save image to: ", output_path, " Error code: ", err)
    else:
        print("SceneExporter: Successfully saved scene '", OS.get_cmdline_user_args()[0], "' to '", output_path, "'")

    print("SceneExporter: Quitting...")
    quit()