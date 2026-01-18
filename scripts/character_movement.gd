extends CharacterBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

const SPEED = 150.0
#const JUMP_VELOCITY = -400.0

var last_direction: Vector2 = Vector2.DOWN


func _physics_process(_delta: float) -> void:
	"""
	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	"""
	process_movement()
	process_animation()
	move_and_slide()

# ------------------------------------------------------------------------------
# MOVEMENT & ANIMATION
# ------------------------------------------------------------------------------

# Process movement input and update velocity.
func process_movement() -> void:
	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_vector("left", "right", "up", "down")

	if direction != Vector2.ZERO:
		velocity = direction.normalized() * SPEED
		last_direction = direction
	else:
		velocity = Vector2.ZERO

# Process animation based on movement state.
func process_animation() -> void:
	if velocity != Vector2.ZERO:
		play_animation("walk", last_direction)
	else:
		play_animation("idle", last_direction)

# Play animation based on direction.
func play_animation(prefix: String, dir: Vector2) -> void:
	if dir.x > 0 and dir.y > 0:
		animated_sprite_2d.play(prefix + "_down_right")  # Diagonal down-right
	elif dir.x > 0 and dir.y < 0:
		animated_sprite_2d.play(prefix + "_up_right")  # Diagonal up-right
	elif dir.x < 0 and dir.y > 0:
		animated_sprite_2d.play(prefix + "_down_left")  # Diagonal down-left
	elif dir.x < 0 and dir.y < 0:
		animated_sprite_2d.play(prefix + "_up_left")  # Diagonal up-left
	elif dir.x > 0:
		animated_sprite_2d.play(prefix + "_right")
	elif dir.x < 0:
		animated_sprite_2d.play(prefix + "_left")
	elif dir.y > 0:
		animated_sprite_2d.play(prefix + "_down")
	elif dir.y < 0:
		animated_sprite_2d.play(prefix + "_up")
