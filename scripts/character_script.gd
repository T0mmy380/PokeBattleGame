extends CharacterBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var character_selector_ui: Node2D = $"../Character Selector UI"
@onready var nav_layer: TileMapLayer = get_tree().get_first_node_in_group("nav_layer")
@onready var wall_layer: TileMapLayer = get_tree().get_first_node_in_group("wall_layer")
# TileMap root used to render overlays in map space.
@onready var tilemap_root: Node2D = nav_layer.get_parent() if nav_layer != null else get_parent()

const speed := 100.0
const ARRIVE_DISTANCE := 2.0 # Final snap tolerance in pixels.
const ATTACK_FLASH_SECONDS := 0.2

var last_direction: Vector2 = Vector2.DOWN

var is_jumping := false
var jump_timer := 0.0
var jump_total := 0.0
var jump_anim_name := ""

var astar_grid: AStarGrid2D

var path_cells := PackedVector2Array()
var path_index := 0
var hover_cell := Vector2i.ZERO
var selected_cell := Vector2i.ZERO
var has_hover := false
var has_selected := false

var path_line: Line2D
var hover_sprite: Sprite2D
var selected_sprite: Sprite2D
var attack_sprite: Sprite2D

# ------------------------------------------------------------------------------
# PHYSICS PROCESS
# ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	process_jump(delta)
	process_movement(delta)
	update_facing_from_input()
	process_animation()
	move_and_slide()
	update_path_line()


func _ready() -> void:

	setup_pathfinding()
	setup_click_move_visuals()


# ------------------------------------------------------------------------------
# JUMP
# ------------------------------------------------------------------------------

func process_jump(delta: float) -> void:
	# Start jump
	if not is_jumping and Input.is_action_just_pressed("jump"):
		start_jump()

	if is_jumping:
		# While jumping: if direction changes, switch jump anim to match
		var dir := velocity.normalized()
		if dir != Vector2.ZERO:
			last_direction = snap_direction_cardinal(dir)
			var desired := get_anim_name("hop", dir)
			if desired != jump_anim_name:
				switch_jump_anim_preserve_progress(desired)

		# Count down jump time
		jump_timer -= delta
		if jump_timer <= 0.0:
			end_jump()


func start_jump() -> void:
	is_jumping = true

	var dir := velocity.normalized()
	if dir == Vector2.ZERO:
		dir = last_direction
	else:
		last_direction = snap_direction_cardinal(dir)

	jump_anim_name = get_anim_name("hop", dir)

	animated_sprite_2d.play(jump_anim_name)
	animated_sprite_2d.sprite_frames.set_animation_loop(jump_anim_name, false)

	jump_total = get_anim_length_seconds(jump_anim_name)
	jump_timer = jump_total


func switch_jump_anim_preserve_progress(new_anim: String) -> void:
	# Progress through jump (0..1)
	var t := 0.0
	if jump_total > 0.0:
		t = clamp(1.0 - (jump_timer / jump_total), 0.0, 1.0)

	jump_anim_name = new_anim

	# Play the new directional jump anim (no looping)
	animated_sprite_2d.play(jump_anim_name)
	animated_sprite_2d.sprite_frames.set_animation_loop(jump_anim_name, false)

	# Set frame to match the same progress through the animation
	var frames := animated_sprite_2d.sprite_frames.get_frame_count(jump_anim_name)
	if frames <= 1:
		animated_sprite_2d.frame = 0
		animated_sprite_2d.frame_progress = 0.0
		return

	var frame_f := t * float(frames - 1)
	var frame_i := int(floor(frame_f))
	animated_sprite_2d.frame = clamp(frame_i, 0, frames - 1)
	animated_sprite_2d.frame_progress = clamp(frame_f - float(frame_i), 0.0, 1.0)


func end_jump() -> void:
	is_jumping = false

	# Land on last frame
	var frames := animated_sprite_2d.sprite_frames.get_frame_count(jump_anim_name)
	animated_sprite_2d.frame = max(frames - 1, 0)
	animated_sprite_2d.frame_progress = 0.0
	animated_sprite_2d.stop()


