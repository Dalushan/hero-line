class_name TDGrid
extends RefCounted
## 网格 / 流场 / 放置合法性校验
## 纯逻辑层，不依赖任何 Node，可在 headless 下运行与单测。

enum Cell {
	GROUND,     ## 敌人可通行
	BUILDABLE,  ## 可建造英雄/防御塔的格子
	BLOCKED,    ## 已被建筑占据
}

const WIDTH := 20
const HEIGHT := 14

var width: int
var height: int
var cells: Array[int] = []
var spawn_cell: Vector2i
var base_cell: Vector2i

## flow_dist[i] = 该格到基地的最短步数（不可达为 INF）
var flow_dist: Array[int] = []
var _queue: Array[int] = []

const INF := 999999


func _init(w: int = WIDTH, h: int = HEIGHT) -> void:
	width = w
	height = h
	cells.resize(width * height)
	cells.fill(Cell.GROUND)
	spawn_cell = Vector2i(width / 2, 1)
	base_cell = Vector2i(width / 2, height - 2)
	_build_default_layout()


func idx(x: int, y: int) -> int:
	return y * width + x


func cell(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_cell(v: Vector2i) -> int:
	if not in_bounds(v.x, v.y):
		return Cell.BLOCKED
	return cells[idx(v.x, v.y)]


func set_cell(v: Vector2i, c: int) -> void:
	if in_bounds(v.x, v.y):
		cells[idx(v.x, v.y)] = c


func is_passable(v: Vector2i) -> bool:
	var c := get_cell(v)
	return c == Cell.GROUND or c == Cell.BUILDABLE


## 默认布局：一条 L 形主通路，其余为可建造格
func _build_default_layout() -> void:
	for y in range(height):
		for x in range(width):
			cells[idx(x, y)] = Cell.BUILDABLE
	# 竖直通道
	for y in range(spawn_cell.y, base_cell.y + 1):
		cells[idx(spawn_cell.x, y)] = Cell.GROUND
	# 水平通道（通往基地）
	for x in range(spawn_cell.x, base_cell.x + 1):
		cells[idx(x, base_cell.y)] = Cell.GROUND
	# 基地与出兵口
	cells[idx(base_cell.x, base_cell.y)] = Cell.GROUND
	cells[idx(spawn_cell.x, spawn_cell.y)] = Cell.GROUND


## 从基地反向 BFS 计算流场。返回是否成功（基地可达）
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
		var cx := cur % width
		var cy := cur / width
		var d: int = flow_dist[cur]
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nx := cx + dir.x
			var ny := cy + dir.y
			if not in_bounds(nx, ny):
				continue
			var ni := idx(nx, ny)
			if not is_passable(Vector2i(nx, ny)):
				continue
			if flow_dist[ni] != INF:
				continue
			flow_dist[ni] = d + 1
			_queue.append(ni)
	return flow_dist[idx(spawn_cell.x, spawn_cell.y)] != INF


## 放置合法性：① 该格可建造且为空 ② 放置后不产生死路
## strict_islands=true 时还要求不产生孤立空地（无意义浪费格子）
func can_place(v: Vector2i, strict_islands: bool = true) -> Dictionary:
	if not in_bounds(v.x, v.y):
		return {"ok": false, "reason": "超出战场范围"}
	var c := get_cell(v)
	if c == Cell.GROUND:
		return {"ok": false, "reason": "通路格不可建造"}
	if c == Cell.BLOCKED:
		return {"ok": false, "reason": "该格已被占用"}
	# 临时占位
	cells[idx(v.x, v.y)] = Cell.BLOCKED
	var path_ok := recompute_flow()
	var islands_ok := true
	if path_ok and strict_islands:
		islands_ok = _all_ground_reachable()
	# 还原
	cells[idx(v.x, v.y)] = Cell.BUILDABLE
	recompute_flow()
	if not path_ok:
		return {"ok": false, "reason": "会封死通往基地的路线"}
	if not islands_ok:
		return {"ok": false, "reason": "会围出无法到达的死角"}
	return {"ok": true, "reason": ""}


func _all_ground_reachable() -> bool:
	for y in range(height):
		for x in range(width):
			if cells[idx(x, y)] == Cell.GROUND:
				if flow_dist[idx(x, y)] == INF:
					return false
	return true


## 敌人下一步移动方向（沿流场梯度）。无路可走时返回 Vector2i.ZERO
func next_step(from: Vector2i) -> Vector2i:
	if not in_bounds(from.x, from.y):
		return Vector2i.ZERO
	var best := Vector2i.ZERO
	var best_d: int = flow_dist[idx(from.x, from.y)]
	if best_d == INF:
		return Vector2i.ZERO
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var nx := from.x + dir.x
		var ny := from.y + dir.y
		if not in_bounds(nx, ny):
			continue
		if not is_passable(Vector2i(nx, ny)):
			continue
		var d: int = flow_dist[idx(nx, ny)]
		if d < best_d:
			best_d = d
			best = dir
	return best


## 建造格列表（供 AI 布防使用）
func buildable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if cells[idx(x, y)] == Cell.BUILDABLE:
				out.append(Vector2i(x, y))
	return out


## 到通路的曼哈顿距离（布防优先级：越近越优先）
func dist_to_path(v: Vector2i) -> int:
	var best := 9999
	for y in range(height):
		for x in range(width):
			if cells[idx(x, y)] == Cell.GROUND:
				best = min(best, abs(v.x - x) + abs(v.y - y))
	return best
