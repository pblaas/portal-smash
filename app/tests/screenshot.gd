extends Node3D

# Visual verification harness: instantiates the real main scene with a plain
# Camera3D, captures the standing tower, then drives a physics throw and
# captures the impact and aftermath.
# Run: timeout 120 xvfb-run -a godot --path app --xr-mode off res://tests/screenshot.tscn

var main: Node3D
var cam: Camera3D
var _phase := 0


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.9, 2.6)
	cam.rotation_degrees = Vector3(-10, 0, 0)
	cam.fov = 78.0
	add_child(cam)
	cam.current = true


func _process(_delta: float) -> void:
	_phase += 1
	if _phase == 40:
		_capture("/tmp/opencode/lab_stack.png")
	elif _phase == 45:
		main.powerup_chance = 0.0
		main.ball.mass = 30.0
		main.launch_ball(Vector3(0.0, 4.0, 1.6), Vector3(0.0, 0.0, -35.0))
	elif _phase == 72:
		_capture("/tmp/opencode/lab_impact.png")
	elif _phase == 80:
		print("score after impact: ", main.score)
	elif _phase == 220:
		_capture("/tmp/opencode/lab_after.png")
		print("score+4s: ", main.score)
		get_tree().quit()


func _capture(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("saved: ", path, "  ", image.get_size())