func get_anim_length_seconds(anim_name: String) -> float:
	if animated_sprite_2d.sprite_frames == null:
		return 0.0
	if not animated_sprite_2d.sprite_frames.has_animation(anim_name):
		return 0.0

	var frames := animated_sprite_2d.sprite_frames.get_frame_count(anim_name)
	var fps := animated_sprite_2d.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return 0.0

	return float(frames) / float(fps)

# ------------------------------------------------------------------------------
# MOVEMENT & ANIMATION
# ------------------------------------------------------------------------------

func process_movement(delta: float) -> void:
	if path_cells.is_empty() or path_index >= path_cells.size():
		velocity = Vector2.ZERO
		return

	var target_cell := path_cells[path_index]
	var target_pos := cell_to_world_center(target_cell)
	var to_target := target_pos - global_position

	var step := speed * delta
	if to_target.length() <= step:
		# Snap to exact tile center before advancing.
		global_position = target_pos
		path_index += 1
		if path_index >= path_cells.size():
			velocity = Vector2.ZERO
			return
		target_cell = path_cells[path_index]
		target_pos = cell_to_world_center(target_cell)
		to_target = target_pos - global_position

	if to_target != Vector2.ZERO:
		velocity = to_target.normalized() * speed
		last_direction = snap_direction_cardinal(velocity)
	else:
		velocity = Vector2.ZERO


func process_animation() -> void:
	# Jump has priority; do not play walk/idle during jump
	if is_jumping:
		return

	if velocity != Vector2.ZERO:
		animated_sprite_2d.play(get_anim_name("walk", last_direction))
	else:
		animated_sprite_2d.play(get_anim_name("idle", last_direction))

# ------------------------------------------------------------------------------
# ANIMATION NAME HELPERS
# ------------------------------------------------------------------------------

func update_facing_from_input() -> void:
	# Allow turning in place when not moving.
	if is_jumping:
		return
	if velocity != Vector2.ZERO:
		return

	var x := Input.get_axis("left", "right")
	var y := Input.get_axis("up", "down")
	var input_dir := Vector2.ZERO
	# Enforce single-axis facing (no diagonals).
	if x != 0.0:
		input_dir = Vector2(sign(x), 0)
	elif y != 0.0:
		input_dir = Vector2(0, sign(y))

	if input_dir != Vector2.ZERO:
		last_direction = input_dir

func get_anim_name(prefix: String, dir: Vector2) -> String:
	# stable 8-dir resolution (reduces diagonal flicker)
	var x := 0
	var y := 0
	if dir.x > 0.1: x = 1
	elif dir.x < -0.1: x = -1
	if dir.y > 0.1: y = 1
	elif dir.y < -0.1: y = -1

	if x == 1 and y == 1:
		return prefix + "_down_right"
	elif x == 1 and y == -1:
		return prefix + "_up_right"
	elif x == -1 and y == 1:
		return prefix + "_down_left"
	elif x == -1 and y == -1:
		return prefix + "_up_left"
	elif x == 1:
		return prefix + "_right"
	elif x == -1:
		return prefix + "_left"
	elif y == 1:
		return prefix + "_down"
	elif y == -1:
		return prefix + "_up"

	return prefix + "_down"

# ------------------------------------------------------------------------------
# CHARACTER SELECTOR
# ------------------------------------------------------------------------------

func set_character_by_name(char_name: String) -> void:
	var full_char : Array = split_name(char_name)
	var c_name = full_char[0]
	var form = full_char[1]
	
	print("set_character_by_name called with: %s" % char_name)
	var animFrames_path := "res://assets/characters/pokemon/%s/sprites/sprites_%s/anims/%s_frames.tres" % [c_name, form, c_name]
	var animFrames := load(animFrames_path) as SpriteFrames
	print("Loaded SpriteFrames at path: %s" % animFrames_path)

	if animFrames == null:
		push_error("Failed to load SpriteFrames at path: %s" % animFrames_path)
		return
	
	animated_sprite_2d.sprite_frames = animFrames


