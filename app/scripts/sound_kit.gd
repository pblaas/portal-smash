extends RefCounted
class_name SoundKit

# Procedurally synthesized one-shots (16-bit mono WAV) so the app ships
# zero audio files: knock impacts, ground thuds, throw whoosh, spawn chime,
# power-up sounds, and looping background music layers.

const SAMPLE_RATE := 22050
const BGM_DURATION := 8.0

var knock: AudioStreamWAV
var thud: AudioStreamWAV
var whoosh: AudioStreamWAV
var chime: AudioStreamWAV
var heavy: AudioStreamWAV
var ice: AudioStreamWAV
var fire: AudioStreamWAV
var bgm_calm: AudioStreamWAV
var bgm_intense: AudioStreamWAV


func build() -> void:
	knock = _synth(0.16, _make_knock)
	thud = _synth(0.2, _make_thud)
	whoosh = _synth(0.38, _make_whoosh)
	chime = _synth(0.4, _make_chime)
	heavy = _synth(0.28, _make_heavy)
	ice = _synth(0.35, _make_ice)
	fire = _synth(0.55, _make_fire)
	bgm_calm = _make_bgm(_make_bgm_calm)
	bgm_intense = _make_bgm(_make_bgm_intense)


static func _synth(duration: float, fill: Callable) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = float(fill.call(i, float(i) / SAMPLE_RATE, float(count) / SAMPLE_RATE))
	return _pack_wav(samples, false)


static func _make_bgm(fill: Callable) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(BGM_DURATION * SAMPLE_RATE)
	samples.resize(count)
	for i in count:
		samples[i] = float(fill.call(i, float(i) / SAMPLE_RATE, BGM_DURATION))
	return _pack_wav(samples, true)


static func _pack_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	wav.data = bytes
	return wav


static func _make_knock(_i: int, t: float, dur: float) -> float:
	var env := exp(-t * 42.0)
	var noise_decay := exp(-t * 95.0)
	var body := sin(t * 880.0) * exp(-t * 60.0) * 0.5
	body += sin(t * 340.0) * exp(-t * 38.0) * 0.4
	return (body + noise_decay * 0.55) * env * (1.0 - 0.0)


static func _make_thud(_i: int, t: float, dur: float) -> float:
	var sweep := 150.0 * exp(-t * 9.0) + 48.0
	var body := sin(t * sweep * 6.28318) * exp(-t * 16.0)
	return body * 0.9


static func _make_whoosh(i: int, t: float, dur: float) -> float:
	# Band-limited noise with a swell window; light one-pole smoothing below.
	var window := pow(sin(3.14159 * t / dur), 2.2)
	var n := sin(float(i * 2654435761 % 4096) * 0.0123) + sin(float(i * 40503 % 2417) * 0.031)
	return n * window * 0.35


static func _make_chime(i: int, t: float, dur: float) -> float:
	var notes := [880.0, 1174.7, 1567.98]
	var index := int(t / (dur / 3.0))
	index = mini(index, 2)
	var env := exp(-(t - (dur / 3.0) * float(index)) * 9.0)
	return sin(t * notes[index] * 6.28318) * env * 0.24


static func _make_heavy(_i: int, t: float, dur: float) -> float:
	var sweep := 90.0 * exp(-t * 12.0) + 35.0
	var body := sin(t * sweep * 6.28318) * exp(-t * 22.0)
	var noise := _white_noise(_i) * exp(-t * 45.0) * 0.4
	return (body + noise) * 1.1


static func _make_ice(_i: int, t: float, dur: float) -> float:
	var f := 1800.0
	var body := sin(t * f * 6.28318) * exp(-t * 18.0)
	body += sin(t * f * 2.0 * 6.28318) * exp(-t * 22.0) * 0.35
	body += sin(t * f * 3.0 * 6.28318) * exp(-t * 28.0) * 0.18
	var shimmer := _white_noise(_i) * exp(-t * 60.0) * 0.2
	return (body + shimmer) * 0.5


static func _make_fire(i: int, t: float, dur: float) -> float:
	var env := exp(-t * 5.5)
	var n := _white_noise(i) * 0.55 + _white_noise(i * 7) * 0.25
	return n * env * 0.8


static func _make_bgm_calm(i: int, t: float, dur: float) -> float:
	var base := 55.0
	var v := 0.0
	# A-minor drone: A1, E2, A2 (all integer cycles over the loop)
	var freqs := [base, base * 1.5, base * 2.0]
	for f in freqs:
		v += sin(t * f * 6.28318) * 0.14
	# Slow breathing amplitude
	v *= 0.55 + 0.45 * sin(t * 0.125 * 6.28318)
	# Sparse high sparkle
	var sparkle := _white_noise(i) * 0.03 if sin(t * 0.7) > 0.96 else 0.0
	return v + sparkle


static func _make_bgm_intense(i: int, t: float, dur: float) -> float:
	var base := 55.0
	var v := 0.0
	# Driving low drone
	v += sin(t * base * 6.28318) * 0.22
	v += sin(t * base * 2.0 * 6.28318) * 0.12
	# Four-on-the-floor kick every 0.5 s
	var kick_t := fmod(t, 0.5)
	var kick_env := exp(-kick_t * 35.0)
	var kick_freq := 110.0 * exp(-kick_t * 12.0)
	v += sin(t * kick_freq * 6.28318) * kick_env * 0.45
	# Off-beat hat-ish noise
	var hat_t := fmod(t + 0.25, 0.5)
	if hat_t < 0.08:
		v += _white_noise(i) * 0.22
	# Faster arpeggio layer
	var arp_step := int(fmod(t * 4.0, 4.0))
	var arp_notes := [base * 1.5, base * 2.0, base * 1.2, base * 2.5]
	var arp_env := exp(-fmod(t * 4.0, 1.0) * 8.0)
	v += sin(t * arp_notes[arp_step] * 6.28318) * arp_env * 0.16
	return v * 0.75


static func _white_noise(i: int) -> float:
	return sin(float(i * 2654435761 % 4096) * 0.0123)


func stream_for(kind: String) -> AudioStreamWAV:
	match kind:
		"knock":
			return knock
		"thud", "land":
			return thud
		"whoosh":
			return whoosh
		"chime":
			return chime
		"heavy":
			return heavy
		"ice":
			return ice
		"fire":
			return fire
	return null
