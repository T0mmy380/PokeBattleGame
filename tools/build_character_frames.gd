@tool
extends EditorScript

@export var tick_rate: float = 30.0

const DIR_ORDER := ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]
const BASE_PATH := "res://assets/characters/pokemon/"


func _run() -> void:
	print("--- Starting Batch Pokémon Processing ---")
	
	var pokemon_list = get_subdirs(BASE_PATH)
	if pokemon_list.is_empty():
		push_error("No Pokémon directories found in: %s" % BASE_PATH)
		return

	for pokemon_name in pokemon_list:
		process_pokemon(pokemon_name)
	
	print("--- Batch Processing Complete ---")


## Processes a single Pokémon folder, and all its forms
func process_pokemon(pokemon_name: String) -> void:
	var poke_path := BASE_PATH + pokemon_name + "/"
	var sprites_path := poke_path + "sprites/"
	
	# Check if sprites folder exists
	if not DirAccess.dir_exists_absolute(sprites_path):
		push_warning("Skipping %s: No 'sprites' folder found." % pokemon_name)
		return

	# Find all form directories
	var forms = get_forms_from_dir(sprites_path)
	print("\n[ %s ] Found forms: %s" % [pokemon_name.to_upper(), forms])

	for form_name in forms:
		var current_form_path := sprites_path + "sprites_%s/" % form_name
		var xml_path := current_form_path + "AnimData.xml"
		
		if not FileAccess.file_exists(xml_path):
			push_warning("  Skipping form %s: AnimData.xml not found." % form_name)
			continue

		_process_form(pokemon_name, form_name, current_form_path, xml_path)


## Processes a single form of a Pokémon
func _process_form(pokemon_name: String, form_name: String, current_form_path: String, xml_path: String) -> void:
	var parsed := _parse_animdata(xml_path)
	if parsed.is_empty():
		return

	var frames_res := SpriteFrames.new()
	var meta := {} 

	# Build all non-CopyOf first
	for anim_name in parsed.keys():
		var a: AnimDef = parsed[anim_name]
		if a.copy_of != "": continue

		var anim_png_path := "%s%s-Anim.png" % [current_form_path, anim_name]
		var tex := load(anim_png_path) as Texture2D
		if tex == null: continue

		var fw := int(a.frame_w)
		var fh := int(a.frame_h)
		var sheet_size := tex.get_size()
		var cols := int(sheet_size.x / fw)
		var rows := int(sheet_size.y / fh)
		var dir_count := 8 if rows >= 8 else 1

		var durations_ticks: Array = a.durations.duplicate()
		if durations_ticks.size() == 0:
			for i in range(cols): durations_ticks.append(10)

		# Sync durations and metadata
		var fps := _estimate_fps_from_durations(durations_ticks)
		meta[anim_name] = {
			"frame_w": fw, "frame_h": fh, "cols": cols, "rows": rows,
			"dir_count": dir_count, "durations_ticks": durations_ticks,
			"durations_sec": durations_ticks.map(func(d): return float(d) / tick_rate),
			"rush_frame": a.rush_frame, "hit_frame": a.hit_frame, "return_frame": a.return_frame
		}

		for r in range(dir_count):
			var dir_key: String = DIR_ORDER[r] if dir_count == 8 else "down"
			var anim_id := "%s_%s" % [anim_name.to_lower(), dir_key]
			frames_res.add_animation(anim_id)
			frames_res.set_animation_speed(anim_id, fps)
			for c in range(cols):
				var region := Rect2i(Vector2i(c * fw, r * fh), Vector2i(fw, fh))
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = region
				frames_res.add_frame(anim_id, atlas)

	# Handle CopyOf
	for anim_name in parsed.keys():
		var a: AnimDef = parsed[anim_name]
		if a.copy_of == "" or not meta.has(a.copy_of): continue

	# Save outputs
	var out_dir := current_form_path + "anims/"
	if not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)

	var frames_path := out_dir + "%s_frames.tres" % pokemon_name
	ResourceSaver.save(frames_res, frames_path)
	
	var meta_path := out_dir + "%s_anim_meta.json" % pokemon_name
	var f := FileAccess.open(meta_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "  "))
		f.close()
	
	print("  ✅ Processed: %s (%s)" % [pokemon_name, form_name])

# -------------------------------------------------------------------
# XML PARSING
# -------------------------------------------------------------------

class AnimDef:
	var name := ""
	var copy_of := ""
	var frame_w := 0
	var frame_h := 0
	var durations: Array = []
	var rush_frame := -1
	var hit_frame := -1
	var return_frame := -1

func _parse_animdata(path: String) -> Dictionary:
	var out := {}

	var parser := XMLParser.new()
	var err := parser.open(path)
	if err != OK:
		push_error("XMLParser open failed: %s (err=%s)" % [path, str(err)])
		return out

	var current := AnimDef.new()
	var in_anim := false
	var current_tag := ""
	var durations_mode := false

	while true:
		var read_err := parser.read()
		if read_err == ERR_FILE_EOF:
			break
		if read_err != OK:
			push_error("XMLParser read failed: %s" % str(read_err))
			break

		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				current_tag = parser.get_node_name()
				if current_tag == "Anim":
					in_anim = true
					current = AnimDef.new()
				elif current_tag == "Durations":
					durations_mode = true
				elif current_tag == "Duration" and durations_mode:
					# value comes in NODE_TEXT next
					pass

			XMLParser.NODE_TEXT:
				if not in_anim:
					continue
				var text := parser.get_node_data().strip_edges()
				if text == "":
					continue

				match current_tag:
					"Name":
						current.name = text
					"CopyOf":
						current.copy_of = text
					"FrameWidth":
						current.frame_w = int(text)
					"FrameHeight":
						current.frame_h = int(text)
					"RushFrame":
						current.rush_frame = int(text)
					"HitFrame":
						current.hit_frame = int(text)
					"ReturnFrame":
						current.return_frame = int(text)
					"Duration":
						if durations_mode:
							current.durations.append(int(text))

			XMLParser.NODE_ELEMENT_END:
				var end_tag := parser.get_node_name()
				if end_tag == "Durations":
					durations_mode = false
				elif end_tag == "Anim":
					in_anim = false
					if current.name != "":
						out[current.name] = current
					current_tag = ""

	return out


# -------------------------------------------------------------------
# HELPERS
# -------------------------------------------------------------------

func _estimate_fps_from_durations(durations_ticks: Array) -> float:
	# Calculate average duration in ticks
	var sum: float = 0.0
	for d in durations_ticks:
		sum += float(d)
	var avg: float = sum / float(max(1, durations_ticks.size()))
	if avg <= 0.0:
		return 6.0
	return tick_rate / avg


func get_subdirs(path: String) -> Array:
	var dirs := []
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and not file_name.begins_with("."):
				dirs.append(file_name)
			file_name = dir.get_next()
	return dirs


func get_forms_from_dir(path: String) -> Array:
	var forms := []
	var dirs = get_subdirs(path)
	for d in dirs:
		if d.begins_with("sprites_"):
			forms.append(d.replace("sprites_", ""))
	return forms
