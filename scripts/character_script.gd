extends CharacterBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var character_selector_ui: Node2D = $"../Character Selector UI"

const SPEED := 100.0

var last_direction: Vector2 = Vector2.DOWN

var is_jumping := false
var jump_timer := 0.0
var jump_total := 0.0
var jump_anim_name := ""

var form_name: String = "normal" 



func _ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	process_jump(delta)
	process_movement()
	process_animation()
	move_and_slide()


# ------------------------------------------------------------------------------
# JUMP
# ------------------------------------------------------------------------------

func process_jump(delta: float) -> void:
	# Start jump
	if not is_jumping and Input.is_action_just_pressed("jump"):
		start_jump()

	if is_jumping:
		# While jumping: if direction changes, switch jump anim to match
		var dir := Input.get_vector("left", "right", "up", "down")
		if dir != Vector2.ZERO:
			last_direction = dir
			var desired := get_anim_name("hop", dir)
			if desired != jump_anim_name:
				switch_jump_anim_preserve_progress(desired)

		# Count down jump time
		jump_timer -= delta
		if jump_timer <= 0.0:
			end_jump()

func start_jump() -> void:
	is_jumping = true

	var dir := Input.get_vector("left", "right", "up", "down")
	if dir == Vector2.ZERO:
		dir = last_direction
	else:
		last_direction = dir

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

func process_movement() -> void:
	# Allow movement during jump (change if you want it locked)
	var direction := Input.get_vector("left", "right", "up", "down")

	if direction != Vector2.ZERO:
		velocity = direction.normalized() * SPEED
		last_direction = direction
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

var current_dir := "s"

func set_character_by_name(char_name: String) -> void:
	print("set_character_by_name called with: %s" % char_name)
	var animFrames_path := "res://assets/characters/pokemon/%s/sprites/sprites_%s/anims/%s_frames.tres" % [char_name, form_name, char_name]
	var animFrames := load(animFrames_path) as SpriteFrames
	print("Loaded SpriteFrames at path: %s" % animFrames_path)

	if animFrames == null:
		push_error("Failed to load SpriteFrames at path: %s" % animFrames_path)
		return
	
	animated_sprite_2d.sprite_frames = animFrames
	
# ------------------------------------------------------------------------------
# CHARACTER SELECTOR
# ------------------------------------------------------------------------------
func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER:
			character_selector_ui.popup.popup()



		'''
		if event.keycode == KEY_1:
			set_character_by_name("greninja")
			print("Character set to Greninja")
		elif event.keycode == KEY_2:
			set_character_by_name("golurk")
			print("Character set to Golurk")
		elif event.keycode == KEY_3:
			set_character_by_name("scolipede")
			print("Character set to Scolipede")
		'''
