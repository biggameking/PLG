extends SceneTree
func _initialize() -> void:
	var fo := FileAccess.open("res://tools/dbg.txt", FileAccess.WRITE)
	fo.store_string("init ok")
	fo.close()
var n := 0
func _process(dt) -> bool:
	n += 1
	if n == 3:
		var fo := FileAccess.open("res://tools/dbg2.txt", FileAccess.WRITE)
		fo.store_string("process ran %d" % n)
		fo.close()
		quit()
	return true
