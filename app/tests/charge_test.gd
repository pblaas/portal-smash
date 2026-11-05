extends Node3D

# Visual check of the held-ball lightning charge.

var main: Node3D
var cam: Camera3D
var _phase := 0

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.25, 1.6)
	cam.rotation_degrees = Vector3(0, 0, 0)
	cam.fov = 78.0
	add_child(cam)
	cam.current = true


func _process(_delta: float) -> void:
	_phase += 1
	main.left_ball_state.mode = main.BallMode.HELD
	main.left_ball_state.held_hand = main.left_controller
	main.left_ball_state.body.global_position = Vector3(-0.25, 1.25, 0.2)
	if main.left_ball_state.aura != null:
		main.left_ball_state.aura.emitting = true
	main.right_ball_state.mode = main.BallMode.HELD
	main.right_ball_state.held_hand = main.right_controller
	main.right_ball_state.body.global_position = Vector3(0.25, 1.25, 0.2)
	if main.right_ball_state.aura != null:
		main.right_ball_state.aura.emitting = true
	if _phase == 40:
		var image := get_viewport().get_texture().get_image()
		image.save_png("/tmp/opencode/charge.png")
		print("saved /tmp/opencode/charge.png")
		get_tree().quit()
