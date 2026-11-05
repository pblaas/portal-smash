extends Node3D

const BuildVersion = preload("res://scripts/build_version.gd")
const SoundKitScript = preload("res://scripts/sound_kit.gd")

const TOWER_CENTER := Vector3(0.0, 0.0, -3.4)
const CUBE_EDGE := 0.502
const CUBE_PITCH := 0.506
const TOWER_ROWS := 15
const CUBE_COUNT := TOWER_ROWS * (TOWER_ROWS + 1) / 2
const BALL_RADIUS := 0.15
const BALL_REST_OFFSET_LEFT := Vector3(-0.55, 0.92, -0.65)
const BALL_REST_OFFSET_RIGHT := Vector3(0.55, 0.92, -0.65)
const BALL_FOLLOW_OFFSET := Vector3(0.0, -0.06, -0.2)
const GRAB_RADIUS := 0.9
const THROW_MIN_SPEED := 1.0
const THROW_SPEED_SCALE := 1.25
const KNOCK_DIST := 0.26
const SETTLE_SPEED := 0.7
const SETTLE_TIME := 1.3
const SOUND_POOL_SIZE := 10
const POWERUP_DURATION := 10.0
const POWERUP_CHANCE := 0.30
const FIREBALL_RADIUS := 4.8
const FIREBALL_FORCE := 6.0
const CUBE_MASS := 0.3
const BALL_BASE_MASS := 10.0
const HEAVY_MASS := 30.0
const ICE_MASS := 8.0
const ICE_IMPULSE := 16.0
const INDENT_RECOVER := 0.22
const INDENT_MAX := 0.18
const ROUND_COUNT := 10
const ROUND_ADVANCE_THRESHOLD := 0.98
const RESTART_BOX_SIZE := 1.4

const TRANSITION_OLD_SINK_DURATION := 0.6
const TRANSITION_RISE_DELAY := 0.65
const TRANSITION_RISE_DURATION := 1.6
const TRANSITION_SETTLE_DURATION := 0.5
const TRANSITION_RISE_OFFSET := -2.6

@onready var tower_root: Node3D = $CubeTower
@onready var floor_mesh: MeshInstance3D = $Lab/FloorBody/FloorMesh
@onready var rig: XrRig = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $XROrigin3D/LeftController
@onready var right_controller: XRController3D = $XROrigin3D/RightController
@onready var tower_light: OmniLight3D = $TowerLight

enum BallMode { REST, HELD, FLYING }
enum Powerup { NONE, HEAVY, ICE, FIRE }

class BallState:
	var body: RigidBody3D
	var visual: MeshInstance3D
	var mat: StandardMaterial3D
	var base_color: Color
	var base_emission: Color
	var mode := BallMode.REST
	var held_hand = null
	var slow_time := 0.0
	var sound_at := -100000
	var trail: GPUParticles3D
	var aura: GPUParticles3D


var sfx := SoundKitScript.new()
var left_ball_state := BallState.new()
var right_ball_state := BallState.new()

# Backward-compatible aliases for code/tests that still treat the right ball as
# the primary ball.
var ball: RigidBody3D:
	get: return right_ball_state.body
var ball_visual: MeshInstance3D:
	get: return right_ball_state.visual
var ball_mat: StandardMaterial3D:
	get: return right_ball_state.mat
var ball_mode:
	get: return right_ball_state.mode
	set(value): right_ball_state.mode = value
var ball_held_hand:
	get: return right_ball_state.held_hand
	set(value): right_ball_state.held_hand = value

var cubes: Array[RigidBody3D] = []
var _cube_shape: BoxShape3D
var _cube_mesh: BoxMesh
var _cube_phys: PhysicsMaterial
var _row_mats: Array[StandardMaterial3D] = []
var score := 0
var _score_label: Label3D
var _hint: Label3D
var _hint_time := 0.0
var _version: Label3D
var _sound_players: Array[AudioStreamPlayer3D] = []
var _sound_next := 0
var _bgm_calm: AudioStreamPlayer
var _bgm_intense: AudioStreamPlayer
const BGM_CALM_DB := -6.0
const BGM_INTENSE_DB := -6.0
const BGM_MUTE_DB := -80.0
var _menu_was := false
var _ax_was := false
var _grip_was := {}
var _hand_prev := {}
var _hand_vel := {}
var _hit_sound_at := {}
var _cube_sound_until := 0
var _base_ball_mass := BALL_BASE_MASS
var active_powerup := Powerup.NONE
var _pending_powerup := Powerup.NONE
var powerup_chance := POWERUP_CHANCE
var _powerup_time := 0.0
var _powerup_used := false
var _powerup_state: BallState = null
var _explosion_center := Vector3.ZERO
var _explosion_ball_state: BallState = null
var _last_throw_hand = null
var current_round := 1
var total_score := 0
var _congrats_label: Label3D
var _restart_box: RigidBody3D
var _restart_label: Label3D
var _rounds_complete := false
var _smoke_texture: ImageTexture = null

enum TransitionPhase { SINKING, RISING, SETTLING }
var _transition_active := false
var _transition_time := 0.0
var _transition_phase := TransitionPhase.SINKING
var _transition_old_cubes: Array[RigidBody3D] = []
var _transition_rise_start := 0.0
var _transition_settle_start := 0.0


func _init() -> void:
	AppLog.install()


func _ready() -> void:
	var openxr := XRServer.find_interface("OpenXR")
	if openxr != null and openxr.is_initialized():
		get_viewport().use_xr = true
	print("Portal Smash ", BuildVersion.TEXT)
	print("log file: ", AppLog.global_path())

	sfx.build()
	_apply_floor_texture()
	_apply_ceiling_texture()
	_prepare_shared_cubes()
	_spawn_tower()
	_build_balls()
	_build_wall_details()
	_build_labels()
	_build_sound_pool()
	_build_music()
	_build_hand_models()
	print("lab ready: %d cubes stacked" % cubes.size())
	_show_hint("Hold GRIP on either hand to catch that hand's ball.\nSwing and release to throw it at the tower!", 9.0)


func _apply_floor_texture() -> void:
	var mat := floor_mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	var tex := _make_floor_texture()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.uv1_scale = Vector3(4, 4, 1)
	mat.metallic = 0.0
	mat.roughness = 0.35


func _apply_ceiling_texture() -> void:
	var ceiling_mesh: MeshInstance3D = $Lab/CeilingBody/CeilingMesh
	var mat := ceiling_mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	var tex := load("res://assets/ceiling.jpg") as Texture2D
	if tex == null:
		return
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.uv1_scale = Vector3(4, 4, 1)
	mat.metallic = 0.0
	mat.roughness = 0.95


