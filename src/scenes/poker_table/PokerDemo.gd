## PokerDemo.gd
## 牌局Demo场景控制器
extends Control

## 游戏会话
var session: SimplePokerSession

## UI引用
@onready var player_funds_label: Label = %PlayerFunds
@onready var player_hand_label: Label = %PlayerHand
@onready var player_hand_type_label: Label = %PlayerHandType
@onready var pot_label: Label = %PotAmount
@onready var round_label: Label = %RoundInfo
@onready var to_call_label: Label = %ToCall
@onready var npc_funds_label: Label = %NPCFunds
@onready var npc_hand_label: Label = %NPCHand
@onready var npc_state_label: Label = %NPCState
@onready var npc_trap_label: Label = %NPCTrap
@onready var log_text: RichTextLabel = %LogText

@onready var fold_btn: Button = %FoldBtn
@onready var check_call_btn: Button = %CheckCallBtn
@onready var raise_btn: Button = %RaiseBtn
@onready var raise_amount: SpinBox = %RaiseAmount
@onready var all_in_btn: Button = %AllInBtn
@onready var pressure_btn: Button = %PressureBtn
@onready var excite_btn: Button = %ExciteBtn
@onready var start_btn: Button = %StartBtn
@onready var restart_btn: Button = %RestartBtn


