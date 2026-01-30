extends Node2D

@onready var character: Node2D = $"../Pokemon"
@onready var popup: Panel = $"Selector Window/UI/Panel"
@onready var character_grid: GridContainer = $"Selector Window/UI/Panel/GridPopup/PanelContainer/GridContainer"

var selected_name := ""

func _ready() -> void:
	popup.hide()

	_connect_buttons()

	if selected_name == "" and character_grid.get_child_count() > 0:
		var first_button := _find_first_button(character_grid)
		if first_button != null:
			_on_character_button_pressed(first_button)
			print("Preselected character: %s" % selected_name)
	
	character.set_character_by_name(selected_name)
	

func _connect_buttons() -> void:
	_connect_buttons_recursive(character_grid)


func _connect_buttons_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is TextureButton:
			if not child.pressed.is_connected(_on_character_button_pressed):
				child.pressed.connect(_on_character_button_pressed.bind(child))
				print("Connected button: %s" % child.name)

		_connect_buttons_recursive(child)


func _find_first_button(node: Node) -> TextureButton:
	for child in node.get_children():
		if child is TextureButton:
			return child
		var nested := _find_first_button(child)
		if nested != null:
			return nested
	return null

func _on_character_button_pressed(button: TextureButton) -> void:

	selected_name = button.name
	print("Selected character: %s" % selected_name)

	_on_select_button_pressed()
	popup.hide()


func _on_select_button_pressed() -> void:
	if selected_name != "":
		character.set_character_by_name(selected_name)
	popup.hide()