func _make_floor_texture() -> ImageTexture:
	var s := 512
	var tiles := 2
	var tile := s / tiles
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var base := Color(0.97, 0.95, 0.91)
	for ty in tiles:
		for tx in tiles:
			var ox := tx * tile
			var oy := ty * tile
			var tbase := base.lightened(randf() * 0.02)
			for y in tile:
				for x in tile:
					var px := float(x) / float(tile)
					var py := float(y) / float(tile)
					var v := sin(px * 14.0 + sin(py * 10.0) * 2.5) * 0.5 + 0.5
					v += sin(py * 16.0 + cos(px * 7.0) * 2.0) * 0.35
					v += sin((px + py) * 9.0) * 0.15
					v /= 1.5
					var c := tbase
					if v > 0.65:
						c = c.darkened(0.45 + (v - 0.65) * 0.8)
					elif v < 0.30:
						c = c.lightened(0.04)
					img.set_pixel(ox + x, oy + y, c)
	var grout := Color(0.40, 0.38, 0.35)
	for t in range(1, tiles):
		var gy := t * tile
		for x in s:
			for dy in range(-1, 2):
				img.set_pixel(x, gy + dy, grout)
		var gx := t * tile
		for y in s:
			for dx in range(-1, 2):
				img.set_pixel(gx + dx, y, grout)
	return ImageTexture.create_from_image(img)


func row_color(row: int) -> Color:
	return Color.from_hsv(fmod(float(row) * 0.135, 1.0), 0.60, 0.92)


static func cube_row(index: int) -> int:
	for r in TOWER_ROWS:
		if index < row_start(r + 1):
			return r
	return TOWER_ROWS - 1


static func row_start(row: int) -> int:
	return row * TOWER_ROWS - row * (row - 1) / 2


static func tower_local(index: int) -> Vector3:
	var row := cube_row(index)
	var count := TOWER_ROWS - row
	var col := index - row_start(row)
	var x := (float(col) - float(count - 1) * 0.5) * CUBE_PITCH
	var y := (float(row) + 0.5) * CUBE_PITCH
	return Vector3(x, y, 0.0)


func _crate_texture(pattern: int) -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.65, 0.65, 0.65, 1.0))
	for i in 400:
		var x := randi() % s
		var y := randi() % s
		var c := img.get_pixel(x, y)
		if randf() > 0.5:
			c = c.lightened(randf() * 0.08)
		else:
			c = c.darkened(randf() * 0.08)
		img.set_pixel(x, y, c)
	match pattern % 4:
		0:
			for y in range(0, s, 8):
				if (y / 8) % 2 == 0:
					for x in s:
						img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.18))
		1:
			for x in range(0, s, 16):
				for y in s:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.30))
			for y in range(0, s, 16):
				for x in s:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.30))
		2:
			for y in range(0, s, 8):
				for x in range(0, s, 8):
					if ((x / 8) + (y / 8)) % 2 == 0:
						img.fill_rect(Rect2i(x, y, 8, 8), img.get_pixel(x, y).darkened(0.20))
		3:
			for x in range(24, 40):
				for y in s:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.25))
			for y in range(24, 40):
				for x in s:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.25))
	return ImageTexture.create_from_image(img)


func _prepare_shared_cubes() -> void:
	_cube_shape = BoxShape3D.new()
	_cube_shape.size = Vector3(CUBE_EDGE, CUBE_EDGE, CUBE_EDGE)
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3(CUBE_EDGE, CUBE_EDGE, CUBE_EDGE)
	_cube_phys = PhysicsMaterial.new()
	_cube_phys.friction = 0.7
	_cube_phys.bounce = 0.0
	for r in TOWER_ROWS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = row_color(r)
		mat.albedo_texture = _crate_texture(r)
		mat.roughness = 0.75
		_row_mats.append(mat)


func _spawn_tower(design_index: int = 1, animate_rise: bool = false) -> void:
	for c in cubes:
		if is_instance_valid(c):
			c.queue_free()
	cubes.clear()
	score = 0
	var positions := _design_positions(design_index)
	for i in positions.size():
		var body := RigidBody3D.new()
		body.name = "Cube%03d" % i
		body.mass = CUBE_MASS
		var home_pos := TOWER_CENTER + positions[i]
		body.position = home_pos
		if animate_rise:
			body.position.y += TRANSITION_RISE_OFFSET
			body.freeze = true
			body.collision_layer = 0
			body.collision_mask = 0
			body.set_meta("rise_home", home_pos)
			body.set_meta("rise_start", body.position)
		else:
			body.freeze = true
		body.linear_damp = 0.4
		body.angular_damp = 3.0
		body.physics_material_override = _cube_phys
		body.contact_monitor = true
		body.max_contacts_reported = 2
		body.body_entered.connect(_on_cube_hit.bind(body))
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = _cube_mesh
		mesh.material_override = _row_mats[_design_row(positions[i], i)]
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		shape.shape = _cube_shape
		body.add_child(shape)
		body.set_meta("knocked", false)
		body.set_meta("home", home_pos)
		tower_root.add_child(body)
		cubes.append(body)
	_cube_sound_until = Time.get_ticks_msec() + 700
	if animate_rise:
		_transition_rise_start = _transition_time
	else:
		get_tree().create_timer(0.05).timeout.connect(_unfreeze_cubes)
	_update_score_label()


func _design_row(pos: Vector3, index: int) -> int:
	# Map a design position to a row color index based on height.
	var row := int(pos.y / CUBE_PITCH)
	return clampi(row, 0, TOWER_ROWS - 1)


func _design_positions(index: int) -> Array[Vector3]:
	match ((index - 1) % 10) + 1:
		1: return _design_pyramid()
		2: return _design_wall()
		3: return _design_brick_wall()
		4: return _design_ziggurat()
		5: return _design_a_frame()
		6: return _design_square_pyramid()
		7: return _design_cylinder()
		8: return _design_cross()
		9: return _design_spiral()
		10: return _design_castle()
	return _design_pyramid()


func _design_pyramid() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for i in CUBE_COUNT:
		positions.append(tower_local(i))
	return positions


func _design_wall() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var rows := 10
	var cols := 15
	for r in rows:
		for c in cols:
			var x := (float(c) - float(cols - 1) * 0.5) * CUBE_PITCH
			var y := (float(r) + 0.5) * CUBE_PITCH
			positions.append(Vector3(x, y, 0.0))
	return positions


func _design_brick_wall() -> Array[Vector3]:
	# Offset rows like bricks so every cube has support below.
	var positions: Array[Vector3] = []
	var rows := 10
	var cols := 15
	for r in rows:
		var offset := 0.0 if r % 2 == 0 else CUBE_PITCH * 0.5
		var y := (float(r) + 0.5) * CUBE_PITCH
		for c in cols:
			var x := (float(c) - float(cols - 1) * 0.5) * CUBE_PITCH + offset
			positions.append(Vector3(x, y, 0.0))
	return positions


