extends SceneTree
## 截图工具：启动场景，运行若干秒后截图存盘
## 用法: godot --headless --script res://tools/screenshot.gd
## 注意: 需要真实渲染上下文，不能用 --headless

const OUT_PATH := "user://screenshot.png"
const RUN_SECONDS := 12.0


func _init() -> void:
	root.set_content_scale_size(Vector2i(1280, 720))
	# 加载主场景
	var scene: PackedScene = load("res://scenes/main.tscn")
	var node := scene.instantiate()
	root.add_child(node)
	print("[screenshot] 场景已加载，运行 %.0f 秒后截图" % RUN_SECONDS)


func _process(delta: float) -> bool:
	var elapsed := float(Time.get_ticks_msec()) / 1000.0
	if elapsed < RUN_SECONDS:
		return false
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_PATH)
	var err := img.save_png(path)
	if err == OK:
		print("[screenshot] 已保存: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	else:
		print("[screenshot] 保存失败 err=%d" % err)
	quit(0)
	return true
