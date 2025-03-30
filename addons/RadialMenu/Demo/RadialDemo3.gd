extends PanelContainer
"""
(c) 2021-2024 Pascal Schuppli

Demonstrates the use of the RadialMenu control.

This code is made available under the MIT license. See LICENSE for further
information.
"""

const TWODEE_TEXTURE = preload("icons/2D.svg")
const POINTS_TEXTURE = preload("icons/PointMesh.svg")
const GRID_TEXTURE = preload("icons/Grid.svg")
const ORIGIN_TEXTURE = preload("icons/CoordinateOrigin.svg")
const SCALE_TEXTURE = preload("icons/Zoom.svg")
const TOOL_TEXTURE = preload("icons/Tools.svg")

# Import the Radial Menu
const RadialMenu = preload("../RadialMenu.gd")


func create_submenu(parent_menu):
	# create a new radial menu
	var submenu = RadialMenu.new()
	# copy some important properties from the parent menu
	submenu.circle_coverage = 0.45
	submenu.width = parent_menu.width * 0.8
	submenu.show_animation = parent_menu.show_animation
	submenu.animation_speed_factor = parent_menu.animation_speed_factor
	return submenu


# Called when the node enters the scene tree for the first time.
func _ready():
	# Create a few dummy submenus.
	var submenu1 = create_submenu($Node/RadialMenu)
	var submenu2 = create_submenu($Node/RadialMenu)
	var submenu3 = create_submenu($Node/RadialMenu)
	var submenu4 = create_submenu($Node/RadialMenu)

	var submenu5 = create_submenu(submenu4)
	submenu4.add_icon_item(SCALE_TEXTURE, "Something else", submenu5)

	var submenu6 = create_submenu(submenu5)
	submenu5.add_icon_item(POINTS_TEXTURE, "Another", submenu6)

	# Define the main menu's items.
	(
		$Node/RadialMenu
		. set_items(
			[
				RadialMenu.RadialMenuItem.create(SCALE_TEXTURE, "Reset Scale", "action1"),
				RadialMenu.RadialMenuItem.create(TWODEE_TEXTURE, "Axis Setup", "submenu1"),
				RadialMenu.RadialMenuItem.create(POINTS_TEXTURE, "Dataset Setup", "submenu2"),
				RadialMenu.RadialMenuItem.create(GRID_TEXTURE, "Grid Setup", "submenu3"),
				RadialMenu.RadialMenuItem.create(TOOL_TEXTURE, "Advanced Tools", "submenu4"),
			] as Array[RadialMenu.RadialMenuItem]
		)
	)


func _input(event):
	if event is InputEventMouseButton:
		# open the menu
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_RIGHT:
			var m = get_local_mouse_position()
			$Node/RadialMenu.open_menu(m)
			get_viewport().set_input_as_handled()
	if Input.is_action_just_pressed("ui_cancel"):
		var m = get_window().size / 2
		$Node/RadialMenu.open_menu(m)
		get_viewport().set_input_as_handled()


func _on_ArcPopupMenu_item_selected(action, _position):
	$MenuResult.text = str(action) + " selected"


func _on_radial_menu_canceled() -> void:
	$MenuResult.text = "Nothing selected yet"