func _design_ziggurat() -> Array[Vector3]:
	# Solid stepped pyramid: each level is fully supported by the one below.
	var positions: Array[Vector3] = []
	var levels := 6
	for l in levels:
		var size := levels - l
		var y := (float(l) + 0.5) * CUBE_PITCH
		for cx in size:
			for cz in size:
				var x := (float(cx) - float(size - 1) * 0.5) * CUBE_PITCH
				var z := (float(cz) - float(size - 1) * 0.5) * CUBE_PITCH
				positions.append(Vector3(x, y, z))
	return positions


func _design_a_frame() -> Array[Vector3]:
	# Solid triangular prism wall - self-supporting and stable.
	var positions: Array[Vector3] = []
	var width := 11
	var depth := 3
	for h in 6:
		var count := width - h * 2
		if count < 1:
			break
		var y := (float(h) + 0.5) * CUBE_PITCH
		for x in count:
			for z in depth:
				var px := (float(x) - float(count - 1) * 0.5) * CUBE_PITCH
				var pz := (float(z) - float(depth - 1) * 0.5) * CUBE_PITCH
				positions.append(Vector3(px, y, pz))
	return positions


func _design_square_pyramid() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var layers := 6
	for r in layers:
		var count := layers - r
		for cx in count:
			for cz in count:
				var x := (float(cx) - float(count - 1) * 0.5) * CUBE_PITCH
				var z := (float(cz) - float(count - 1) * 0.5) * CUBE_PITCH
				var y := (float(r) + 0.5) * CUBE_PITCH
				positions.append(Vector3(x, y, z))
	return positions


func _design_cylinder() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var layers := 7
	var radius := 2.0
	for r in layers:
		var y := (float(r) + 0.5) * CUBE_PITCH
		var circumference := int(2.0 * PI * radius / CUBE_PITCH)
		for i in circumference:
			var angle := float(i) / float(circumference) * TAU
			var x := cos(angle) * radius
			var z := sin(angle) * radius
			positions.append(Vector3(x, y, z))
	return positions


func _design_cross() -> Array[Vector3]:
	# Thick intersecting walls (3 cubes wide) - much more stable than thin blades.
	var positions: Array[Vector3] = []
	var rows := 5
	var arm := 5
	var thickness := 3
	var used := {}
	for r in rows:
		var y := (float(r) + 0.5) * CUBE_PITCH
		for c in arm:
			for t in thickness:
				var x := (float(c) - float(arm - 1) * 0.5) * CUBE_PITCH
				var z := (float(t) - float(thickness - 1) * 0.5) * CUBE_PITCH
				var p1 := Vector3(x, y, z)
				var p2 := Vector3(z, y, x)
				if not used.has(p1):
					used[p1] = true
					positions.append(p1)
				if not used.has(p2):
					used[p2] = true
					positions.append(p2)
	return positions


func _design_spiral() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var layers := 7
	var radius := 2.0
	for r in layers:
		var y := (float(r) + 0.5) * CUBE_PITCH
		var count := maxi(4, int(2.0 * PI * radius / CUBE_PITCH))
		for i in count:
			var angle := float(i) / float(count) * TAU + float(r) * 0.5
			var x := cos(angle) * radius
			var z := sin(angle) * radius
			positions.append(Vector3(x, y, z))
	return positions


func _design_castle() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	# Four corner turrets.
	var offset := 1.8
	for corner in 4:
		var cx := 1.0 if corner % 2 == 0 else -1.0
		var cz := 1.0 if corner < 2 else -1.0
		for h in 4:
			for tx in 3:
				for tz in 3:
					var x := (cx * offset) + (float(tx) - 1.0) * CUBE_PITCH
					var z := (cz * offset) + (float(tz) - 1.0) * CUBE_PITCH
					var y := (float(h) + 0.5) * CUBE_PITCH
					positions.append(Vector3(x, y, z))
	# Connecting walls.
	for h in 3:
		for t in 5:
			var y := (float(h) + 0.5) * CUBE_PITCH
			var x := (float(t) - 2.0) * CUBE_PITCH
			positions.append(Vector3(x, y, offset))
			positions.append(Vector3(x, y, -offset))
			positions.append(Vector3(offset, y, x))
			positions.append(Vector3(-offset, y, x))
	return positions


func _unfreeze_cubes() -> void:
	for c in cubes:
		if not is_instance_valid(c):
			continue
		c.freeze = false
		c.scale = Vector3.ONE
		c.collision_layer = 1
		c.collision_mask = 1
		c.position = c.get_meta("home")
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		c.sleeping = true


func _build_balls() -> void:
	if _smoke_texture == null:
		_smoke_texture = _make_smoke_texture()
	_build_ball_state(left_ball_state, Color(0.15, 0.75, 1.0), Color(0.08, 0.45, 0.7))
	_build_ball_state(right_ball_state, Color(1.0, 0.5, 0.12), Color(1.0, 0.35, 0.08))
	left_ball_state.body.name = "LeftBall"
	right_ball_state.body.name = "RightBall"
	add_child(left_ball_state.body)
	add_child(right_ball_state.body)
	_build_ball_trail(left_ball_state)
	_build_ball_trail(right_ball_state)
	_build_ball_aura(left_ball_state)
	_build_ball_aura(right_ball_state)
	left_ball_state.body.global_position = _ball_rest_point(left_controller)
	right_ball_state.body.global_position = _ball_rest_point(right_controller)


func _build_ball_state(state: BallState, color: Color, emission: Color) -> void:
	state.body = RigidBody3D.new()
	state.body.mass = _base_ball_mass
	state.body.continuous_cd = true
	state.body.contact_monitor = true
	state.body.max_contacts_reported = 2
	state.body.body_entered.connect(_on_ball_hit.bind(state))
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.2
	state.body.physics_material_override = pm
	state.visual = MeshInstance3D.new()
	state.visual.name = "Mesh"
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	state.visual.mesh = sphere
	state.mat = StandardMaterial3D.new()
	state.mat.albedo_color = color
	state.mat.emission_enabled = true
	state.mat.emission = emission
	state.mat.emission_energy_multiplier = 0.6
	state.mat.roughness = 0.35
	state.visual.material_override = state.mat
	state.body.add_child(state.visual)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = BALL_RADIUS
	state.body.add_child(shape)
	state.body.freeze = true
	state.base_color = color
	state.base_emission = emission


func _build_labels() -> void:
	_score_label = Label3D.new()
	_score_label.name = "ScoreLabel"
	_score_label.position = Vector3(0, 7.5, -1.0)
	_score_label.font_size = 56
	_score_label.pixel_size = 0.001
	_score_label.modulate = Color("8fe0d0")
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_score_label)
	_update_score_label()

	_version = Label3D.new()
	_version.name = "VersionLabel"
	_version.text = BuildVersion.TEXT
	_version.position = Vector3(0, -0.55, -0.8)
	_version.font_size = 16
	_version.pixel_size = 0.001
	_version.modulate = Color(0.45, 0.5, 0.55, 0.6)
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version.no_depth_test = true
	camera.add_child(_version)


