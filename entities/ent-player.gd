#
#	Quake 3 CPM movement port
#
#	Based on WiggleWizard's Unity port
#	https://github.com/WiggleWizard/quake3-movement-unity3d/blob/master/CPMPlayer.cs
#
#	Adapted for Godot 4.0 by Jay!
#

extends CharacterBody3D


# TEMP step types
enum {
	STEP_DEFAULT = 0,
	STEP_METAL,
	STEP_DIRT,
	STEP_VENT,
	STEP_GRATE,
	STEP_TILE,
	STEP_SLOSH,
	STEP_WADE,
	STEP_WATER
}

# Movement "cmd" struct
class Cmd:
	var forward_move : float = 0
	var right_move : float = 0
	var up_move : float = 0

# Nodes
@onready var Collider : CollisionShape3D = $Collider
@onready var Head : Node3D = $Head
@onready var Cam : Camera3D = $Head/Camera
@onready var CasterUse : RayCast3D = $Head/CasterUse
@onready var AudioPlayerVoice : AudioStreamPlayer = $Head/AudioPlayerVoice
@onready var AudioPlayerFeet : AudioStreamPlayer = $AudioPlayerFeet

# Exports
@export_group("Movement")
@export var ground_speed : float = 7
@export var friction : float = 6
@export var ground_acceleration : float = 14
@export var ground_deceleration : float = 10
@export var air_acceleration : float = 2
@export var air_deceleration : float = 2
@export var air_control : float = 0.3
@export var strafe_acceleration : float = 50
@export var strafe_speed : float = 1
@export var jump_strength : float = 6.5
@export var hold_jump_to_bhop : bool = false

@export_group("View")
@export var sensitivity : float = 3
@export var sens_multiplier : float = 0.03
@export_range(0, 90, 0.1) var max_look_angle : float = 90

@export_group("Misc")
@export var fall_punch_threshold : float = 20

# OnReady vars
@onready var sens_final : float = sensitivity * sens_multiplier

# Private vars
var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity", 20)

var _cmd := Cmd.new()

var move_dir_norm : Vector3 = Vector3.ZERO
var player_vel : Vector3 = Vector3.ZERO
var player_top_vel : float = 0
var player_friction : float = 0
var wish_jump := false

var step_left : int = 0
var step_delay : float = 0


