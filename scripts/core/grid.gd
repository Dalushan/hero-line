class_name TDGrid
extends RefCounted
## 网格 / 流场 / 放置合法性校验
## 纯逻辑层，不依赖任何 Node，可在 headless 下运行与单测。
##
## ===== 格子语义 =====
##   GROUND     —— 永久通路（仅出兵口与基地），不可建造、敌人永远可走
##   PATH       —— 进攻路线格：敌人可走 + 可建防御塔（可被挤窄，甚至堵死）
##   BUILDABLE  —— 防守阵地格：敌人不可走，仅可放英雄（与路径分离）
##   BLOCKED    —— 已被建筑占据
##
## ===== 为什么英雄可以站在路线上 =====
## 英雄站在路线格上会阻挡敌人 → 敌人必须绕行并与英雄交战（射程内）→ 英雄能持续输出。
## 若英雄只能站在远离路线的空地上，近战英雄射程2根本追不上移动1.6格/秒的敌人，
## 只能打到1下就脱离战斗 —— 实测从第2波起0击杀。
## 让英雄"站上防线"既解决数值问题，也更符合"我方防守阵地"的设计语义。

enum Cell {
	GROUND,
	PATH,
	BUILDABLE,
	BLOCKED,
}

enum PlaceKind {
	HERO,   ## 放英雄：只能在防守阵地格(BUILDABLE)
	TOWER,  ## 放防御塔：只能在进攻路线格(PATH)
}

const WIDTH := 20
const HEIGHT := 14

## 走廊半宽（3 格宽）
const CORRIDOR_HALF := 1

var width: int
var height: int
var cells: Array[int] = []
var spawn_cell: Vector2i
var base_cell: Vector2i

## flow_dist[i] = 该格到基地的最短步数（不可达为 INF）
var flow_dist: Array[int] = []
var _queue: Array[int] = []

const INF := 999999

## 四个方向的常量表（typed，避免 Variant 推断）
const DIRS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
]


func _init(w: int = WIDTH, h: int = HEIGHT) -> void:
	width = w
	height = h
	cells.resize(width * height)
	cells.fill(Cell.BUILDABLE)
	spawn_cell = Vector2i(width / 2, 1)
	base_cell = Vector2i(width / 2, height - 2)
	_build_default_layout()
	# 构造后立即计算流场 —— 保证 grid 一创建就是一致状态
	# （否则外部直接调用 next_step() 会读到未初始化的 flow_dist）
	recompute_flow()