func _build_sound_pool() -> void:
	for i in SOUND_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "Sound%d" % i
		player.unit_size = 6.0
		player.volume_db = -4.0
		add_child(player)
		_sound_players.append(player)


func _build_music() -> void:
	_bgm_calm = AudioStreamPlayer.new()
	_bgm_calm.name = "BgmCalm"
	_bgm_calm.stream = sfx.bgm_calm
	_bgm_calm.volume_db = BGM_CALM_DB
	add_child(_bgm_calm)
	_bgm_calm.play()

	_bgm_intense = AudioStreamPlayer.new()
	_bgm_intense.name = "BgmIntense"
	_bgm_intense.stream = sfx.bgm_intense
	_bgm_intense.volume_db = BGM_MUTE_DB
	add_child(_bgm_intense)
	_bgm_intense.play()


func _build_hand_models() -> void:
	_build_hand_for(left_controller, Color(0.15, 0.75, 1.0))
	_build_hand_for(right_controller, Color(1.0, 0.5, 0.12))


func _build_hand_for(controller: XRController3D, color: Color) -> void:
	var hand := Node3D.new()
	hand.name = "HandModel"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	mat.metallic = 0.2

	var palm := MeshInstance3D.new()
	palm.name = "Palm"
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.1, 0.09, 0.04)
	palm.mesh = palm_mesh
	palm.material_override = mat
	palm.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.02))
	hand.add_child(palm)

	for i in 3:
		var finger := MeshInstance3D.new()
		finger.name = "Finger%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.011
		cyl.height = 0.075
		finger.mesh = cyl
		finger.material_override = mat
		var x := (float(i) - 1.0) * 0.028
		var basis := Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		finger.transform = Transform3D(basis, Vector3(x, 0.02, -0.07))
		hand.add_child(finger)

	var thumb := MeshInstance3D.new()
	thumb.name = "Thumb"
	var thumb_cyl := CylinderMesh.new()
	thumb_cyl.top_radius = 0.014
	thumb_cyl.bottom_radius = 0.013
	thumb_cyl.height = 0.055
	thumb.mesh = thumb_cyl
	thumb.material_override = mat
	var thumb_basis := Basis(Vector3.RIGHT, deg_to_rad(-60.0)) * Basis(Vector3.UP, deg_to_rad(30.0))
	thumb.transform = Transform3D(thumb_basis, Vector3(0.055, -0.01, -0.04))
	hand.add_child(thumb)

	controller.add_child(hand)


func _spawn_debris(at: Vector3, color: Color, strength: float) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "Debris"
	particles.one_shot = true
	particles.emitting = true
	particles.amount = clampi(int(strength * 14.0), 4, 18)
	particles.lifetime = 0.5
	particles.explosiveness = 0.7
	particles.direction = Vector3.UP
	particles.spread = 90.0
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 2.8
	particles.gravity = Vector3(0.0, -7.0, 0.0)

	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	box.material = mat
	particles.mesh = box

	add_child(particles)
	particles.global_position = at
	get_tree().create_timer(particles.lifetime + 0.2).timeout.connect(particles.queue_free)


func _spawn_impact_flash(at: Vector3, color: Color, strength: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = lerpf(1.4, 3.2, strength)
	light.omni_range = lerpf(0.7, 1.5, strength)
	add_child(light)
	light.global_position = at
	var fade := create_tween()
	fade.tween_property(light, "light_energy", 0.0, lerpf(0.12, 0.24, strength))
	fade.tween_callback(light.queue_free)


func _build_wall_details() -> void:
	_apply_wall_texture()
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.72, 0.74, 0.78)
	trim_mat.metallic = 0.55
	trim_mat.roughness = 0.35
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.20, 0.21, 0.23)
	pillar_mat.metallic = 0.25
	pillar_mat.roughness = 0.65
	for body: Node3D in [$Lab/WallBack, $Lab/WallFront, $Lab/WallLeft, $Lab/WallRight]:
		if not is_instance_valid(body):
			continue
		var shape := body.get_node("WallShape").shape as BoxShape3D
		if shape == null:
			continue
		var size := shape.size
		var basis := body.global_transform.basis
		var long_dir: Vector3
		var long_len: float
		var thick: float
		var normal: Vector3
		if size.x >= size.z:
			long_dir = basis.x
			long_len = size.x
			thick = size.z
			normal = basis.z
		else:
			long_dir = basis.z
			long_len = size.z
			thick = size.x
			normal = basis.x
		var center := body.global_position
		var base_h := 0.25
		var base_d := 0.08
		var base_pos := center + normal * (thick * 0.5 + base_d * 0.5) + Vector3(0.0, -size.y * 0.5 + base_h * 0.5, 0.0)
		_add_trim_box($Lab, body.name + "Baseboard", base_pos, long_dir, normal, Vector3(long_len, base_h, base_d), trim_mat)
		var band_h := 0.18
		var band_d := 0.06
		var band_pos := center + normal * (thick * 0.5 + band_d * 0.5)
		_add_trim_box($Lab, body.name + "Band", band_pos, long_dir, normal, Vector3(long_len, band_h, band_d), trim_mat)
		var pillar_w := 0.18
		var pillar_d := 0.08
		var spacing := 3.5
		var count := maxi(2, int(long_len / spacing) + 1)
		for i in count:
			var t := 0.0 if count == 1 else float(i) / float(count - 1)
			var offset := (t - 0.5) * long_len
			var p_pos := center + long_dir * offset + normal * (thick * 0.5 + pillar_d * 0.5)
			_add_trim_box($Lab, body.name + "Pillar%d" % i, p_pos, long_dir, normal, Vector3(pillar_w, size.y, pillar_d), pillar_mat)


func _add_trim_box(parent: Node3D, node_name: String, pos: Vector3, long_dir: Vector3, normal: Vector3, dims: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = dims
	mesh.mesh = box
	mesh.material_override = mat
	var b := Basis(long_dir, Vector3.UP, normal)
	if b.determinant() < 0.0:
		b.y = -b.y
	mesh.transform = Transform3D(b, pos)
	parent.add_child(mesh)


func _apply_wall_texture() -> void:
	var wall_mesh: MeshInstance3D = $Lab/WallBack/WallMesh
	var wall_mat: StandardMaterial3D = wall_mesh.get_surface_override_material(0) as StandardMaterial3D
	if wall_mat == null:
		return
	var tex := load("res://assets/wall_gray.jpg") as Texture2D
	if tex == null:
		return
	wall_mat.albedo_texture = tex
	wall_mat.albedo_color = Color(1.0, 1.0, 1.0)
	wall_mat.uv1_scale = Vector3(3, 2, 1)
	wall_mat.metallic = 0.0
	wall_mat.roughness = 0.9


func _build_ball_trail(state: BallState) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Trail"
	particles.amount = 40
	particles.lifetime = 0.15
	particles.fixed_fps = 60
	particles.local_coords = false
	particles.emitting = false
	particles.transform = Transform3D.IDENTITY
	particles.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.015
	pm.direction = Vector3(0.0, 0.04, 0.0)
	pm.spread = 90.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.06
	pm.gravity = Vector3(0.0, 0.03, 0.0)
	pm.damping_min = 1.5
	pm.damping_max = 3.5
	pm.scale_min = 0.03
	pm.scale_max = 0.09
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0), 0.0, 0.0)
	scale_curve.add_point(Vector2(1.0, 0.2), 0.0, 0.0)
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	pm.scale_curve = scale_texture
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 1.0, 0.11))
	grad.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	pm.color = Color(state.mat.albedo_color.r, state.mat.albedo_color.g, state.mat.albedo_color.b, 0.2)
	particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var qmat := StandardMaterial3D.new()
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.vertex_color_use_as_albedo = true
	qmat.albedo_texture = _smoke_texture
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qmat
	particles.draw_pass_1 = quad
	state.body.add_child(particles)
	state.trail = particles


