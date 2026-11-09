extends RefCounted
# Procedural sound effects: tiny PCM streams synthesized at boot so the game
# ships zero audio assets. Each entry is an AudioStreamWAV of 8-bit samples.

const RATE := 22050

# a sine blip with an exponential decay — the "ding" family
static func tone(freq: float, dur: float, vol := 0.5, slide := 1.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * freq * pow(slide, t * 8.0) / RATE
		var env: float = exp(-6.0 * t / dur)
		data[i] = int(128 + 127 * vol * env * sin(ph))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = RATE
	s.data = data
	return s

# filtered noise burst — hits, thuds, breaks
static func noise(dur: float, vol := 0.5, decay := 8.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51f7
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerp(lp, rng.randf_range(-1.0, 1.0), 0.35) # cheap lowpass
		data[i] = int(128 + 127 * vol * exp(-decay * t / dur) * lp)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = RATE
	s.data = data
	return s

# two-tone arpeggio — chimes (catch, level up)
static func arp(freqs: Array, step := 0.09, vol := 0.4) -> AudioStreamWAV:
	var n := int(RATE * step * freqs.size()) + int(RATE * 0.15)
	var data := PackedByteArray()
	data.resize(n)
	for i in n:
		var t := float(i) / RATE
		var fi: int = mini(int(t / step), freqs.size() - 1)
		var lt: float = t - fi * step
		var env: float = exp(-9.0 * lt / maxf(0.001, step * freqs.size()))
		data[i] = int(128 + 127 * vol * env * sin(TAU * float(freqs[fi]) * t))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = RATE
	s.data = data
	return s
