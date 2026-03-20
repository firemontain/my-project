## CardData.gd
## 单张扑克牌的数据定义
class_name CardData
extends RefCounted

## 花色枚举
enum Suit {
	SPADE,      ## 黑桃 ♠
	HEART,      ## 红心 ♥
	DIAMOND,    ## 方块 ♦
	CLUB        ## 梅花 ♣
}

## 点数枚举（2-14，其中14代表A）
enum Rank {
	TWO = 2,
	THREE = 3,
	FOUR = 4,
	FIVE = 5,
	SIX = 6,
	SEVEN = 7,
	EIGHT = 8,
	NINE = 9,
	TEN = 10,
	JACK = 11,
	QUEEN = 12,
	KING = 13,
	ACE = 14
}

## 花色
var suit: Suit

## 点数
var rank: Rank

## 是否为暗牌（仅持有者可见）
var is_face_down: bool = false


## 初始化
func _init(p_suit: Suit = Suit.SPADE, p_rank: Rank = Rank.TWO) -> void:
	suit = p_suit
	rank = p_rank


## 获取卡牌唯一ID
func get_card_id() -> String:
	return "%d_%d" % [suit, rank]


## 获取显示名称
func get_display_name() -> String:
	var suit_names := ["♠", "♥", "♦", "♣"]
	var rank_names := ["", "", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
	return suit_names[suit] + rank_names[rank]


## 获取花色符号
func get_suit_symbol() -> String:
	var suit_symbols := ["♠", "♥", "♦", "♣"]
	return suit_symbols[suit]


## 获取点数显示
func get_rank_display() -> String:
	var rank_displays := ["", "", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
	return rank_displays[rank]


## 比较两张牌（按点数，再按花色）
## 返回正数表示a大于b，负数表示a小于b，0表示相等
static func compare(a: CardData, b: CardData) -> int:
	if a.rank != b.rank:
		return a.rank - b.rank
	return a.suit - b.suit