func _build_ball_aura(state: BallState) -> void:
	var aura := GPUParticles3D.new()
	aura.name = "ChargeAura"
	aura.amount = 128
	aura.lifetime = 0.6
	aura.preprocess = 0.3
	aura.emitting = false
	aura.randomness = 0.5
	aura.local_coords = false
	aura.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))

	var particle_mat := ParticleProcessMaterial.new()
	particle_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_mat.emission_sphere_radius = BALL_RADIUS * 1.1
	particle_mat.direction = Vector3.UP
	particle_mat.spread = 180.0
	particle_mat.initial_velocity_min = 0.04
	particle_mat.initial_velocity_max = 0.18
	particle_mat.gravity = Vector3.ZERO
	particle_mat.scale_min = 0.008
	particle_mat.scale_max = 0.018

	var scale_ramp := GradientTexture1D.new()
	var scale_grad := Gradient.new()
	scale_grad.offsets = PackedFloat32Array([0.0, 1.0])
	scale_grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	scale_ramp.gradient = scale_grad
	particle_mat.scale_curve = scale_ramp

	var color := state.mat.albedo_color
	var color_ramp := GradientTexture1D.new()
	var color_grad := Gradient.new()
	color_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	color_grad.colors = PackedColorArray([
		_color_tint(color, 1.3),
		_color_tint(color, 0.85),
		Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0.0),
	])
	color_ramp.gradient = color_grad
	particle_mat.color_ramp = color_ramp
	aura.process_material = particle_mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.albedo_texture = _create_particle_texture()
	quad.material = draw_mat
	aura.draw_pass_1 = quad

	state.body.add_child(aura)
	state.aura = aura


func _color_tint(color: Color, factor: float) -> Color:
	var tinted := color * factor
	tinted.a = 1.0
	return tinted.clamp()


func _create_particle_texture() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dx := (x - center) / center
			var dy := (y - center) / center
			var dist := sqrt(dx * dx + dy * dy)
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = alpha * alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


func _make_smoke_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var cx := float(s) * 0.5
	var cy := float(s) * 0.5
	var radius := float(s) * 0.5
	for y in s:
		for x in s:
			var d := sqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy)) / radius
			if d < 1.0:
				var a := pow(1.0 - d, 1.8)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _show_hint(text: String, seconds: float) -> void:
	if _hint == null:
		_hint = Label3D.new()
		_hint.name = "Hint"
		_hint.position = Vector3(0, -0.42, -0.8)
		_hint.font_size = 22
		_hint.pixel_size = 0.001
		_hint.modulate = Color(0.55, 0.6, 0.68, 0.9)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.no_depth_test = true
		camera.add_child(_hint)
	_hint.text = text
	_hint.visible = true
	_hint_time = seconds


func _powerup_name(kind: int) -> String:
	match kind:
		Powerup.HEAVY:
			return "HEAVY"
		Powerup.ICE:
			return "ICE"
		Powerup.FIRE:
			return "FIRE"
	return ""


func _update_score_label() -> void:
	if _score_label == null:
		return
	var tag := ""
	if _pending_powerup != Powerup.NONE:
		tag = "  NEXT: %s" % _powerup_name(_pending_powerup)
	elif active_powerup != Powerup.NONE:
		tag = "  [%s]" % _powerup_name(active_powerup)
	var round_text := "ROUND %d/%d" % [current_round, ROUND_COUNT]
	var smashed_text := "SMASHED %d/%d" % [score, cubes.size()]
	var total_text := "TOTAL %d" % (total_score + score)
	_score_label.text = "%s  %s  %s%s" % [round_text, smashed_text, total_text, tag]


func _ball_state_for_hand(hand) -> BallState:
	if hand == left_controller:
		return left_ball_state
	return right_ball_state


func _ball_rest_point(hand = right_controller) -> Vector3:
	if hand == left_controller:
		return rig.global_position + BALL_REST_OFFSET_LEFT
	return rig.global_position + BALL_REST_OFFSET_RIGHT


func _ball_rest_point_for_state(state: BallState) -> Vector3:
	if state == left_ball_state:
		return _ball_rest_point(left_controller)
	return _ball_rest_point(right_controller)


func _any_ball_at_rest() -> bool:
	return left_ball_state.mode == BallMode.REST or right_ball_state.mode == BallMode.REST


func _hand_hold_point(hand) -> Vector3:
	return hand.global_transform * BALL_FOLLOW_OFFSET


func _physics_process(delta: float) -> void:
	_process_events(delta)
	_update_knocks()
	_update_ball_physics(delta)
	_update_buttons()


func _process_events(delta: float) -> void:
	if _hint_time > 0.0:
		_hint_time -= delta
		if _hint_time <= 0.0 and _hint != null:
			_hint.visible = false


func _update_knocks() -> void:
	if _transition_active:
		return
	for c in cubes:
		if not is_instance_valid(c) or c.get_meta("knocked", false):
			continue
		if c.global_position.distance_to(c.get_meta("home")) > KNOCK_DIST:
			c.set_meta("knocked", true)
			score += 1
			var hand = _last_throw_hand
			if hand == null or not is_instance_valid(hand):
				hand = right_controller
			var speed := c.linear_velocity.length()
			var haptic_strength := clampf(speed / 6.0, 0.2, 1.0)
			rig.pulse_haptic(hand, lerpf(0.35, 0.95, haptic_strength), lerpf(0.04, 0.13, haptic_strength))
	_update_score_label()
	_check_round_progress()


func _check_round_progress() -> void:
	if _transition_active or _rounds_complete or cubes.is_empty():
		return
	var progress := float(score) / float(cubes.size())
	if progress < ROUND_ADVANCE_THRESHOLD:
		return
	if current_round < ROUND_COUNT:
		_start_round_transition()
	else:
		_complete_rounds()


