extends CharacterBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var character_selector_ui: Node2D = $"../Character Selector UI"

const speed := 100.0

var last_direction: Vector2 = Vector2.DOWN


func _ready() -> void:
	set_character_by_name("froakie_normal")
# ------------------------------------------------------------------------------
# PHYSICS PROCESS
# ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	process_animation()

# ------------------------------------------------------------------------------
# ANIMATION
# ------------------------------------------------------------------------------

func process_animation() -> void:

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

# ------------------------------------------------------------------------------
# CHARACTER SELECTOR
# ------------------------------------------------------------------------------

func set_character_by_name(char_name: String) -> void:
	var full_char : Array = split_name(char_name)
	var name = full_char[0]
	var form = full_char[1]
	
	print("set_character_by_name called with: %s" % char_name)
	var animFrames_path := "res://assets/characters/pokemon/%s/sprites/sprites_%s/anims/%s_frames.tres" % [name, form, name]
	var animFrames := load(animFrames_path) as SpriteFrames
	print("Loaded SpriteFrames at path: %s" % animFrames_path)

	if animFrames == null:
		push_error("Failed to load SpriteFrames at path: %s" % animFrames_path)
		return
	
	animated_sprite_2d.sprite_frames = animFrames

# ---------------------------------------------------------------------------------
# HELPER
# ---------------------------------------------------------------------------------

func split_name(char_name: String) -> Array:
	var parts := char_name.split("_")
	if parts.size() >= 2:
		return parts
	else:
		return [char_name, "normal"]
