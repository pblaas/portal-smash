extends RefCounted
class_name SoundKit

# Procedurally synthesized one-shots (16-bit mono WAV) so the app ships
# zero audio files: knock impacts, ground thuds, throw whoosh, spawn chime.

const SAMPLE_RATE := 22050

var knock: AudioStreamWAV
var thud: AudioStreamWAV
var whoosh: AudioStreamWAV
var chime: AudioStreamWAV


func build() -> void:
	knock = _synth(0.16, _make_knock)
	thud = _synth(0.2, _make_thud)
	whoosh = _synth(0.38, _make_whoosh)
	chime = _synth(0.4, _make_chime)


static func _synth(duration: float, fill: Callable) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = float(fill.call(i, float(i) / SAMPLE_RATE, float(count) / SAMPLE_RATE))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
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
	return null
