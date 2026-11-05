extends Node3D

# Visual verification of round transition.
# Run: timeout 120 xvfb-run -a godot --path app --xr-mode off res://tests/transition_test.tscn

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
	if _phase == 30:
		# Trigger a round transition manually.
		main.score = int(ceil(main.cubes.size() * 0.99))
		main._check_round_progress()
	elif _phase == 35:
		_capture("/tmp/opencode/trans_start.png")
	elif _phase == 60:
		_capture("/tmp/opencode/trans_mid.png")
	elif _phase == 240:
		_capture("/tmp/opencode/trans_end.png")
		print("transition active: ", main._transition_active, " cubes: ", main.cubes.size())
		get_tree().quit()


func _capture(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("saved: ", path, "  ", image.get_size())
