extends Node2D

@onready var character: Node2D = $"../Pokemon"
@onready var popup: PopupPanel = $"Selector Window/UI/Selector Popup"
@onready var text_feild: LineEdit = $"Selector Window/UI/Selector Popup/VBoxContainer/Text Feild"


func _ready() -> void:
	set_curent_character()


func _on_select_button_pressed() -> void:
	set_curent_character()
	popup.hide()


func get_character_name() -> String:
	return text_feild.text


func set_curent_character() -> void:
	character.set_character_by_name(get_character_name())