func _start_round_transition() -> void:
	if _transition_active:
		return
	_transition_active = true
	_transition_time = 0.0
	_transition_phase = TransitionPhase.SINKING
	total_score += score
	current_round += 1
	_pending_powerup = Powerup.NONE
	_clear_powerup()
	_respawn_ball(left_ball_state, false)
	_respawn_ball(right_ball_state, false)

	_transition_old_cubes = cubes.duplicate()
	cubes.clear()
	for c in _transition_old_cubes:
		if not is_instance_valid(c):
			continue
		c.freeze = true
		c.collision_layer = 0
		c.collision_mask = 0

	_show_hint("ROUND CLEAR!", 1.5)
	_play_sound("chime", TOWER_CENTER, 1.0)
	if tower_light != null:
		tower_light.light_energy = 2.2
	_spawn_tower(current_round, true)
	_update_score_label()


func _complete_rounds() -> void:
	_rounds_complete = true
	total_score += score
	_update_score_label()
	_show_congrats()
	_build_restart_box()
	_play_sound("chime", TOWER_CENTER, 1.0)


func _reset_rounds() -> void:
	_rounds_complete = false
	current_round = 1
	total_score = 0
	_pending_powerup = Powerup.NONE
	_clear_powerup()
	_hide_congrats()
	_destroy_restart_box()
	_respawn_ball(left_ball_state, false)
	_respawn_ball(right_ball_state, false)
	_spawn_tower(1)
	_show_hint("Rounds reset! SMASH again!", 2.5)
	_play_sound("chime", _ball_rest_point(), 1.0)
	_update_score_label()


func _update_ball_physics(delta: float) -> void:
	for state: BallState in [left_ball_state, right_ball_state]:
		if state.mode != BallMode.FLYING:
			continue
		if state.body.linear_velocity.length() < SETTLE_SPEED:
			state.slow_time += delta
			if state.slow_time > SETTLE_TIME:
				_respawn_ball(state, true)
				continue
		else:
			state.slow_time = 0.0
		var p := state.body.global_position
		if p.y < -0.5 or p.y > 10.0 or absf(p.x) > 5.8 or absf(p.z) > 5.8:
			_respawn_ball(state, true)


func _respawn_ball(state: BallState, chime: bool) -> void:
	state.mode = BallMode.REST
	if state.aura != null:
		state.aura.emitting = false
	state.body.freeze = true
	state.body.linear_velocity = Vector3.ZERO
	state.body.angular_velocity = Vector3.ZERO
	state.body.global_position = _ball_rest_point_for_state(state)
	state.body.rotation = Vector3.ZERO
	state.slow_time = 0.0
	if active_powerup == Powerup.NONE and _pending_powerup != Powerup.NONE:
		_apply_pending_powerup(state)
	if chime:
		_play_sound("chime", state.body.global_position, 1.0)
		_show_hint("New ball!", 1.6)
		var hand := left_controller if state == left_ball_state else right_controller
		rig.pulse_haptic(hand, 0.5, 0.12)


func _update_buttons() -> void:
	var menu := left_controller.is_button_pressed("menu_button") or right_controller.is_button_pressed("menu_button")
	if menu and not _menu_was:
		_reset_tower()
	_menu_was = menu

	var ax := right_controller.is_button_pressed("ax_button")
	if ax and not _ax_was:
		_reset_tower()
	_ax_was = ax

	_handle_grip(left_controller)
	_handle_grip(right_controller)


func _handle_grip(hand) -> void:
	var state := _ball_state_for_hand(hand)
	var pressed: bool = hand.is_button_pressed("grip_click")
	var was: bool = _grip_was.get(hand, false)
	if pressed and not was and state.mode == BallMode.REST:
		var target := _hand_hold_point(hand)
		if state.body.global_position.distance_to(target) <= GRAB_RADIUS:
			state.mode = BallMode.HELD
			state.held_hand = hand
			rig.pulse_haptic(hand, 0.15, 0.045)
			if state.aura != null:
				state.aura.emitting = true
	elif not pressed and was and state.mode == BallMode.HELD and state.held_hand == hand:
		if state.aura != null:
			state.aura.emitting = false
		var vel: Vector3 = _hand_velocity(hand)
		if vel.length() >= THROW_MIN_SPEED:
			state.mode = BallMode.FLYING
			state.body.freeze = false
			state.body.linear_velocity = vel * THROW_SPEED_SCALE
			state.body.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
			state.held_hand = null
			_last_throw_hand = hand
			var throw_strength := clampf(vel.length() / 8.0, 0.2, 1.0)
			_play_sound("whoosh", state.body.global_position, throw_strength)
			rig.pulse_haptic(hand, lerpf(0.35, 0.8, throw_strength), lerpf(0.05, 0.12, throw_strength))
		else:
			state.mode = BallMode.REST
			state.held_hand = null
			state.body.linear_velocity = Vector3.ZERO
	_grip_was[hand] = pressed


func _hand_velocity(hand) -> Vector3:
	if not _hand_vel.has(hand):
		return Vector3.ZERO
	return _hand_vel[hand]


func _hand_track(delta: float) -> void:
	for hand in [left_controller, right_controller]:
		var now: Vector3 = hand.global_position
		if _hand_prev.has(hand):
			var dt := maxf(delta, 0.001)
			var raw: Vector3 = (now - _hand_prev[hand]) / dt
			var prev: Vector3 = _hand_vel.get(hand, Vector3.ZERO)
			_hand_vel[hand] = prev.lerp(raw, 0.45) if delta > 0.0 else raw
		_hand_prev[hand] = now


func _update_transition(delta: float) -> void:
	_transition_time += delta

	# Fade the flash light back to off.
	if tower_light != null and tower_light.light_energy > 0.0:
		tower_light.light_energy = maxf(0.0, tower_light.light_energy - delta * 3.0)

	if _transition_phase == TransitionPhase.SINKING:
		if _transition_old_cubes.size() > 0:
			var sink_t := clampf(_transition_time / TRANSITION_OLD_SINK_DURATION, 0.0, 1.0)
			for c in _transition_old_cubes:
				if not is_instance_valid(c):
					continue
				var home: Vector3 = c.get_meta("home")
				c.position = home.lerp(home + Vector3(0, -2.4, 0), sink_t)
				var s := maxf(0.01, 1.0 - sink_t)
				c.scale = Vector3(s, s, s)
			if sink_t >= 1.0:
				for c in _transition_old_cubes:
					if is_instance_valid(c):
						c.queue_free()
				_transition_old_cubes.clear()
				_transition_phase = TransitionPhase.RISING
		else:
			_transition_phase = TransitionPhase.RISING

	elif _transition_phase == TransitionPhase.RISING:
		var rise_t := (_transition_time - _transition_rise_start - TRANSITION_RISE_DELAY) / TRANSITION_RISE_DURATION
		if rise_t < 0.0:
			return
		if rise_t < 1.0:
			var eased := ease(rise_t, -2.0)
			for c in cubes:
				if not is_instance_valid(c):
					continue
				var start: Vector3 = c.get_meta("rise_start")
				var home: Vector3 = c.get_meta("rise_home")
				c.position = start.lerp(home, eased)
		else:
			for c in cubes:
				if not is_instance_valid(c):
					continue
				c.position = c.get_meta("rise_home")
			_transition_settle_start = _transition_time
			_transition_phase = TransitionPhase.SETTLING

	elif _transition_phase == TransitionPhase.SETTLING:
		if _transition_time - _transition_settle_start >= TRANSITION_SETTLE_DURATION:
			_unfreeze_cubes()
			_transition_active = false
			_transition_phase = TransitionPhase.SINKING
			_show_hint("ROUND %d/%d" % [current_round, ROUND_COUNT], 2.5)
			_play_sound("chime", TOWER_CENTER, 1.0)
			_update_score_label()