func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER:
			character_selector_ui.popup.popup()
			return

		# Simple melee attack (1 tile in front).
		if event.is_action_pressed("attack"):
			perform_attack()
			return

	if nav_layer == null:
		return

	if event is InputEventMouseMotion:
		# Hover highlight.
		update_hover_cell(get_global_mouse_position())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Click-to-move.
		var click_cell := world_to_cell(get_global_mouse_position())
		if is_cell_walkable(click_cell):
			set_selected_cell(click_cell)
			set_path_to(click_cell)

# ------------------------------------------------------------------------------
# ATTACK
# ------------------------------------------------------------------------------

func perform_attack() -> void:
	var facing_step := get_facing_step()
	var origin_cell := world_to_cell(global_position)
	var target_cell := origin_cell + facing_step

	if not is_cell_in_bounds(target_cell):
		return

	# Flash the targeted tile in red.
	if attack_sprite != null:
		attack_sprite.visible = true
		attack_sprite.position = cell_to_tilemap_local_center(target_cell)
		_flash_attack_tile()


func _flash_attack_tile() -> void:
	await get_tree().create_timer(ATTACK_FLASH_SECONDS).timeout
	if attack_sprite != null:
		attack_sprite.visible = false


# ---------------------------------------------------------------------------------
# HELPER
# ---------------------------------------------------------------------------------

func split_name(char_name: String) -> Array:
	var parts := char_name.split("_")
	if parts.size() >= 2:
		return parts
	else:
		return [char_name, "normal"]

func get_facing_step() -> Vector2i:
	# 4-dir step based on last known facing.
	var dir := snap_direction_cardinal(last_direction)

	if dir == Vector2.ZERO:
		return Vector2i(0, 1)

	return Vector2i(int(dir.x), int(dir.y))

func snap_direction_cardinal(dir: Vector2) -> Vector2:
	# Resolve to 4 directions only (no diagonals).
	if dir == Vector2.ZERO:
		return Vector2.ZERO

	if abs(dir.x) >= abs(dir.y):
		return Vector2(sign(dir.x), 0)
	return Vector2(0, sign(dir.y))


func setup_pathfinding() -> void:
	# Build the A* grid from the ground + wall layers.
	if nav_layer == null or nav_layer.tile_set == null:
		return

	astar_grid = AStarGrid2D.new()
	astar_grid.cell_size = nav_layer.tile_set.tile_size
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER

	var used_rect := nav_layer.get_used_rect()
	if used_rect == Rect2i():
		return
	astar_grid.region = used_rect
	astar_grid.update()

	for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
		for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
			var cell := Vector2i(x, y)
			var has_ground := nav_layer.get_cell_source_id(cell) != -1
			var is_blocked := wall_layer != null and wall_layer.get_cell_source_id(cell) != -1
			astar_grid.set_point_solid(cell, not has_ground or is_blocked)


func setup_click_move_visuals() -> void:
	# Create an overlay node to draw highlights/lines in map space.
	if tilemap_root == null or nav_layer == null:
		return

	var viz := Node2D.new()
	viz.name = "ClickMoveViz"
	viz.z_index = 10
	# Defer add to avoid "parent busy" during _ready.
	tilemap_root.call_deferred("add_child", viz)

	path_line = Line2D.new()
	path_line.name = "PathLine"
	path_line.width = 2.0
	path_line.default_color = Color(0.2, 0.8, 1.0, 0.7)
	path_line.antialiased = true
	path_line.z_index = 1
	viz.call_deferred("add_child", path_line)

	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)

	hover_sprite = Sprite2D.new()
	hover_sprite.name = "HoverTile"
	hover_sprite.texture = tex
	hover_sprite.modulate = Color(0.2, 0.8, 1.0, 0.25)
	hover_sprite.visible = false
	hover_sprite.z_index = 2
	viz.call_deferred("add_child", hover_sprite)

	selected_sprite = Sprite2D.new()
	selected_sprite.name = "SelectedTile"
	selected_sprite.texture = tex
	selected_sprite.modulate = Color(1.0, 0.9, 0.2, 0.25)
	selected_sprite.visible = false
	selected_sprite.z_index = 3
	viz.call_deferred("add_child", selected_sprite)

	attack_sprite = Sprite2D.new()
	attack_sprite.name = "AttackTile"
	attack_sprite.texture = tex
	attack_sprite.modulate = Color(1.0, 0.1, 0.1, 0.4)
	attack_sprite.visible = false
	attack_sprite.z_index = 4
	viz.call_deferred("add_child", attack_sprite)

	var tile_size := get_tile_size()
	hover_sprite.scale = tile_size
	selected_sprite.scale = tile_size
	attack_sprite.scale = tile_size