func _ready() -> void:
	# 连接按钮信号
	fold_btn.pressed.connect(_on_fold_pressed)
	check_call_btn.pressed.connect(_on_check_call_pressed)
	raise_btn.pressed.connect(_on_raise_pressed)
	all_in_btn.pressed.connect(_on_all_in_pressed)
	pressure_btn.pressed.connect(_on_pressure_pressed)
	excite_btn.pressed.connect(_on_excite_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	restart_btn.pressed.connect(_on_restart_pressed)
	
	# 初始状态
	_set_action_buttons_enabled(false)
	_set_psych_buttons_enabled(false)
	restart_btn.disabled = true
	
	_log("[color=cyan]欢迎来到牌局Demo！[/color]")
	_log("这是一个简化的梭哈(五张种马)对战演示。")
	_log("点击 [b]开始牌局[/b] 开始游戏。")
	_log("")
	_log("[color=yellow]游戏规则：[/color]")
	_log("- 每人发5张牌（1暗4明）")
	_log("- 共4轮下注")
	_log("- 最后摊牌比大小")
	_log("")
	_log("[color=orange]NPC心理系统：[/color]")
	_log("- 使用「施加压力」和「刺激兴奋」影响NPC决策")
	_log("- 当NPC心理指标达到阈值时会触发「陷阱」行为")


func _on_start_pressed() -> void:
	_start_new_game()


func _on_restart_pressed() -> void:
	_start_new_game()


func _start_new_game() -> void:
	# 随机选择NPC陷阱类型
	var trap_types := [
		NPCTrapSys.TrapType.OVERCONFIDENCE,
		NPCTrapSys.TrapType.TILT,
		NPCTrapSys.TrapType.GREED
	]
	var trap_type: NPCTrapSys.TrapType = trap_types[randi() % trap_types.size()]
	
	# 创建新会话
	session = SimplePokerSession.new(10000, 10000, trap_type)
	
	# 连接信号
	session.round_started.connect(_on_round_started)
	session.player_turn.connect(_on_player_turn)
	session.npc_turn.connect(_on_npc_turn)
	session.npc_decision_made.connect(_on_npc_decision)
	session.round_ended.connect(_on_round_ended)
	session.session_ended.connect(_on_session_ended)
	session.hand_dealt.connect(_on_hand_dealt)
	
	# 更新UI
	start_btn.disabled = true
	restart_btn.disabled = false
	_set_psych_buttons_enabled(true)
	
	_log("")
	_log("[color=green]========== 新牌局开始 ==========[/color]")
	_log("NPC陷阱类型: [color=red]%s[/color]" % session.npc_trap.get_trap_description())
	
	# 更新陷阱显示
	npc_trap_label.text = "陷阱: %s" % _get_trap_short_name(trap_type)
	
	# 开始会话
	session.start_session()


func _get_trap_short_name(trap_type: NPCTrapSys.TrapType) -> String:
	match trap_type:
		NPCTrapSys.TrapType.OVERCONFIDENCE:
			return "过度自信"
		NPCTrapSys.TrapType.LOSS_AVERSION:
			return "损失厌恶"
		NPCTrapSys.TrapType.TILT:
			return "情绪失控"
		NPCTrapSys.TrapType.GREED:
			return "贪婪"
		NPCTrapSys.TrapType.FEAR:
			return "恐惧"
		NPCTrapSys.TrapType.GAMBLER_FALLACY:
			return "赌徒谬误"
	return "未知"


func _on_hand_dealt(_player_hand: Array[CardData], _npc_hand: Array[CardData]) -> void:
	_update_display()


func _on_round_started(round_num: int) -> void:
	_log("")
	_log("[color=yellow]>>> 第 %d 轮开始 <<<[/color]" % round_num)
	_update_display()


func _on_player_turn() -> void:
	_log("[color=cyan]轮到你行动[/color]")
	_set_action_buttons_enabled(true)
	_update_check_call_button()
	_update_display()


func _on_npc_turn(npc_name: String) -> void:
	_log("%s 正在思考..." % npc_name)
	_set_action_buttons_enabled(false)


func _on_npc_decision(npc_name: String, action: String, amount: int) -> void:
	var msg := "%s: [b]%s[/b]" % [npc_name, action]
	if amount > 0:
		msg += " $%d" % amount
	
	# 检查是否是陷阱触发
	if session and session.npc_trap._trap_triggered:
		msg += " [color=red](陷阱触发!)[/color]"
	
	_log(msg)
	_update_display()


func _on_round_ended(round_num: int) -> void:
	_log("第 %d 轮结束" % round_num)


func _on_session_ended(winner: String, pot_amount: int) -> void:
	_set_action_buttons_enabled(false)
	_set_psych_buttons_enabled(false)
	
	_log("")
	_log("[color=green]========== 牌局结束 ==========[/color]")
	
	if winner == "player":
		_log("[color=lime]🎉 你赢了！获得 $%d[/color]" % pot_amount)
	elif winner == "npc":
		_log("[color=red]😢 你输了... NPC获得 $%d[/color]" % pot_amount)
	else:
		_log("[color=yellow]🤝 平局！各分 $%d[/color]" % (pot_amount / 2))
	
	# 显示最终手牌
	if session:
		_log("")
		_log("你的手牌: %s" % _get_full_hand_string(session.player_hand))
		_log("NPC手牌: %s" % _get_full_hand_string(session.npc_hand))
		
		var evaluator := HandEvaluator.new()
		var player_result := evaluator.evaluate(session.player_hand)
		var npc_result := evaluator.evaluate(session.npc_hand)
		_log("你的牌型: [b]%s[/b]" % player_result.description)
		_log("NPC牌型: [b]%s[/b]" % npc_result.description)
	
	_update_display()


func _get_full_hand_string(hand: Array[CardData]) -> String:
	var s := ""
	for card in hand:
		s += card.get_display_name() + " "
	return s.strip_edges()


func _on_fold_pressed() -> void:
	if session:
		_log("你选择: [b]弃牌[/b]")
		session.player_action("fold")
		_set_action_buttons_enabled(false)


func _on_check_call_pressed() -> void:
	if not session:
		return
	
	if session.to_call > 0:
		_log("你选择: [b]跟注[/b] $%d" % session.to_call)
		session.player_action("call")
	else:
		_log("你选择: [b]过牌[/b]")
		session.player_action("check")
	_set_action_buttons_enabled(false)


func _on_raise_pressed() -> void:
	if session:
		var amount := int(raise_amount.value)
		_log("你选择: [b]加注[/b] $%d" % amount)
		session.player_action("raise", amount)
		_set_action_buttons_enabled(false)


func _on_all_in_pressed() -> void:
	if session:
		_log("你选择: [b]全押[/b] $%d" % session.player_funds)
		session.player_action("all_in")
		_set_action_buttons_enabled(false)


func _on_pressure_pressed() -> void:
	if session:
		session.apply_pressure_to_npc(20.0)
		_log("[color=orange]你施加压力！NPC压力 +20[/color]")
		_update_display()


func _on_excite_pressed() -> void:
	if session:
		session.apply_excitement_to_npc(20.0)
		_log("[color=orange]你刺激了NPC！NPC兴奋度 +20[/color]")
		_update_display()


func _update_check_call_button() -> void:
	if session and session.to_call > 0:
		check_call_btn.text = "跟注 $%d" % session.to_call
	else:
		check_call_btn.text = "过牌"


func _set_action_buttons_enabled(enabled: bool) -> void:
	fold_btn.disabled = not enabled
	check_call_btn.disabled = not enabled
	raise_btn.disabled = not enabled
	raise_amount.editable = enabled
	all_in_btn.disabled = not enabled


func _set_psych_buttons_enabled(enabled: bool) -> void:
	pressure_btn.disabled = not enabled
	excite_btn.disabled = not enabled


func _update_display() -> void:
	if not session:
		return
	
	# 玩家信息
	player_funds_label.text = "资金: $%d" % session.player_funds
	
	var player_hand_str := ""
	for card in session.player_hand:
		player_hand_str += card.get_display_name() + " "
	player_hand_label.text = "手牌: %s" % player_hand_str.strip_edges()
	
	if session.player_hand.size() >= 5:
		player_hand_type_label.text = session.get_player_hand_description()
	else:
		player_hand_type_label.text = ""
	
	# 底池信息
	pot_label.text = "$%d" % session.pot
	round_label.text = "第 %d 轮" % session.current_round
	to_call_label.text = "需跟注: $%d" % session.to_call
	
	# NPC信息
	npc_funds_label.text = "资金: $%d" % session.npc_funds
	npc_hand_label.text = "手牌: %s" % session.get_npc_visible_hand_description()
	npc_state_label.text = "心理: %s" % session.get_npc_psychological_state()
	
	# 更新加注滑块范围
	raise_amount.min_value = session.to_call + session.min_raise
	raise_amount.max_value = session.player_funds
	if raise_amount.value < raise_amount.min_value:
		raise_amount.value = raise_amount.min_value


func _log(message: String) -> void:
	log_text.append_text(message + "\n")