func _process(delta: float) -> void:
	if _transition_active:
		_update_transition(delta)
	_hand_track(delta)
	if active_powerup != Powerup.NONE:
		_powerup_time -= delta
		if _powerup_time <= 0.0:
			_clear_powerup()
		if _pending_powerup != Powerup.NONE and _any_ball_at_rest():
			_apply_pending_powerup()
	if _bgm_calm != null and _bgm_intense != null:
		var target_intense := BGM_INTENSE_DB if active_powerup != Powerup.NONE else BGM_MUTE_DB
		var target_calm := BGM_MUTE_DB if active_powerup != Powerup.NONE else BGM_CALM_DB
		_bgm_intense.volume_db = lerpf(_bgm_intense.volume_db, target_intense, delta * 4.0)
		_bgm_calm.volume_db = lerpf(_bgm_calm.volume_db, target_calm, delta * 4.0)
	for state: BallState in [left_ball_state, right_ball_state]:
		if state.mode == BallMode.HELD:
			var hand = state.held_hand
			var target: Vector3 = _hand_hold_point(hand)
			state.body.global_position = state.body.global_position.lerp(target, clampf(delta * 22.0, 0.0, 1.0))
		elif state.mode == BallMode.REST:
			var rest := _ball_rest_point_for_state(state)
			state.body.global_position = state.body.global_position.lerp(rest, clampf(delta * 8.0, 0.0, 1.0))
		if state.trail != null:
			state.trail.emitting = (state.mode == BallMode.FLYING)
			if state.trail.process_material != null:
				var c := state.mat.albedo_color
				state.trail.process_material.color = Color(c.r, c.g, c.b, 0.2)
	_recover_indents(delta)


func _on_cube_hit(_other: Node, cube: RigidBody3D) -> void:
	var now := Time.get_ticks_msec()
	if now < _cube_sound_until:
		return
	var id := cube.get_instance_id()
	var last: int = _hit_sound_at.get(id, -100000)
	if now - last < 110:
		return
	_hit_sound_at[id] = now
	var strength := clampf(cube.linear_velocity.length() / 6.0, 0.15, 1.0)
	_play_sound("knock", cube.global_position, strength)
	if strength > 0.45:
		var mesh := cube.get_node("Mesh") as MeshInstance3D
		var col := Color(0.7, 0.7, 0.7)
		if mesh != null and mesh.material_override is StandardMaterial3D:
			col = (mesh.material_override as StandardMaterial3D).albedo_color
		_spawn_debris(cube.global_position, col, strength)


func _on_ball_hit(_other: Node, state: BallState) -> void:
	if state.mode != BallMode.FLYING:
		return
	var is_cube := _other is RigidBody3D and cubes.has(_other)
	var now := Time.get_ticks_msec()
	if now - state.sound_at < 200:
		return
	state.sound_at = now
	var strength := clampf(state.body.linear_velocity.length() / 7.0, 0.1, 1.0)
	var hand = state.held_hand if state.held_hand != null else _last_throw_hand
	if hand == null or not is_instance_valid(hand):
		hand = right_controller
	rig.pulse_haptic(hand, lerpf(0.25, 0.85, strength), lerpf(0.03, 0.11, strength))

	if is_cube:
		if strength > 0.35:
			_spawn_impact_flash(state.body.global_position, state.mat.albedo_color, strength)
		_indent_cube(_other as Node3D, state.body)
		if active_powerup == Powerup.ICE and state == _powerup_state:
			_other.apply_central_impulse(state.body.linear_velocity.normalized() * ICE_IMPULSE)
			_play_sound("ice", state.body.global_position, 1.0)
		elif active_powerup == Powerup.FIRE and state == _powerup_state and not _powerup_used:
			_powerup_used = true
			_explosion_center = state.body.global_position
			_explosion_ball_state = state
			_play_sound("fire", state.body.global_position, 1.0)
			call_deferred("_explode")
			return
		elif active_powerup == Powerup.HEAVY and state == _powerup_state:
			_play_sound("heavy", state.body.global_position, strength)
		elif randf() < powerup_chance:
			var roll := (randi() % 3) + 1
			_grant_powerup(roll)
		else:
			_play_sound("thud", state.body.global_position, strength)
	else:
		_play_sound("thud", state.body.global_position, strength)


