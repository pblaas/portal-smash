extends XROrigin3D
class_name XrRig

signal speed_changed(index: int, speed: float)

@export var speeds: Array[float] = [1.0, 2.0, 3.5]
@export var snap_turn_degrees := 30.0
@export var stick_deadzone := 0.2
@export var hud_seconds := 1.8

@onready var camera: XRCamera3D = $XRCamera3D
@onready var left_controller: XRController3D = $LeftController
@onready var right_controller: XRController3D = $RightController

var speed_index := 0
var snap_enabled := true
var locomotion_enabled := true

var _snap_ready := true
var _hud: Label3D
var _hud_time := 0.0
var _left_click_was := false
var _right_click_was := false


func _ready() -> void:
	_hud = Label3D.new()
	_hud.name = "SpeedHud"
	_hud.position = Vector3(0.0, -0.3, -0.7)
	_hud.pixel_size = 0.001
	_hud.font_size = 34
	_hud.modulate = Color("8fd0ff")
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.visible = false
	camera.add_child(_hud)
	_show_hud()


func _process(delta: float) -> void:
	_update_speed_toggle()
	_update_smooth_move(delta)
	_update_snap_turn()
	if _hud_time > 0.0:
		_hud_time -= delta
		if _hud_time <= 0.0:
			_hud.visible = false


func current_speed() -> float:
	if speeds.is_empty():
		return 0.0
	return speeds[clampi(speed_index, 0, speeds.size() - 1)]


static func cycle_index(index: int, total: int) -> int:
	if total <= 0:
		return 0
	return wrapi(index + 1, 0, total)


func _update_speed_toggle() -> void:
	var left_pressed := left_controller.is_button_pressed("primary_click")
	if left_pressed and not _left_click_was:
		_cycle_speed(left_controller)
	_left_click_was = left_pressed

	var right_pressed := right_controller.is_button_pressed("primary_click")
	if right_pressed and not _right_click_was:
		_cycle_speed(right_controller)
	_right_click_was = right_pressed


func _cycle_speed(hand: XRController3D) -> void:
	if speeds.size() <= 1:
		return
	speed_index = cycle_index(speed_index, speeds.size())
	speed_changed.emit(speed_index, current_speed())
	_show_hud()
	pulse_haptic(hand)


func _show_hud() -> void:
	_hud.text = "Speed %d/%d  %.1f m/s" % [
		clampi(speed_index, 0, speeds.size() - 1) + 1,
		speeds.size(),
		current_speed(),
	]
	_hud.visible = true
	_hud_time = hud_seconds


func pulse_haptic(hand, amplitude := 0.6, duration := 0.08) -> void:
	var interface := XRServer.find_interface("OpenXR")
	if interface == null or not interface.is_initialized():
		return
	var tracker: StringName = hand.tracker
	interface.trigger_haptic_pulse("haptic", tracker, 0.0, amplitude, duration, 0.0)


func _rescaled(stick: Vector2) -> Vector2:
	var magnitude := stick.length()
	if magnitude < stick_deadzone:
		return Vector2.ZERO
	if magnitude >= 1.0:
		return stick
	return stick * ((magnitude - stick_deadzone) / ((1.0 - stick_deadzone) * magnitude))


func _update_smooth_move(delta: float) -> void:
	if not locomotion_enabled:
		return
	var move := _walk_axis(left_controller.get_vector2("primary"))
	move += _walk_axis(right_controller.get_vector2("primary"))
	move = clampf(move, -1.0, 1.0)
	if is_zero_approx(move):
		return
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	global_position += forward * move * current_speed() * delta


func _walk_axis(stick: Vector2) -> float:
	stick = _rescaled(stick)
	if stick == Vector2.ZERO or absf(stick.y) <= absf(stick.x):
		return 0.0
	return stick.y


func _turn_axis(stick: Vector2) -> float:
	stick = _deadzoned(stick)
	if stick == Vector2.ZERO or absf(stick.x) <= absf(stick.y):
		return 0.0
	return stick.x


func _update_snap_turn() -> void:
	if not snap_enabled:
		_snap_ready = false
		return
	var turn := _turn_axis(left_controller.get_vector2("primary"))
	turn += _turn_axis(right_controller.get_vector2("primary"))
	if not _snap_ready:
		if absf(turn) < stick_deadzone:
			_snap_ready = true
		return
	if absf(turn) < stick_deadzone:
		return
	var angle := -deg_to_rad(snap_turn_degrees) * signf(turn)
	var head := camera.global_position
	global_position = head + (global_position - head).rotated(Vector3.UP, angle)
	global_rotate(Vector3.UP, angle)
	_snap_ready = false


func _deadzoned(stick: Vector2) -> Vector2:
	if stick.length() < stick_deadzone:
		return Vector2.ZERO
	return stick
