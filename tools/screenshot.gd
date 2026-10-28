extends SceneTree
## 截图工具：启动场景，运行若干秒后截图存盘
## 用法: godot --headless --script res://tools/screenshot.gd
## 注意: 需要真实渲染上下文，不能用 --headless

const OUT_PATH := "user://screenshot.png"
const RUN_SECONDS := 12.0
const OPEN_SHOP := true     ## 截图时是否打开商店面板

var _main_node: Node = null
var _shop_opened := false


func _init() -> void:
	root.set_content_scale_size(Vector2i(1280, 720))
	# 加载主场景
	var scene: PackedScene = load("res://scenes/main.tscn")
	var node := scene.instantiate()
	root.add_child(node)
	if OPEN_SHOP:
		# 打开商店（验证 UI 能渲染）
		# ★ 必须在节点入树之后再调用：_init() 阶段 main._ready() 还没跑，
		#   get_node_or_null 拿不到子节点，_toggle_shop 会静默 return
		_main_node = node
		print("[screenshot] 节点已入树, 稍后打开商店")


func _process(delta: float) -> bool:
	if _main_node != null and not _shop_opened:
		_shop_opened = true
		if _main_node.has_method("_toggle_shop"):
			_main_node.call("_toggle_shop")
			print("[screenshot] 已打开商店面板")
		var sp = _main_node.get_node_or_null("OverlayLayer/ShopPanel")
		if sp:
			print("[screenshot] shop_panel visible=%s children=%d" % [sp.visible, sp.get_child_count()])
		return false

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