func _indent_cube(cube: RigidBody3D, other: Node3D) -> void:
	var mesh := cube.get_node("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var impact_dir := (cube.global_position - other.global_position).normalized()
	var local_dir := cube.global_transform.basis.inverse() * impact_dir
	local_dir = local_dir.normalized()
	var speed := cube.linear_velocity.length()
	var amount := clampf(speed / 8.0, 0.04, INDENT_MAX)
	var target := Vector3(
		1.0 - abs(local_dir.x) * amount + (abs(local_dir.y) + abs(local_dir.z)) * amount * 0.35,
		1.0 - abs(local_dir.y) * amount + (abs(local_dir.x) + abs(local_dir.z)) * amount * 0.35,
		1.0 - abs(local_dir.z) * amount + (abs(local_dir.x) + abs(local_dir.y)) * amount * 0.35
	)
	mesh.scale = target
	cube.set_meta("indent_target", target)
	cube.set_meta("indent_time", INDENT_RECOVER)


func _recover_indents(delta: float) -> void:
	for c in cubes:
		if not is_instance_valid(c):
			continue
		var t: float = c.get_meta("indent_time", 0.0)
		if t <= 0.0:
			continue
		t -= delta
		c.set_meta("indent_time", maxf(t, 0.0))
		var mesh := c.get_node("Mesh") as MeshInstance3D
		if mesh == null:
			continue
		var target: Vector3 = c.get_meta("indent_target", Vector3.ONE)
		var factor := t / INDENT_RECOVER
		mesh.scale = target.lerp(Vector3.ONE, 1.0 - factor)


func _apply_pending_powerup(for_state: BallState = null) -> void:
	if _pending_powerup == Powerup.NONE:
		return
	var target := for_state
	if target == null:
		if right_ball_state.mode != BallMode.FLYING:
			target = right_ball_state
		elif left_ball_state.mode != BallMode.FLYING:
			target = left_ball_state
	if target == null:
		return
	active_powerup = _pending_powerup
	_pending_powerup = Powerup.NONE
	_powerup_time = POWERUP_DURATION
	_powerup_used = false
	_powerup_state = target
	_apply_powerup_visuals(target)
	_update_score_label()


func _grant_powerup(kind: int) -> void:
	var name := _powerup_name(kind)
	var target: BallState = null
	if right_ball_state.mode != BallMode.FLYING:
		target = right_ball_state
	elif left_ball_state.mode != BallMode.FLYING:
		target = left_ball_state
	if active_powerup == Powerup.NONE and target != null:
		active_powerup = kind as Powerup
		_powerup_time = POWERUP_DURATION
		_powerup_used = false
		_powerup_state = target
		_apply_powerup_visuals(target)
		_show_hint("%s BALL!" % name, 2.0)
		_play_sound("chime", _ball_rest_point_for_state(target), 1.0)
	else:
		_pending_powerup = kind as Powerup
		_show_hint("NEXT: %s BALL!" % name, 2.0)
		_play_sound("chime", _ball_rest_point(), 0.7)
	_update_score_label()


func _clear_powerup() -> void:
	active_powerup = Powerup.NONE
	_powerup_time = 0.0
	_powerup_used = false
	if _powerup_state != null and is_instance_valid(_powerup_state.body):
		_powerup_state.body.mass = _base_ball_mass
		_powerup_state.visual.scale = Vector3.ONE
		_powerup_state.mat.albedo_color = _powerup_state.base_color
		_powerup_state.mat.emission = _powerup_state.base_emission
		_powerup_state.mat.emission_energy_multiplier = 0.6
	_powerup_state = null
	_update_score_label()
	if _pending_powerup != Powerup.NONE and _any_ball_at_rest():
		_apply_pending_powerup()


func _apply_powerup_visuals(state: BallState) -> void:
	if state.body == null or state.visual == null or state.mat == null:
		return
	match active_powerup:
		Powerup.HEAVY:
			state.body.mass = HEAVY_MASS
			state.mat.albedo_color = Color(0.25, 0.25, 0.28)
			state.mat.emission = Color(0.05, 0.05, 0.08)
			state.mat.emission_energy_multiplier = 0.6
			state.visual.scale = Vector3(1.5, 1.5, 1.5)
		Powerup.ICE:
			state.body.mass = ICE_MASS
			state.mat.albedo_color = Color(0.75, 0.92, 1.0)
			state.mat.emission = Color(0.4, 0.75, 0.95)
			state.mat.emission_energy_multiplier = 0.9
			state.visual.scale = Vector3(1.15, 1.15, 1.15)
		Powerup.FIRE:
			state.body.mass = _base_ball_mass
			state.mat.albedo_color = Color(1.0, 0.18, 0.05)
			state.mat.emission = Color(1.0, 0.08, 0.0)
			state.mat.emission_energy_multiplier = 2.2
			state.visual.scale = Vector3(1.25, 1.25, 1.25)


func _explode() -> void:
	var state := _explosion_ball_state if _explosion_ball_state != null else right_ball_state
	_clear_powerup()
	_respawn_ball(state, false)
	for c in cubes:
		if not is_instance_valid(c):
			continue
		var dir := c.global_position - _explosion_center
		var dist := dir.length()
		if dist < FIREBALL_RADIUS and dist > 0.001:
			c.sleeping = false
			var falloff := 1.0 - (dist / FIREBALL_RADIUS)
			c.apply_central_impulse(dir.normalized() * FIREBALL_FORCE * falloff)
			c.apply_torque_impulse(Vector3(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)))
	_play_sound("whoosh", _explosion_center, 1.0)
	_show_hint("BOOM!", 1.5)
	var hand := left_controller if _explosion_ball_state == left_ball_state else right_controller
	rig.pulse_haptic(hand, 0.9, 0.15)


func launch_ball(from: Vector3, vel: Vector3, hand = right_controller) -> void:
	var state := _ball_state_for_hand(hand)
	state.mode = BallMode.FLYING
	state.body.freeze = false
	state.body.global_position = from
	state.body.linear_velocity = vel
	state.body.angular_velocity = Vector3(2.0, 2.0, 2.0)


func _play_sound(kind: String, at: Vector3, strength: float) -> void:
	var stream := sfx.stream_for(kind)
	if stream == null:
		return
	var player := _sound_players[_sound_next]
	_sound_next = (_sound_next + 1) % _sound_players.size()
	player.global_position = at
	player.stream = stream
	player.volume_db = lerpf(-14.0, -2.0, clampf(strength, 0.0, 1.0))
	player.play()


func _reset_tower() -> void:
	_reset_rounds()


func _show_congrats() -> void:
	if _congrats_label == null:
		_congrats_label = Label3D.new()
		_congrats_label.name = "CongratsLabel"
		_congrats_label.position = Vector3(0, 8.5, -3.4)
		_congrats_label.font_size = 72
		_congrats_label.pixel_size = 0.001
		_congrats_label.modulate = Color(1.0, 0.9, 0.3, 1.0)
		_congrats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_congrats_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_congrats_label)
	_congrats_label.text = "Congratulations, you invested significant effort!"
	_congrats_label.visible = true


func _hide_congrats() -> void:
	if _congrats_label != null:
		_congrats_label.visible = false


func _build_restart_box() -> void:
	if _restart_box != null:
		return
	_restart_box = RigidBody3D.new()
	_restart_box.name = "RestartBox"
	_restart_box.position = TOWER_CENTER + Vector3(0, 3.0, 0)
	_restart_box.freeze = false
	_restart_box.mass = 5.0
	_restart_box.contact_monitor = true
	_restart_box.max_contacts_reported = 2
	_restart_box.body_entered.connect(_on_restart_box_hit)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.1
	_restart_box.physics_material_override = pm

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(RESTART_BOX_SIZE, RESTART_BOX_SIZE, RESTART_BOX_SIZE)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.5, 0.2)
	mat.emission_energy_multiplier = 0.8
	mat.roughness = 0.4
	mesh.material_override = mat
	_restart_box.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(RESTART_BOX_SIZE, RESTART_BOX_SIZE, RESTART_BOX_SIZE)
	_restart_box.add_child(shape)

	add_child(_restart_box)

	_restart_label = Label3D.new()
	_restart_label.name = "RestartLabel"
	_restart_label.position = Vector3(0, RESTART_BOX_SIZE * 0.75, 0)
	_restart_label.font_size = 48
	_restart_label.pixel_size = 0.001
	_restart_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_restart_label.text = "destroy me to restart the rounds"
	_restart_box.add_child(_restart_label)


func _destroy_restart_box() -> void:
	if _restart_box != null:
		_restart_box.queue_free()
		_restart_box = null
		_restart_label = null


func _on_restart_box_hit(other: Node) -> void:
	if _rounds_complete and (other == left_ball_state.body or other == right_ball_state.body):
		_reset_rounds()
