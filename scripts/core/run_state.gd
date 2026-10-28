class_name TDRunState
extends RefCounted
## 一局游戏的全局状态（纯数据，可序列化）。core 层所有系统都读写它。

signal state_changed()

enum Phase {
	PREPARING,   ## 布防期
	DRAFTING,    ## 支援二选一
	RUNNING,     ## 波次进行中
	SETTLING,    ## 波次结算
	VICTORY,
	DEFEAT,
}

var phase: int = Phase.PREPARING
var wave: int = 0
var stage_index: int = 0
var difficulty: int = 0            ## 0=普通 1=困难 2=噩梦
var base_hp: int = 1000
var base_hp_max: int = 1000
var gold: int = 0
var time_in_phase: float = 0.0
var elapsed: float = 0.0

var grid: TDGrid
var rng: TDRng

var heroes: Array = []             ## Array[Dictionary]
var enemies: Array = []            ## Array[Dictionary]
var selected_hero_ids: Array = []  ## 已通过支援系统选过的英雄
var support_cards: Array = []      ## 当前待选的卡牌
var wave_groups: Array = []        ## 当前波次编队
var pending_spawns: Array = []     ## 待出怪队列
var run_seed: int = 0

var kills: int = 0
var gold_earned: int = 0
var waves_cleared: int = 0


func _init(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else TDRng.make_random_seed()
	rng = TDRng.new(run_seed)
	grid = TDGrid.new()


## 难度参数
func difficulty_hp_mul() -> float:
	return [1.0, 1.6, 2.4][clampi(difficulty, 0, 2)]


func difficulty_extra_cards() -> int:
	return [0, 1, 1][clampi(difficulty, 0, 2)]


## 生命值映射
func hero_alive_map() -> Dictionary:
	var m := {}
	for h in heroes:
		m[String(h.get("id", ""))] = bool(h.get("alive", false))
	return m


func find_hero(id: String) -> Dictionary:
	for h in heroes:
		if String(h.get("id", "")) == id:
			return h
	return {}


func living_heroes() -> Array:
	var out: Array = []
	for h in heroes:
		if bool(h.get("alive", false)):
			out.append(h)
	return out


func total_hero_dps() -> float:
	var s := 0.0
	for h in heroes:
		if not bool(h.get("alive", false)):
			continue
		var st: Dictionary = h.get("stats", {})
		var atk := float(st.get("attack", 0.0))
		var iv := maxf(float(st.get("atk_interval", 1.0)), 0.1)
		s += atk / iv
	return s


func add_gold(amount: int) -> void:
	gold += amount
	gold_earned += amount


func damage_base(amount: int) -> void:
	base_hp = maxi(0, base_hp - amount)


func is_game_over() -> bool:
	return base_hp <= 0


func advance_phase(new_phase: int) -> void:
	phase = new_phase
	time_in_phase = 0.0
	state_changed.emit()