func update_hover_cell(world_pos: Vector2) -> void:
	# Update hover highlight to the current mouse tile.
	if astar_grid == null:
		return

	var cell := world_to_cell(world_pos)
	if not is_cell_in_bounds(cell):
		has_hover = false
		if hover_sprite != null:
			hover_sprite.visible = false
		return

	hover_cell = cell
	has_hover = true
	if hover_sprite != null:
		hover_sprite.visible = true
		hover_sprite.position = cell_to_tilemap_local_center(cell)


func set_selected_cell(cell: Vector2i) -> void:
	# Update selected tile highlight.
	selected_cell = cell
	has_selected = true
	if selected_sprite != null:
		selected_sprite.visible = true
		selected_sprite.position = cell_to_tilemap_local_center(cell)


func set_path_to(cell: Vector2i) -> void:
	# Compute a fresh path from the current tile to the clicked tile.
	if astar_grid == null:
		return

	var start_cell := world_to_cell(global_position)
	# Snap start to its tile center to avoid drift.
	global_position = cell_to_world_center(start_cell)
	var new_path := astar_grid.get_id_path(start_cell, cell)
	path_cells = PackedVector2Array(new_path)
	path_index = 0
	if path_cells.size() > 0 and path_cells[0] == Vector2(start_cell):
		path_index = 1

	update_path_line()


func update_path_line() -> void:
	# Draw a line from the character to the remaining path tiles.
	if path_line == null:
		return

	if path_cells.is_empty() or path_index >= path_cells.size():
		path_line.clear_points()
		return

	var points := PackedVector2Array()
	points.append(tilemap_root.to_local(global_position))
	for i in range(path_index, path_cells.size()):
		points.append(cell_to_tilemap_local_center(path_cells[i]))
	path_line.points = points


func is_cell_in_bounds(cell: Vector2i) -> bool:
	if astar_grid == null:
		return false
	return astar_grid.is_in_boundsv(cell)


func is_cell_walkable(cell: Vector2i) -> bool:
	if astar_grid == null:
		return false
	if not astar_grid.is_in_boundsv(cell):
		return false
	return not astar_grid.is_point_solid(cell)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	# Convert world-space position to tile coords.
	if nav_layer == null:
		return Vector2i.ZERO
	return nav_layer.local_to_map(nav_layer.to_local(world_pos))


func cell_to_world_center(cell: Vector2i) -> Vector2:
	# Convert tile coords to world-space tile center.
	if nav_layer == null:
		return global_position
	var local_pos := nav_layer.map_to_local(cell)
	return nav_layer.to_global(local_pos)


func cell_to_tilemap_local_center(cell: Vector2i) -> Vector2:
	# Convert tile coords to TileMap-local position for overlay rendering.
	if nav_layer == null or tilemap_root == null:
		return Vector2.ZERO
	var world_pos := cell_to_world_center(cell)
	return tilemap_root.to_local(world_pos)


func get_tile_size() -> Vector2:
	if nav_layer != null and nav_layer.tile_set != null:
		return nav_layer.tile_set.tile_size
	return Vector2(32, 32)
