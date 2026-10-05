class_name ScreenFade
extends CanvasLayer
## Fundido a negro entre escenas: ScreenFade.go(get_tree(), "res://mi_escena.tscn", 0.6)
## Oscurece la pantalla, cambia de escena y vuelve a aclarar. Se borra solo al terminar.

static func go(tree: SceneTree, scene_path: String, time: float = 0.6) -> void:
	var f := ScreenFade.new()
	f.layer = 200
	tree.root.add_child(f)
	f._run(scene_path, time)

func _run(path: String, time: float) -> void:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.modulate.a = 0.0
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP   # mientras funde no se puede pulsar nada
	add_child(r)
	var t := create_tween()
	t.tween_property(r, "modulate:a", 1.0, maxf(time, 0.01))
	await t.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(r, "modulate:a", 0.0, maxf(time, 0.01))
	await t2.finished
	queue_free()
