@tool
extends EditorScript

const DIR_ORDER := ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]
@export var tick_rate: float = 30.0

var form_name: String = "shiny" 

# CONFIG (set these)
# number of charcters in folder
var CHAR_NAME := "charizard"
var BASE_PATH := "res://assets/characters/pokemon/"
var POKE_PATH := BASE_PATH + "%s" % CHAR_NAME
var SPRITES_PATH := POKE_PATH + "/sprites/"
var FORM_PATH := SPRITES_PATH + "sprites_%s/" % form_name
var XML_PATH := FORM_PATH + "AnimData.xml"

func _run() -> void:
    print("base path: ", BASE_PATH)
    print("poke path: ", POKE_PATH)
    print("sprites path: ", SPRITES_PATH)
    
    var forms = get_forms_from_dir(SPRITES_PATH)
    print("Forms found: ", forms)
    
    # Loop through each form
    for form in forms:
        form_name = form
        var current_form_path := SPRITES_PATH + "sprites_%s/" % form_name
        var xml_path := current_form_path + "AnimData.xml"
        
        print("\n--- Processing form: %s ---" % form_name)
        print("form path: ", current_form_path)
        print("xml path: ", xml_path)
        
        var parsed := _parse_animdata(xml_path)
        if parsed.is_empty():
            push_warning("No anims parsed for form %s. Check XML_PATH: %s" % [form_name, xml_path])
            continue

        var frames_res := SpriteFrames.new()
        var meta := {} # saved as JSON

        # Build all non-CopyOf first
        for anim_name in parsed.keys():
            var a: AnimDef = parsed[anim_name]
            if a.copy_of != "":
                continue

            var anim_png_path := "%s%s-Anim.png" % [current_form_path, anim_name]
            var tex := load(anim_png_path) as Texture2D
            if tex == null:
                push_warning("Missing PNG (skipping anim): %s" % anim_png_path)
                continue

            var sheet_size := tex.get_size()
            var fw := int(a.frame_w)
            var fh := int(a.frame_h)

            if fw <= 0 or fh <= 0:
                push_warning("Invalid frame size for %s (skipping)" % anim_name)
                continue

            var cols := int(sheet_size.x / fw)
            var rows := int(sheet_size.y / fh)

            if cols <= 0 or rows <= 0:
                push_warning("Sheet too small or wrong frame size for %s (skipping)" % anim_name)
                continue

            # If the sheet has 8 rows use 8-dir, otherwise treat as 1-dir.
            var dir_count := 8 if rows >= 8 else 1

            # Durations are per-frame (per column)
            var durations_ticks: Array = a.durations.duplicate()
            if durations_ticks.size() == 0:
                # Fallback: if XML has none, assume 10 ticks/frame
                for i in range(cols):
                    durations_ticks.append(10)

            # If duration count doesn't match cols, clamp safely.
            if durations_ticks.size() != cols:
                push_warning("%s durations (%d) != cols (%d). Clamping." % [anim_name, durations_ticks.size(), cols])
                while durations_ticks.size() < cols:
                    durations_ticks.append(durations_ticks[-1])
                if durations_ticks.size() > cols:
                    durations_ticks = durations_ticks.slice(0, cols)

            # Set a best-effort FPS for AnimatedSprite2D
            var fps := _estimate_fps_from_durations(durations_ticks)

            # Store meta for later "perfect timing" playback
            meta[anim_name] = {
                "frame_w": fw,
                "frame_h": fh,
                "cols": cols,
                "rows": rows,
                "dir_count": dir_count,
                "durations_ticks": durations_ticks,
                "durations_sec": durations_ticks.map(func(d): return float(d) / tick_rate),
                "rush_frame": a.rush_frame,
                "hit_frame": a.hit_frame,
                "return_frame": a.return_frame
            }

            for r in range(dir_count):
                var dir_key: String = DIR_ORDER[r] if dir_count == 8 else "down"
                var anim_id := "%s_%s" % [anim_name.to_lower(), dir_key]

                if frames_res.has_animation(anim_id):
                    # Avoid duplicates if rerun
                    frames_res.remove_animation(anim_id)

                frames_res.add_animation(anim_id)
                frames_res.set_animation_speed(anim_id, fps)
                frames_res.set_animation_loop(anim_id, true)

                for c in range(cols):
                    var region := Rect2i(Vector2i(c * fw, r * fh), Vector2i(fw, fh))
                    var atlas := AtlasTexture.new()
                    atlas.atlas = tex
                    atlas.region = region
                    frames_res.add_frame(anim_id, atlas)

        # Apply CopyOf links in meta (and duplicate frames by reference name)
        for anim_name in parsed.keys():
            var a: AnimDef = parsed[anim_name]
            if a.copy_of == "":
                continue

            var src := a.copy_of
            if not meta.has(src):
                push_warning("CopyOf '%s' points to missing '%s' (skipping)" % [anim_name, src])
                continue

            meta[anim_name] = meta[src].duplicate(true)
            meta[anim_name]["copy_of"] = src

            # Duplicate SpriteFrames animations (names differ)
            var src_dir_count := int(meta[src]["dir_count"])
            for r in range(src_dir_count):
                var dir_key: String = DIR_ORDER[r] if src_dir_count == 8 else "down"
                var src_anim_id := "%s_%s" % [src.to_lower(), dir_key]
                var dst_anim_id := "%s_%s" % [anim_name.to_lower(), dir_key]

                if not frames_res.has_animation(src_anim_id):
                    continue

                if frames_res.has_animation(dst_anim_id):
                    frames_res.remove_animation(dst_anim_id)

                frames_res.add_animation(dst_anim_id)
                frames_res.set_animation_speed(dst_anim_id, frames_res.get_animation_speed(src_anim_id))
                frames_res.set_animation_loop(dst_anim_id, frames_res.get_animation_loop(src_anim_id))

                var fc := frames_res.get_frame_count(src_anim_id)
                for i in range(fc):
                    var tex: Texture2D = frames_res.get_frame_texture(src_anim_id, i)
                    frames_res.add_frame(dst_anim_id, tex)

        # Ensure output folder exists
        var out_dir := current_form_path + "anims/"
        var dir := DirAccess.open(BASE_PATH)
        if dir == null:
            push_error("Could not open BASE_PATH: %s" % BASE_PATH)
            continue
        if not dir.dir_exists(current_form_path + "anims"):
            var err_make = DirAccess.make_dir_absolute(out_dir)
            if err_make != OK:
                push_error("Failed to create anim folder: %s (err=%s)" % [out_dir, str(err_make)])
                continue

        # Save SpriteFrames
        var frames_path := out_dir + "%s_%s_frames.tres" % [CHAR_NAME, form_name]
        var err := ResourceSaver.save(frames_res, frames_path)
        if err != OK:
            push_error("Failed to save frames: %s (err=%s)" % [frames_path, str(err)])
            continue

        # Save meta JSON
        var meta_path := out_dir + "%s_%s_anim_meta.json" % [CHAR_NAME, form_name]
        var f := FileAccess.open(meta_path, FileAccess.WRITE)
        if f == null:
            push_warning("Could not write meta JSON: %s" % meta_path)
        else:
            f.store_string(JSON.stringify(meta, "  "))
            f.close()

        print("✅ Saved SpriteFrames: ", frames_path)
        print("✅ Saved Meta JSON:   ", meta_path)


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
    # AnimatedSprite2D only supports one FPS per animation.
    # We estimate from average duration.
    var sum: float = 0.0
    for d in durations_ticks:
        sum += float(d)
    var avg: float = sum / float(max(1, durations_ticks.size()))
    if avg <= 0.0:
        return 6.0
    return tick_rate / avg

func get_forms_from_dir(path: String) -> Array:
    var forms := []
    var dir := DirAccess.open(path)
    if dir == null:
        push_error("Could not open path to get forms: %s" % path)
        return forms
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if dir.current_is_dir() and not file_name.begins_with("."):
            forms.append(file_name)
        file_name = dir.get_next()
    dir.list_dir_end()

    # remove sprites_ prefix if present
    for i in range(forms.size()):
        if forms[i].begins_with("sprites_"):
            forms[i] = forms[i].substr(8, forms[i].length() - 8)

    return forms