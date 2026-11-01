class_name Rng
# mulberry32 — same algorithm as the TS prototype for reproducible seeds.

var s: int

func _init(seed: int) -> void:
	s = seed & 0xFFFFFFFF

func next() -> float:
	s = (s + 0x6d2b79f5) & 0xFFFFFFFF
	var t := s
	t = ((t ^ (t >> 15)) * (1 | t)) & 0xFFFFFFFF
	t = ((t + ((t ^ (t >> 7)) * (61 | t))) & 0xFFFFFFFF) ^ t
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

func int_range(lo: int, hi: int) -> int:
	return lo + int(next() * (hi - lo + 1))

func pick(arr: Array) -> Variant:
	return arr[int(next() * arr.size())]

func chance(p: float) -> bool:
	return next() < p

static func hash2(x: int, y: int, seed: int) -> float:
	var h: int = seed & 0xFFFFFFFF
	h = ((h ^ (x & 0xFFFFFFFF)) * 0x27d4eb2d) & 0xFFFFFFFF
	h = ((h ^ (y & 0xFFFFFFFF)) * 0x165667b1) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x85ebca6b) & 0xFFFFFFFF
	h ^= h >> 13
	return float(h & 0xFFFFFFFF) / 4294967296.0