# Generic helper funcs
func _mouse_lock(state: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if state else Input.MOUSE_MODE_VISIBLE
func mouse_locked() -> bool:
	return true if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else false


# Misc helper funcs
func _play_step_sound(step_type: int = STEP_DEFAULT, step_vol: float = 0) -> void:
	step_left = 0 if step_left == 1 else 1
	var step_n : int = randi_range(0, 1) + step_left * 2
	
	var step_snd : String = "Default"
	match step_type:
		STEP_METAL:	step_snd = "Metal"
		STEP_DIRT:	step_snd = "Dirt"
		STEP_VENT:	step_snd = "Vent"
		STEP_GRATE:	step_snd = "Grate"
		STEP_TILE:	step_snd = "Tile"
		STEP_SLOSH:	step_snd = "Slosh"
		STEP_WADE:	step_snd = "Wade"
		STEP_WATER:	step_snd = "Water"
	
	SoundManager.play_sound(AudioPlayerFeet, "Feet", step_snd, step_n, step_vol)

func _update_step_sound() -> void:
	if step_delay > 0:
		return
	
	var vel_speed := velocity.length()
	
	var vel_walk := ground_speed * 0.4
	var vel_run := ground_speed * 0.8
	
	var slow_walking := vel_speed < vel_run
	
	var fvol : float = 1
	if is_on_floor() and vel_speed > 0 and (vel_speed >= vel_walk or step_delay == 0):
		fvol = 0.7 if slow_walking else 1.0
		step_delay = 0.4 if slow_walking else 0.3
		_play_step_sound(STEP_DEFAULT, fvol)


# Movement helper funcs
func _set_movement_dir() -> void:
	_cmd.forward_move = Input.get_axis("move_forward", "move_backward")
	_cmd.right_move = Input.get_axis("move_left", "move_right")

func _queue_jump() -> void:
	if hold_jump_to_bhop:
		wish_jump = Input.is_action_pressed("jump")
		return
	
	if Input.is_action_just_pressed("jump") and not wish_jump:
		wish_jump = true
	if Input.is_action_just_released("jump"):
		wish_jump = false

func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current_speed := player_vel.dot(wish_dir)
	var add_speed : float = wish_speed - current_speed
	
	if add_speed <= 0:
		return
	
	var accel_speed : float = accel * delta * wish_speed
	
	if accel_speed > add_speed:
		accel_speed = add_speed
	
	player_vel.x += accel_speed * wish_dir.x
	player_vel.z += accel_speed * wish_dir.z

func _apply_friction(t: float, delta: float) -> void:
	var vec := Vector3(player_vel.x, 0, player_vel.z)
	var speed := vec.length()
	
	var control : float = 0
	var drop : float = 0
	
	# Only if the player is on the ground then apply friction
	if is_on_floor():
		control = ground_deceleration if speed < ground_deceleration else speed
		drop = control * friction * delta * t
	
	var new_speed : float = speed - drop
	player_friction = new_speed
	if new_speed < 0:
		new_speed = 0
	if speed > 0:
		new_speed /= speed
	
	player_vel.x *= new_speed
	player_vel.z *= new_speed

func _air_control(wish_dir: Vector3, wish_speed: float, delta: float) -> void:
	# Can't control movement if not moving forward or backward
	if absf(_cmd.forward_move) < 0.001 or absf(wish_speed) < 0.001:
		return
	
	var z_speed := player_vel.y
	player_vel.y = 0
	# Next two lines are equivalent to idTech's VectorNormalize()
	var speed := player_vel.length()
	player_vel = player_vel.normalized()
	
	var dot := player_vel.dot(wish_dir)
	var k : float = 32 * (air_control * dot * dot * delta)
	
	# Change direction while slowing down
	if dot > 0:
		player_vel.x = player_vel.x * speed + wish_dir.x * k
		player_vel.y = player_vel.y * speed + wish_dir.y * k
		player_vel.z = player_vel.z * speed + wish_dir.z * k
		
		player_vel = player_vel.normalized()
		move_dir_norm = player_vel
	
	player_vel.x *= speed
	player_vel.y = z_speed
	player_vel.z *= speed


# Main movement funcs
func _ground_move(delta: float) -> void:
	# Do not apply friction if the player is queueing up the next jump
	if not wish_jump:
		_apply_friction(1, delta)
	else:
		_apply_friction(0, delta)
	
	_set_movement_dir()
	
	var wish_dir := (transform.basis * Vector3(_cmd.right_move, 0, _cmd.forward_move)).normalized()
	move_dir_norm = wish_dir
	
	var wish_speed := wish_dir.length() * ground_speed
	
	_accelerate(wish_dir, wish_speed, ground_acceleration, delta)
	
	# Reset the gravity velocity
	player_vel.y = -gravity * delta
	
	if wish_jump:
		player_vel.y = jump_strength
		wish_jump = false

func _air_move(delta: float) -> void:
	_set_movement_dir()
	
	var wish_dir := (transform.basis * Vector3(_cmd.right_move, 0, _cmd.forward_move))
	
	var wish_speed := wish_dir.length() * ground_speed
	
	wish_dir = wish_dir.normalized()
	move_dir_norm = wish_dir
	
	# CPM: Air control
	var accel : float = 0
	
	var wish_speed2 := wish_speed
	if player_vel.dot(wish_dir) < 0:
		accel = air_deceleration
	else:
		accel = air_acceleration
	# If the player is ONLY strafing left or right
	if _cmd.forward_move == 0 and _cmd.right_move != 0:
		if wish_speed > strafe_speed:
			wish_speed = strafe_speed
		accel = strafe_acceleration
	
	_accelerate(wish_dir, wish_speed, accel, delta)
	if air_control > 0:
		_air_control(wish_dir, wish_speed2, delta)
	
	# Apply gravity
	player_vel.y -= gravity * delta


# Base funcs
func _ready() -> void:
	_mouse_lock(true)

func _physics_process(delta: float) -> void:
	step_delay = clampf(step_delay - delta, 0, 1)
	_update_step_sound()
	
	# Custom movement
	_queue_jump()
	if is_on_floor():
		_ground_move(delta)
	else:
		_air_move(delta)
	
	# Move
	velocity = player_vel
	move_and_slide()
	
	# Calculate top velocity
	var udp := Vector3(player_vel.x, 0, player_vel.z)
	if udp.length() > player_top_vel:
		player_top_vel = udp.length()

func _input(event: InputEvent) -> void:
	# TEMP
	if mouse_locked() and Input.is_action_just_pressed("menu"):
		_mouse_lock(false)
	
	# Ensure that the cursor is locked
	if not mouse_locked() and Input.is_action_just_pressed("attack"):
		_mouse_lock(true)
	
	# TEMP
	if mouse_locked() and Input.is_action_just_pressed("attack"):
		_play_step_sound()
	
	# Get mouse movement
	if mouse_locked() and event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sens_final))
		Head.rotate_x(deg_to_rad(-event.relative.y * sens_final))
		
		# Clamp rotation
		Head.rotation.x = clamp(Head.rotation.x, deg_to_rad(-max_look_angle), deg_to_rad(max_look_angle))