func idx(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_cell(v: Vector2i) -> int:
	if not in_bounds(v.x, v.y):
		return Cell.BLOCKED
	return cells[idx(v.x, v.y)]


func set_cell(v: Vector2i, c: int) -> void:
	if in_bounds(v.x, v.y):
		cells[idx(v.x, v.y)] = c


## 敌人能否行走
func is_walkable(v: Vector2i) -> bool:
	var c := get_cell(v)
	return c == Cell.GROUND or c == Cell.PATH


## 是否属于路线（GROUND 或 PATH）
func is_on_path(v: Vector2i) -> bool:
	var c := get_cell(v)
	return c == Cell.GROUND or c == Cell.PATH


## 英雄站位（防守阵地格，未被占用）
func hero_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if cells[idx(x, y)] == Cell.BUILDABLE:
				out.append(Vector2i(x, y))
	return out


## 防御塔位（路线格，未被占用）
func tower_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if cells[idx(x, y)] == Cell.PATH:
				out.append(Vector2i(x, y))
	return out


## 默认布局：
##   竖直走廊 x ∈ [cx-1, cx+1]，从出兵口到基地行
##   水平走廊 y ∈ [by-1, by+1]，覆盖基地
##   走廊全部 = PATH（可建塔，会改变寻路）
##   走廊之外 = BUILDABLE（防守阵地，放英雄，敌人不可走）
##   出兵口与基地 = GROUND（永久开放）
func _build_default_layout() -> void:
	for y in range(height):
		for x in range(width):
			cells[idx(x, y)] = Cell.BUILDABLE

	# 竖直走廊
	for y in range(spawn_cell.y, base_cell.y + 1):
		for x in range(spawn_cell.x - CORRIDOR_HALF, spawn_cell.x + CORRIDOR_HALF + 1):
			if in_bounds(x, y):
				cells[idx(x, y)] = Cell.PATH

	# 水平走廊
	for x in range(spawn_cell.x - CORRIDOR_HALF, base_cell.x + CORRIDOR_HALF + 1):
		for y in range(base_cell.y - CORRIDOR_HALF, base_cell.y + CORRIDOR_HALF + 1):
			if in_bounds(x, y):
				cells[idx(x, y)] = Cell.PATH

	# 出兵口与基地永久开放
	cells[idx(spawn_cell.x, spawn_cell.y)] = Cell.GROUND
	cells[idx(base_cell.x, base_cell.y)] = Cell.GROUND


## 从基地反向 BFS 计算流场。返回基地是否可达（true = 出兵口能走到基地）
func recompute_flow() -> bool:
	flow_dist.resize(width * height)
	flow_dist.fill(INF)
	_queue.clear()
	var bi := idx(base_cell.x, base_cell.y)
	flow_dist[bi] = 0
	_queue.append(bi)
	var head := 0
	while head < _queue.size():
		var cur := _queue[head]
		head += 1
		var cx: int = cur % width
		var cy: int = cur / width
		var d: int = flow_dist[cur]
		for dir in DIRS:
			var nx: int = cx + dir.x
			var ny: int = cy + dir.y
			if not in_bounds(nx, ny):
				continue
			if not is_walkable(Vector2i(nx, ny)):
				continue
			var ni := idx(nx, ny)
			if flow_dist[ni] != INF:
				continue
			flow_dist[ni] = d + 1
			_queue.append(ni)
	return flow_dist[idx(spawn_cell.x, spawn_cell.y)] != INF


## 放置合法性校验
##  kind = HERO  → 可放防守阵地格(不挡路) 或 进攻路线格(会挡路，敌人须绕行并交战)
##  kind = TOWER → 只能放路线格，必须保证不堵死路径、不产生孤立路线段
func can_place(v: Vector2i, kind: int = PlaceKind.HERO) -> Dictionary:
	if not in_bounds(v.x, v.y):
		return {"ok": false, "reason": "超出战场范围"}
	var c := get_cell(v)
	if c == Cell.BLOCKED:
		return {"ok": false, "reason": "该格已被占用"}
	if c == Cell.GROUND:
		return {"ok": false, "reason": "出入口不可建造"}

	if kind == PlaceKind.HERO and c != Cell.BUILDABLE and c != Cell.PATH:
		return {"ok": false, "reason": "英雄只能部署在防守阵地或进攻路线"}
	if kind == PlaceKind.TOWER and c != Cell.PATH:
		return {"ok": false, "reason": "防御塔只能建在进攻路线上"}

	# 该格当前若已与基地隔绝，建塔没有意义（也不应允许）
	recompute_flow()
	if is_on_path(v) and flow_dist[idx(v.x, v.y)] == INF:
		return {"ok": false, "reason": "该位置已与路线隔绝"}

	# 临时占位 → 校验 → 还原
	var saved := c
	cells[idx(v.x, v.y)] = Cell.BLOCKED
	var path_ok := recompute_flow()
	var islands_ok := true
	if path_ok:
		islands_ok = _all_path_reachable()
	cells[idx(v.x, v.y)] = saved
	recompute_flow()

	if not path_ok:
		return {"ok": false, "reason": "会封死通往基地的路线"}
	if not islands_ok:
		return {"ok": false, "reason": "会围出无法到达的死角"}
	return {"ok": true, "reason": ""}


## 所有路线格是否都能到达基地
func _all_path_reachable() -> bool:
	for y in range(height):
		for x in range(width):
			if is_on_path(Vector2i(x, y)):
				if flow_dist[idx(x, y)] == INF:
					return false
	return true


## 敌人下一步移动方向（沿流场梯度）。无路可走返回 Vector2i.ZERO
func next_step(from: Vector2i) -> Vector2i:
	if not in_bounds(from.x, from.y):
		return Vector2i.ZERO
	if flow_dist.size() != width * height:
		recompute_flow()
	var best := Vector2i.ZERO
	var best_d: int = flow_dist[idx(from.x, from.y)]
	if best_d == INF:
		return Vector2i.ZERO
	for dir in DIRS:
		var nx: int = from.x + dir.x
		var ny: int = from.y + dir.y
		if not in_bounds(nx, ny):
			continue
		if not is_walkable(Vector2i(nx, ny)):
			continue
		var d: int = flow_dist[idx(nx, ny)]
		if d < best_d:
			best_d = d
			best = dir
	return best


## 到最近路线格的曼哈顿距离（布防优先级：越近越优先）
func dist_to_path(v: Vector2i) -> int:
	var best := 9999
	for y in range(height):
		for x in range(width):
			if is_on_path(Vector2i(x, y)):
				best = min(best, abs(v.x - x) + abs(v.y - y))
	return best


## 统计信息（调试用）
func stats() -> Dictionary:
	var d := {"ground": 0, "path": 0, "buildable": 0, "blocked": 0}
	for c in cells:
		match c:
			Cell.GROUND: d["ground"] += 1
			Cell.PATH: d["path"] += 1
			Cell.BUILDABLE: d["buildable"] += 1
			Cell.BLOCKED: d["blocked"] += 1
	return d
