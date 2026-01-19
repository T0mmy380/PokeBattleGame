@tool
extends EditorScript

const DIRS := {
	"down": Vector2.DOWN,
	"down_right": Vector2(0.7071068, 0.7071068),
	"right": Vector2.RIGHT,
	"up_right": Vector2(0.7071068, -0.7071068),
	"up": Vector2.UP,
	"up_left": Vector2(-0.7071068, -0.7071068),
	"left": Vector2.LEFT,
	"down_left": Vector2(-0.7071068, 0.7071068)
}

const BASE_TICK_FPS := 60

# CONFIG
const CHAR_NAME := "golurk" 
const BASE_PATH := "res://assets/characters//pokemon/%s/sprites/" % CHAR_NAME
const XML_PATH := BASE_PATH + "AnimData.xml"

const ANIMATIONS := {
	"idle": {
		"frames": 4,
		"fps": 5,
		"loop": true
	},
	"walk": {
		"frames": 4,
		"fps": 5,
		"loop": true
	},
	"hop": {
		"frames": 10,
		"fps": 9,
		"loop": false
	},
}

func _run() -> void:
	var frames_res := SpriteFrames.new()

	for anim_key in ANIMATIONS.keys():
		var sheet_path := "%s%s-Anim.png" % [BASE_PATH, anim_key.capitalize()]
		var anim_sheet = load(sheet_path) as Texture2D
		if anim_sheet == null:
			push_error("Animation sheet not loaded.")
			return
		
		var sheet_size = anim_sheet.get_size()
		var per_row := int(ANIMATIONS[anim_key]["frames"])
		var fps := int(ANIMATIONS[anim_key]["fps"])
		var loop := int(ANIMATIONS[anim_key]["loop"])
		var num_dirs := DIRS.size()
		var frame_width := int(sheet_size.x / per_row)
		push_error("PerRow: %d" % per_row)
		var frame_height := int(sheet_size.y / num_dirs)
		push_error("NumDirs: %d" % num_dirs)


		var row_idx := 0
		for row in DIRS.keys():
			var dir := DIRS[row] as Vector2
			var anim_name := "%s_%s" % [anim_key, row]  

			push_error("Processing animation: %s, direction: %s" % [anim_key, row])
			push_error("Animation name: %s" % anim_name)
			push_error("Direction vector: %s" % dir)

			frames_res.add_animation(anim_name)
			frames_res.set_animation_speed(anim_name, fps)
			frames_res.set_animation_loop(anim_name, loop)

			for col in range(per_row):
				var region := Rect2i(Vector2i(col * frame_width, row_idx * frame_height), Vector2i(frame_width, frame_height))
				push_error("Column: %s" % col)
				push_error("Frame Width: %s" % frame_width)
				push_error("Row Idx: %s" % row_idx)
				push_error("Frame Height: %s" % row_idx)
				push_error("Region: %s" % region)
				var atlas := AtlasTexture.new()
				atlas.atlas = anim_sheet
				atlas.region = region
				frames_res.add_frame(anim_name, atlas)
	
			row_idx +=1

	var out_dir := BASE_PATH + "anims/"
	var directory := DirAccess.open(BASE_PATH)
	if directory:
		if !directory.dir_exists("anims"):
			directory.make_dir("anims")

	var out_path := out_dir + CHAR_NAME + "_frames.tres"
	var err := ResourceSaver.save(frames_res, out_path)
	if err != OK:
		push_error("Failed to save: " + str(err))
	else:
		print("Saved: ", out_path)
