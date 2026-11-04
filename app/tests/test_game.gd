extends SceneTree

# Headless test suite for Portal Smash (lab mode, Godot physics). Run with:
#   timeout 300 env -u DISPLAY godot --headless --xr-mode off --path app -s res://tests/test_game.gd

const MainScript = preload("res://scripts/main.gd")
const SoundKitScript = preload("res://scripts/sound_kit.gd")
const AppLogScript = preload("res://scripts/app_log.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== Portal Smash test suite ===")
	_test_layout_math()
	_test_sound_kit()
	_test_app_log()
	await _test_scene_smoke()
	await _test_grip_throw()
	await _test_powerups()
	await _test_throw_knocks_cubes()
	await _test_reset_tower()
	print("checks passed: %d, failed: %d" % [_passed, _failed])
	if _failed == 0:
		print("ALL TESTS PASSED")
	quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)


func _approx(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps


func _test_layout_math() -> void:
	_check(MainScript.CUBE_COUNT == 120, "15-row pyramid holds 120 cubes (15x16/2)")
	_check(MainScript.TOWER_ROWS == 15, "tower row count constant")
	_check(_approx(MainScript.CUBE_PITCH, 0.506, 0.001), "cube pitch has a small gap over the cube edge")

	var per_row := []
	for r in MainScript.TOWER_ROWS:
		var count := 0
		var y0 := MainScript.tower_local(MainScript.row_start(r)).y
		for i in MainScript.CUBE_COUNT:
			if MainScript.cube_row(i) == r:
				count += 1
				var pos := MainScript.tower_local(i)
				_check(_approx(pos.y, y0, 0.0001), "cube %d shares its row height" % i)
		per_row.append(count)
	_check(per_row[0] == 15 and per_row[14] == 1, "row sizes shrink 15..1 (wide base at the floor)")
	var total := 0
	for c in per_row:
		total += c
	_check(total == MainScript.CUBE_COUNT, "row sizes sum to the cube count")

	var check_base := MainScript.tower_local(MainScript.TOWER_ROWS / 2)
	var check_apex := MainScript.tower_local(MainScript.CUBE_COUNT - 1)
	_check(_approx(check_apex.x, 0.0, 0.001), "apex cube centered on top")
	_check(_approx(check_base.x, 0.0, 0.006), "base row centered")
	var apex_y := check_apex.y + MainScript.CUBE_EDGE * 0.5
	_check(apex_y < 12.0 - 0.2, "apex fits below the lab ceiling (%.2f)" % apex_y)
	var min_x := 0.0
	var max_x := 0.0
	for i in MainScript.CUBE_COUNT:
		var x := MainScript.tower_local(i).x
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
	_check(max_x - min_x < 17.0, "base spans less than the 18m room")

	var span := MainScript.tower_local(1) - MainScript.tower_local(0)
	_check(_approx(span.x, MainScript.CUBE_PITCH, 0.001), "neighbours in one row are exactly one pitch apart")


func _test_sound_kit() -> void:
	var kit = SoundKitScript.new()
	kit.build()
	for kind in ["knock", "thud", "whoosh", "chime"]:
		var stream = kit.stream_for(kind)
		_check(stream != null and not stream.data.is_empty(), "sound '%s' synthesized" % kind)
		if stream != null:
			_check(stream.data.size() > 800, "sound '%s' has samples" % kind)
			_check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "sound '%s' 16-bit" % kind)
	_check(kit.stream_for("nonexistent") == null, "unknown kind maps to null")


func _test_app_log() -> void:
	_check(AppLogScript.install(), "app log installs")
	_check(not AppLogScript.log_path().is_empty(), "log path set")


class MockHand:
	var grip := false
	var xf := Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0.5))
	var global_position: Vector3:
		get:
			return xf.origin
	var global_transform: Transform3D:
		get:
			return xf
	func is_button_pressed(_name: String) -> bool:
		return grip


func _make_main() -> Node3D:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		return null
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	# Wait for the tower warm-up unfreeze before throwing at it.
	for i in 30:
		if main.cubes.size() > 0 and is_instance_valid(main.cubes[0]) and not main.cubes[0].freeze:
			break
		await physics_frame
	return main


func _test_scene_smoke() -> void:
	var main = await _make_main()
	if main == null:
		_check(false, "main scene instantiates")
		return
	_check(main.cubes.size() == MainScript.CUBE_COUNT, "tower spawned 120 physical cubes")
	var rigid_count := 0
	for c in main.cubes:
		if is_instance_valid(c) and c is RigidBody3D:
			rigid_count += 1
	_check(rigid_count == MainScript.CUBE_COUNT, "all cubes are RigidBody3D nodes")
	var at_home := 0
	for i in main.cubes.size():
		var c = main.cubes[i]
		var want: Vector3 = MainScript.TOWER_CENTER + MainScript.tower_local(i)
		if c.position.distance_to(want) < 0.01:
			at_home += 1
		else:
			print("MISMATCH main=%d cube %03d pos=%s want=%s sleeping=%s frozen_ball=%s" % [main.get_instance_id(), i, c.position, want, c.sleeping, main.ball.freeze])
	_check(at_home == MainScript.CUBE_COUNT, "every cube spawned at its layout position")
	_check(main.ball != null and main.ball is RigidBody3D, "ball is a RigidBody3D node")
	_check(main.ball.freeze, "ball frozen while at rest")
	_check(main.ball_mode == 0, "ball starts at REST")
	_check(main.ball.global_position.distance_to(main._ball_rest_point()) < 0.01, "ball at hand-adjacent rest point")
	main.free()
	_check(true, "scene smoke complete")


