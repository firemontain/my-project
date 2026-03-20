## NPCPhysiologicalSys.gd
## NPC生理系统 - 管理兴奋度和压力值
class_name NPCPhysiologicalSys
extends RefCounted

## 信号：生理状态变化
signal state_changed(excitement: float, stress: float)

## 当前兴奋度（0-100）
var excitement: float = 0.0

## 当前压力值（0-100）
var stress: float = 0.0

## 基础兴奋度
var base_excitement: float = 0.0

## 基础压力值
var base_stress: float = 0.0

## 兴奋度衰减率（每轮）
var excitement_decay: float = 5.0

## 压力衰减率（每轮）
var stress_decay: float = 3.0


## 初始化
func _init(p_base_excitement: float = 0.0, p_base_stress: float = 0.0, 
		   p_excitement_decay: float = 5.0, p_stress_decay: float = 3.0) -> void:
	base_excitement = p_base_excitement
	base_stress = p_base_stress
	excitement_decay = p_excitement_decay
	stress_decay = p_stress_decay
	excitement = base_excitement
	stress = base_stress


## 应用修正器（来自玩家能力或牌局事件）
func apply_modifier(excitement_delta: float, stress_delta: float) -> void:
	excitement = clampf(excitement + excitement_delta, 0.0, 100.0)
	stress = clampf(stress + stress_delta, 0.0, 100.0)
	state_changed.emit(excitement, stress)


## 每轮衰减
func decay_values() -> void:
	excitement = maxf(0.0, excitement - excitement_decay)
	stress = maxf(0.0, stress - stress_decay)
	state_changed.emit(excitement, stress)


## 重置到基础状态
func reset() -> void:
	excitement = base_excitement
	stress = base_stress
	state_changed.emit(excitement, stress)


## 获取EV修正系数
## 高兴奋度 → 更激进（EV阈值降低）
## 高压力 → 更保守或更冲动（取决于陷阱类型）
func get_ev_modifier() -> float:
	var excitement_factor := (excitement - 50.0) / 100.0  # -0.5 到 0.5
	var stress_factor := (stress - 50.0) / 100.0
	# 兴奋度高时倾向加注，压力高时决策更极端
	return 1.0 + excitement_factor * 0.3 + stress_factor * 0.2


## 检查是否处于高兴奋状态
func is_highly_excited() -> bool:
	return excitement >= 70.0


## 检查是否处于高压力状态
func is_highly_stressed() -> bool:
	return stress >= 70.0


## 获取状态描述
func get_state_description() -> String:
	var excitement_desc := "平静"
	if excitement >= 80:
		excitement_desc = "极度兴奋"
	elif excitement >= 60:
		excitement_desc = "兴奋"
	elif excitement >= 40:
		excitement_desc = "有些激动"
	
	var stress_desc := "放松"
	if stress >= 80:
		stress_desc = "极度紧张"
	elif stress >= 60:
		stress_desc = "紧张"
	elif stress >= 40:
		stress_desc = "有些焦虑"
	
	return "%s / %s" % [excitement_desc, stress_desc]