func _test_grip_throw() -> void:
	var main = await _make_main()
	if main == null:
		_check(false, "grip test needs main scene")
		return
	var mock := MockHand.new()
	main.ball.global_position = main._hand_hold_point(mock)
	mock.grip = true
	main._handle_grip(mock)
	_check(main.ball_mode == 1, "grip press with ball nearby grabs it (HELD)")
	_check(main.ball_held_hand == mock, "held hand recorded")
	_check(main._grip_was.get(mock, false), "grip edge bookkeeping set on press")
	_check(main.ball.freeze, "ball frozen while held")

	main._hand_vel[mock] = Vector3(0.0, 0.0, -5.5)
	mock.grip = false
	main._handle_grip(mock)
	_check(main.ball_mode == 2, "release with fast hand enters FLYING")
	_check(main.ball.linear_velocity.z < -5.0, "throw velocity carried into the rigid body")
	_check(not main.ball.freeze, "ball unfrozen mid-flight")
	_check(main.ball_held_hand == null, "held hand cleared on throw")

	# slow release -> back to REST
	main.ball_mode = 0
	main.ball.freeze = true
	main.ball.global_position = main._hand_hold_point(mock)
	var slow := MockHand.new()
	main.ball.global_position = main._hand_hold_point(slow)
	slow.grip = true
	main._handle_grip(slow)
	_check(main.ball_mode == 1, "re-grab after throw works")
	slow.grip = false
	main._handle_grip(slow)
	_check(main.ball_mode == 0, "slow release returns ball to REST")
	_check(main.ball.linear_velocity == Vector3.ZERO, "velocity cleared on rest")

	main.free()
	_check(true, "grip/throw flow complete")


func _test_powerups() -> void:
	var main = await _make_main()
	if main == null:
		_check(false, "powerup test needs main scene")
		return
	main.powerup_chance = 0.0
	main._grant_powerup(MainScript.Powerup.HEAVY)
	_check(main.active_powerup == 1, "heavy powerup is active")
	_check(main.ball.mass > 10.0, "heavy ball mass increased")
	_check(main.ball_visual.scale.x > 1.2, "heavy ball visual grows")
	main._clear_powerup()
	_check(main.active_powerup == 0, "powerup cleared")
	_check(_approx(main.ball.mass, 10.0, 0.1), "ball mass restored")

	main._grant_powerup(MainScript.Powerup.FIRE)
	main.ball.global_position = MainScript.TOWER_CENTER + Vector3(0.0, 2.5, 0.0)
	main._explosion_center = main.ball.global_position
	main._explode()
	for i in 120:
		await physics_frame
	_check(main.score > 0, "fireball explosion knocks cubes (score=%d)" % main.score)
	var scattered := 0
	for c in main.cubes:
		if is_instance_valid(c) and c.global_position.distance_to(c.get_meta("home")) > 0.3:
			scattered += 1
	_check(scattered >= 4, "fireball scatters several cubes (%d)" % scattered)

	main.free()
	_check(true, "powerup flow complete")


func _test_throw_knocks_cubes() -> void:
	var main = await _make_main()
	if main == null:
		_check(false, "throw test needs main scene")
		return
	main.powerup_chance = 0.0
	main.ball.mass = 30.0
	main.launch_ball(Vector3(0.0, 4.0, 1.6), Vector3(0.0, 0.0, -35.0))
	_check(main.ball_mode == 2, "launched ball is FLYING")
	var settled := false
	for i in 400:
		await physics_frame
		if main.ball_mode == 0:
			settled = true
			break
	_check(settled, "ball respawned to REST after settling")
	_check(main.score >= 3, "physics throw knocks several cubes (score=%d)" % main.score)
	var scattered := 0
	for c in main.cubes:
		if is_instance_valid(c) and c.global_position.distance_to(c.get_meta("home")) > 0.3:
			scattered += 1
	_check(scattered >= 4, "knocked cubes visibly scattered (%d)" % scattered)
	var inside := 0
	for c in main.cubes:
		if is_instance_valid(c) and c.global_position.y > -0.5 and c.global_position.y < 12.0 and absf(c.global_position.x) < 9.0 and absf(c.global_position.z) < 9.0:
			inside += 1
	_check(inside == MainScript.CUBE_COUNT, "all cubes remain inside the room")
	_check(main.ball_mode == 0, "ball respawned to REST after settling")
	main.free()
	_check(true, "throw physics flow complete")


func _test_reset_tower() -> void:
	var main = await _make_main()
	if main == null:
		_check(false, "reset test needs main scene")
		return
	main.powerup_chance = 0.0
	main.ball.mass = 30.0
	main.launch_ball(Vector3(0.3, 3.0, -0.5), Vector3(0.0, 0.0, -35.0))
	for i in 120:
		await physics_frame
	_check(main.score > 0, "tower damaged before reset (score=%d)" % main.score)
	var before: int = main.cubes.size()
	main._reset_tower()
	await physics_frame
	await physics_frame
	_check(main.cubes.size() == before, "reset respawns the full tower")
	_check(main.score == 0, "score cleared on reset")
	var at_home := 0
	for i in main.cubes.size():
		var c = main.cubes[i]
		if is_instance_valid(c) and c.position.distance_to(MainScript.TOWER_CENTER + MainScript.tower_local(i)) < 0.05:
			at_home += 1
	_check(at_home == before, "reset cubes back at layout positions")
	main.free()
	_check(true, "reset flow complete")
