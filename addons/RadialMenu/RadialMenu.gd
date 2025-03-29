@tool
@icon("res://addons/RadialMenu/icons/radial_menu.svg")
class_name RadialMenu
extends Control
"""
(c) 2021-2024 Pascal Schuppli

Radial Menu Control für Godot 4.3

This code is made available under the MIT license. See the LICENSE file for
further information.

Original Github Repository: https://github.com/jesuisse/godot-radial-menu-control
"""

## Signal is sent when an item is selected. Opening a submenu doesn't emit
## this signal; if you are interested in that, use the submenu's about_to_popup
## signal.
signal item_selected(id, position)
## Signal is sent when you hover over an item
signal item_hovered(item)
## Signal is sent when the menu is closed without anything being selected
signal canceled
## Signal is sent when the menu is opened. This happens *before* the opening animation starts
signal menu_opened(menu)
## Signal is sent when the menu is closed. This happens *before* the closing animation starts
signal menu_closed(menu)

const DEBUG = false

## This serves as a sane fallback for the themed constants etc the code refers to in case no theme
## is provided by the user. See _get_constant, _get_color, _get_font, _getfontsize for fallback logic.
const DEFAULT_THEME = preload("dark_default_theme.tres")

const JOY_DEADZONE := 0.2
const JOY_AXIS_RESCALE = 1.0 / (1.0 - JOY_DEADZONE)

# defines how long you have to wait before releasing a mouse button will
# close the menu.
const MOUSE_RELEASE_TIMEOUT: int = 400

# Name of the child node that is auto-generated by the code
const ITEM_ICONS_NAME = "ItemIcons"

const Draw = preload("drawing_library.gd")

enum Position {
	OFF,
	INSIDE,
	OUTSIDE,
}

## Defines the radius of the ring
@export var radius := 150:
	set = _set_radius
## Defines the menu ring width
@export var width := 50:
	set = _set_width
@export var center_radius := 20:
	set = _set_center_radius
@export_range(0, 30, 0.5) var gap_size := 3.0:
	set = _set_gap_size
@export var selector_position: Position = Position.INSIDE:
	set = _set_selector_position
@export var decorator_ring_position: Position = Position.INSIDE:
	set = _set_decorator_ring_position
## The percentage of a full circle that will be covered by the ring
@export_range(0.1, 1.0, 0.05) var circle_coverage := 0.65:
	set = _set_circle_coverage
## The angle where the center of the ring segment will be (if circle_coverage is less than 1) in radians
@export_range(0.0, 2 * PI, 0.01745) var center_angle := -PI / 2:
	set = _set_center_angle
## Make sure that if you set this to true, you provide a way to turn it off for the user, as this may
## slow down frequent users of your software.
@export var show_animation := false

@export_range(0.01, 1.0, 0.01) var animation_speed_factor := 0.2
## This defines how far outside the ring the mouse will still select a ring segment, as a
## as a multiplication factor of the radius.
@export_range(0, 10, 0.5) var outside_selection_factor := 3.0
## Scales the icons by this factor
@export var icon_scale := 1.0:
	set = _set_icon_scale
## Whether to display the item title in the center of the menu when one is selected
@export var show_titles := true:
	set = _set_titles_display
## Whether submenus should always inherit the theme
@export var submenu_inherit_theme := true

# default menu items. They are provided so a placeholder radial menu can be displayed in the editor
# even before it is configured via code.
var menu_items: Array = [
	{"texture": _get_texture("DefaultPlaceholder"), "title": "Item 1", "id": "arc_id1"},
	{"texture": _get_texture("DefaultPlaceholder"), "title": "Item 2", "id": "arc_id2"},
	{"texture": _get_texture("DefaultPlaceholder"), "title": "Item 3", "id": "arc_id3"},
	{"texture": _get_texture("DefaultPlaceholder"), "title": "Item 4", "id": "arc_id4"},
	{"texture": _get_texture("DefaultPlaceholder"), "title": "Item 5", "id": "arc_id5"},
	{"texture": _get_texture("DefaultPlaceholder"), "title": "Item 6", "id": "arc_id6"},
	{"texture": _get_texture("DefaultPlaceholder"), "title": "Item 7", "id": "arc_id7"},
]:
	set = set_items

# mostly used for animation
enum MenuState {
	CLOSED,
	OPENING,
	OPEN,
	MOVING,
	CLOSING,
}

# The following is internal state and should not be changed or accessed directly from outside the
# object, as it is subject to change without warning.

# for gamepad input. Use setup_gamepad to change these values.
var gamepad_device: int = 0
var gamepad_axis_x: int = 0
var gamepad_axis_y: int = 1
var gamepad_deadzone := JOY_DEADZONE

var item_angle: float = PI / 6:
	set = _set_item_angle

var tween: Tween

var is_ready := false
var _item_children_present := false
var has_left_center := false
## True for submenus
var is_submenu := false
## Currently selected menu item
var selected: int = -1
## State of the menu
var state := MenuState.CLOSED
## Offset of the arc center from top left
var center_offset := Vector2.ZERO
## Backup value for animation
var orig_item_angle: float = 0
## msecs since start when menu openeed
var msecs_at_opened: int = 0
## Where user has clicked
var opened_at_position: Vector2
## The actual center of the menu
var moved_to_position: Vector2
## The index of the current active submenu
var active_submenu_idx: int = -1
## The last selected submenu index, for detecting changes
var last_selected_submenu_idx: int = -1


func _set_radius(new_radius: int) -> void:
	radius = new_radius
	_calc_new_geometry()
	queue_redraw()


func _set_width(new_width: int) -> void:
	width = new_width
	_calc_new_geometry()
	queue_redraw()


func _set_center_radius(new_radius: int) -> void:
	center_radius = new_radius
	queue_redraw()


func _set_gap_size(new_gap_size: float) -> void:
	gap_size = new_gap_size
	# Note: We do not need to recalculate the ring geometry because the gaps
	# only exist visually; they do not influence anything else.
	queue_redraw()


func _set_selector_position(new_position: Position) -> void:
	selector_position = new_position
	_calc_new_geometry()
	queue_redraw()


func _set_icon_scale(new_scale: float) -> void:
	icon_scale = new_scale
	_update_item_icons()
	queue_redraw()


func _set_titles_display(new_display: bool) -> void:
	show_titles = new_display
	queue_redraw()


func _set_item_angle(new_angle: float) -> void:
	item_angle = new_angle
	_calc_new_geometry()
	queue_redraw()


func _set_circle_coverage(new_coverage: float) -> void:
	item_angle = new_coverage * 2 * PI / menu_items.size()
	circle_coverage = new_coverage
	_calc_new_geometry()
	queue_redraw()


func _set_center_angle(new_angle: float) -> void:
	item_angle = circle_coverage * 2 * PI / menu_items.size()
	center_angle = new_angle
	_calc_new_geometry()
	queue_redraw()


func _set_decorator_ring_position(new_pos: Position) -> void:
	decorator_ring_position = new_pos
	_calc_new_geometry()
	queue_redraw()


func _calc_new_geometry() -> void:
	var n := menu_items.size()
	var angle := circle_coverage * 2.0 * PI / menu_items.size()
	var sa := center_angle - 0.5 * n * angle
	var aabb := Draw.calc_ring_segment_AABB(
		radius - get_total_ring_width(), radius, sa, sa + n * angle
	)
	custom_minimum_size = aabb.size
	size = custom_minimum_size
	pivot_offset = -aabb.position
	center_offset = -aabb.position
	_update_item_icons()


# Creates necessary child nodes of the radial menu
func _create_subtree() -> void:
	if not get_node_or_null(ITEM_ICONS_NAME):
		var item_icons := Control.new()
		item_icons.name = ITEM_ICONS_NAME
		add_child(item_icons)


func _ready() -> void:
	hide()
	is_ready = true
	_create_subtree()
	item_angle = circle_coverage * 2.0 * PI / menu_items.size()
	if not is_submenu:
		# (submenus get their signals connected and disconnected elsewhere)
		connect("visibility_changed", Callable(self, "_on_visibility_changed"))
	_register_menu_child_nodes()
	_calc_new_geometry()
	size_flags_horizontal = 0
	size_flags_vertical = 0


func _input(event: InputEvent) -> void:
	_radial_input(event)


func _radial_input(event: InputEvent) -> void:
	if not visible:
		return
	if state == MenuState.OPENING or state == MenuState.CLOSING:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		set_selected_item(get_selected_by_mouse())
		redraw_if_submenu_selection_changed()
	elif event is InputEventJoypadMotion:
		set_selected_item(get_selected_by_joypad())
		redraw_if_submenu_selection_changed()
		return

	if has_open_submenu():
		return

	if event is InputEventMouseButton:
		_handle_mouse_buttons(event)
	else:
		_handle_actions(event)


func is_wheel_button(event: InputEventMouseButton) -> bool:
	return (
		event.button_index
		in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT,
			MOUSE_BUTTON_WHEEL_RIGHT
		]
	)


func _handle_mouse_buttons(event: InputEventMouseButton) -> void:
	if event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_next()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_prev()
		else:
			if not is_submenu:
				get_viewport().set_input_as_handled()
			activate_selected()
	elif state == MenuState.OPEN and not is_wheel_button(event):
		var msecs_since_opened: int = Time.get_ticks_msec() - msecs_at_opened
		if msecs_since_opened > MOUSE_RELEASE_TIMEOUT:
			get_viewport().set_input_as_handled()
			activate_selected()


func _handle_actions(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		selected = -1
		activate_selected()
	elif (
		event.is_action_pressed("ui_down")
		or event.is_action_pressed("ui_right")
		or event.is_action_pressed("ui_focus_next")
	):
		select_next()
		get_viewport().set_input_as_handled()
	elif (
		event.is_action_pressed("ui_up")
		or event.is_action_pressed("ui_left")
		or event.is_action_pressed("ui_focus_prev")
	):
		select_prev()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		activate_selected()


func _calc_segment(inner: float, outer: float, start: float, end: float) -> PackedVector2Array:
	# We switch to a no-gap version of the polygon calculation for narrow segments
	# (heuristic: less than about 10 degrees) because the faux (gap-enabled) ring
	# segment calculation will return invalid polygons when the segments get too
	# narrow.
	if absf(end - start) < 0.2 or gap_size == 0:
		# the version without gaps between segments
		return Draw.calc_ring_segment(inner, outer, start, end, center_offset)
	else:
		# the version with gaps between segments
		return Draw.calc_faux_ring_segment(inner, outer, gap_size, start, end, center_offset)


func _draw() -> void:
	var count := menu_items.size()
	if item_angle * count > 2 * PI:
		item_angle = 2 * PI / count

	var start_angle: float = center_angle - item_angle * (count / 2.0)

	var inout := get_inner_outer()
	var inner := inout[0]
	var outer := inout[1]

	var sw := _get_constant("StrokeWidth")

	# Draw the background for each menu item
	for i in range(count):
		var coords := _calc_segment(
			inner, outer, start_angle + i * item_angle, start_angle + (i + 1) * item_angle
		)
		if i == selected:
			Draw.draw_ring_segment(
				self,
				coords,
				_get_color("SelectedBackground"),
				_get_color("SelectedStroke"),
				sw,
				true
			)
		else:
			Draw.draw_ring_segment(
				self, coords, _get_color("Background"), _get_color("Stroke"), sw, true
			)

	var rw := _get_constant("DecoratorRingWidth")
	var ring_bg := _get_color("RingBackground")
	for i in range(count):
		# draw decorator ring segment
		if decorator_ring_position == Position.OUTSIDE:
			#var coords = Draw.calc_ring_segment(outer, outer + rw, start_angle, start_angle+count*item_angle, center_offset)
			var coords := _calc_segment(
				outer, outer + rw, start_angle + i * item_angle, start_angle + (i + 1) * item_angle
			)
			Draw.draw_ring_segment(self, coords, ring_bg, ring_bg, 1, true)
		elif decorator_ring_position == Position.INSIDE:
			#var coords = Draw.calc_ring_segment(inner-rw, inner, start_angle, start_angle+count*item_angle, center_offset)
			var coords := _calc_segment(
				inner, inner - rw, start_angle + i * item_angle, start_angle + (i + 1) * item_angle
			)
			Draw.draw_ring_segment(self, coords, ring_bg, ring_bg, 1, true)

	# draw selection ring segment
	if selected != -1 and not has_open_submenu():
		var selector_size := _get_constant("SelectorSegmentWidth")
		var select_coords: PackedVector2Array
		if selector_position == Position.OUTSIDE:
			# TODO: Likely we need to swap the inner and outer radius here!
			select_coords = _calc_segment(
				outer,
				outer + selector_size,
				start_angle + selected * item_angle,
				start_angle + (selected + 1) * item_angle
			)
			Draw.draw_ring_segment(
				self,
				select_coords,
				_get_color("SelectorSegment"),
				_get_color("SelectorSegment"),
				1,
				true
			)
		elif selector_position == Position.INSIDE:
			# TODO: Likely we need to swap the inner and outer radius here!
			select_coords = _calc_segment(
				inner - selector_size,
				inner,
				start_angle + selected * item_angle,
				start_angle + (selected + 1) * item_angle
			)
			Draw.draw_ring_segment(
				self,
				select_coords,
				_get_color("SelectorSegment"),
				_get_color("SelectorSegment"),
				1,
				true
			)

	if center_radius != 0:
		_draw_center()

	if DEBUG:
		_debug_draw()


func _draw_center() -> void:
	if not is_submenu and center_radius > 0:
		_draw_center_ring()

	if (
		show_titles
		and (not has_open_submenu() or get_open_submenu().selected == -1)
		and not state == MenuState.CLOSING
	):
		_draw_label()


func _draw_center_ring():
	var bg := _get_color("CenterBackground")
	var fg := _get_color("CenterStroke")
	if selected == -1:
		fg = _get_color("SelectorSegment")

	draw_circle(center_offset, center_radius, bg)
	draw_arc(center_offset, center_radius, 0, 2 * PI, center_radius, fg, 2, true)

	if not show_titles or selected == -1:
		var tex := _get_texture("Close")
		#if active_submenu_idx != -1:
		#	tex = BACK_TEXTURE
		draw_texture(tex, center_offset - tex.get_size() / 2, _get_color("IconModulation"))


func _draw_label() -> void:
	var text: String
	if selected == -1:
		return
	text = menu_items[selected]["title"]
	var font := _get_font("TitleFont")
	var fontsize := _get_fontsize("TitleFont")
	var color := _get_color("TitleDisplay")
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fontsize)
	if center_radius > size.x / 2.0:
		# show text if it fits inside the center ring
		var pos := center_offset - Vector2(size.x / 2.0, -font.get_descent())
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, fontsize, color)
	else:
		# otherwise, draw "..." instead
		size = font.get_string_size("...", HORIZONTAL_ALIGNMENT_CENTER, -1, fontsize)
		var pos := center_offset - Vector2(size.x / 2.0, -font.get_descent())
		draw_string(font, pos, "...", HORIZONTAL_ALIGNMENT_CENTER, -1, fontsize, color)


func _debug_draw() -> void:
	var font := _get_font("TitleFont")
	var fontsize := _get_fontsize("TitleFont")
	draw_string(font, Vector2(0, 40), str(selected), 0, 0, fontsize)


func setup_gamepad(deviceid: int, xaxis: int, yaxis: int, deadzone: float = JOY_DEADZONE) -> void:
	gamepad_device = deviceid
	gamepad_axis_x = xaxis
	gamepad_axis_y = yaxis
	gamepad_deadzone = deadzone


## Returns the index of the menu item that is currently selected by the mouse
## (or -1 when nothing is selected)
func get_selected_by_mouse() -> int:
	if has_open_submenu():
		if get_open_submenu().get_selected_by_mouse() != -1:
			# we don't change the selection while a submenu has a valid selection
			return active_submenu_idx

	var s := selected
	var mpos := get_local_mouse_position() - center_offset
	var lsq := mpos.length_squared()
	var inner_limit: int = mini((radius - width) * (radius - width), 400)
	var outer_limit := (
		(radius + width * outside_selection_factor) * (radius + width * outside_selection_factor)
	)
	if is_submenu:
		inner_limit = pow(get_inner_outer()[0], 2)
	# make selection ring wider than the actual ring of items
	if lsq < inner_limit or lsq > outer_limit:
		# being outside the selection limit only cancels your selection if you've
		# moved the mouse outside since having made the selection...
		if has_left_center:
			s = -1
	else:
		has_left_center = true
		s = get_itemindex_from_vector(mpos)
	return s


## Returns the index that would be selected by the joystick direction
func get_selected_by_joypad() -> int:
	if has_open_submenu():
		return active_submenu_idx

	var xAxis := Input.get_joy_axis(gamepad_device, gamepad_axis_x)
	var yAxis := Input.get_joy_axis(gamepad_device, gamepad_axis_y)
	if absf(xAxis) > gamepad_deadzone:
		if xAxis > 0:
			xAxis = (xAxis - gamepad_deadzone) * JOY_AXIS_RESCALE
		else:
			xAxis = (xAxis + gamepad_deadzone) * JOY_AXIS_RESCALE
	else:
		xAxis = 0
	if absf(yAxis) > gamepad_deadzone:
		if yAxis > 0:
			yAxis = (yAxis - gamepad_deadzone) * JOY_AXIS_RESCALE
		else:
			yAxis = (yAxis + gamepad_deadzone) * JOY_AXIS_RESCALE
	else:
		yAxis = 0

	var jpos := Vector2(xAxis, yAxis)
	var s := selected
	if jpos.length_squared() > 0.36:
		has_left_center = true
		s = get_itemindex_from_vector(jpos)
		if s == -1:
			s = selected
	return s


## Determines whether the current menu has a submenu open
func has_open_submenu() -> bool:
	return active_submenu_idx != -1


## Returns the submenu node if one is open, or null
func get_open_submenu() -> RadialMenu:
	if active_submenu_idx != -1:
		return menu_items[active_submenu_idx].id
	else:
		return null


## Check if the submenu selection has changed, and if so queue a redraw
func redraw_if_submenu_selection_changed() -> void:
	# This is taking care of problems with the title display in the center
	# when the submenu selection has changed
	if has_open_submenu():
		var sub_sel = get_open_submenu().selected
		if sub_sel != last_selected_submenu_idx:
			queue_redraw()
			last_selected_submenu_idx = sub_sel


## Selects the next item in the menu (clockwise)
func select_next() -> void:
	var n = menu_items.size()
	if 2 * PI - n * item_angle < 0.01 or selected < n - 1:
		set_selected_item((selected + 1) % n)
		has_left_center = false


## Selects the previous item in the menu (clockwise)
func select_prev() -> void:
	var n = menu_items.size()
	if 2 * PI - n * item_angle < 0.01 or selected > 0:
		set_selected_item(int(fposmod(selected - 1, n)))
		has_left_center = false


## Opens a submenu or closes the menu and signals an id, depending on what
## was selected
func activate_selected() -> void:
	if selected != -1 and menu_items[selected].id is Control:
		open_submenu(menu_items[selected].id, selected)
	else:
		close_menu()
		signal_id()


func _connect_submenu_signals(submenu) -> void:
	submenu.connect("visibility_changed", Callable(submenu, "_on_visibility_changed"))
	submenu.connect("item_selected", Callable(self, "_on_submenu_item_selected"))
	submenu.connect("item_hovered", Callable(self, "_on_submenu_item_hovered"))
	submenu.connect("canceled", Callable(self, "_on_submenu_cancelled"))


func _disconnect_submenu_signals(submenu) -> void:
	submenu.disconnect("visibility_changed", Callable(submenu, "_on_visibility_changed"))
	submenu.disconnect("item_selected", Callable(self, "_on_submenu_item_selected"))
	submenu.disconnect("item_hovered", Callable(self, "_on_submenu_item_hovered"))
	submenu.disconnect("canceled", Callable(self, "_on_submenu_cancelled"))


func _clear_item_icons() -> void:
	var p = $ItemIcons
	if not p:
		return
	for node in p.get_children():
		p.remove_child(node)
		node.queue_free()
	_item_children_present = false


func _register_menu_child_nodes() -> void:
	for item in get_children():
		if item.name == ITEM_ICONS_NAME:
			continue
		# do something with the others


func _create_item_icons() -> void:
	if not is_ready:
		return
	_clear_item_icons()
	var n = menu_items.size()
	if n == 0:
		return
	var start_angle = center_angle - item_angle * (n >> 1)
	var half_angle
	if n % 2 == 0:
		half_angle = item_angle / 2.0
	else:
		half_angle = 0

	var r = get_icon_radius()

	var coords = Draw.calc_ring_segment_centers(
		r, n, start_angle + half_angle, start_angle + half_angle + n * item_angle, center_offset
	)
	for i in range(n):
		var item = menu_items[i]
		if item != null:
			var sprite = Sprite2D.new()
			sprite.position = coords[i]
			sprite.centered = true
			sprite.texture = item.texture
			sprite.scale = Vector2(icon_scale, icon_scale)
			sprite.modulate = _get_color("IconModulation")
			$ItemIcons.add_child(sprite)
	_item_children_present = true


func _update_item_icons() -> void:
	if not _item_children_present:
		_create_item_icons()
		return
	var r = get_icon_radius()
	var n = menu_items.size()
	var start_angle = center_angle - item_angle * n * 0.5 + item_angle * 0.5

	# a heuristic - hide icons when they tend to outgrow their segment
	if item_angle < 0.01 or r * (item_angle / 2 * PI) < width * icon_scale:
		$ItemIcons.hide()
	else:
		$ItemIcons.show()

	var coords = Draw.calc_ring_segment_centers(
		r, n, start_angle, start_angle + n * item_angle, center_offset
	)
	var i = 0
	var ni = 0
	var item_nodes = $ItemIcons.get_children()
	while i < n:
		var item = menu_items[i]
		if item != null:
			var sprite = item_nodes[ni]
			ni += 1
			sprite.position = coords[i]
			sprite.scale = Vector2(icon_scale, icon_scale)
			sprite.modulate = _get_color("IconModulation")
		i = i + 1


## Returns the inner and outer radius of the item ring (without selector
## and decorator)
func get_inner_outer() -> Vector2:
	var inner
	var outer
	var drw = 0
	if decorator_ring_position == Position.OUTSIDE:
		drw = _get_constant("DecoratorRingWidth")

	if selector_position == Position.OUTSIDE:
		var w = max(drw, _get_constant("SelectorSegmentWidth"))
		inner = radius - w - width
		outer = radius - w
	else:
		inner = radius - drw - width
		outer = radius - drw
	return Vector2(inner, outer)


## Returns the total width of the ring (with decorator and selector)
func get_total_ring_width() -> int:
	var dw = _get_constant("DecoratorRingWidth")
	var sw = _get_constant("SelectorSegmentWidth")
	if decorator_ring_position == selector_position:
		if decorator_ring_position == Position.OFF:
			return width
		else:
			return width + max(sw, dw)
	elif decorator_ring_position == Position.OFF:
		return width + sw
	elif selector_position == Position.OFF:
		return width + dw
	else:
		return width + sw + dw


## Gets the radius at which the item icons are centered
func get_icon_radius() -> float:
	var so_width = 0
	var dr_width = 0
	if selector_position == Position.OUTSIDE:
		so_width = _get_constant("SelectorSegmentWidth")
	if decorator_ring_position == Position.OUTSIDE:
		dr_width = _get_constant("DecoratorRingWidth")
	return radius - width / 2.0 - max(so_width, dr_width)


## Gets theme color (or takes it from default theme)
func _get_color(name) -> Color:
	if has_theme_color(name, "RadialMenu"):
		return get_theme_color(name, "RadialMenu")
	else:
		return DEFAULT_THEME.get_color(name, "RadialMenu")


## Gets theme constant (or takes it from default theme)
func _get_constant(name) -> int:
	if has_theme_constant(name, "RadialMenu"):
		return get_theme_constant(name, "RadialMenu")
	else:
		return DEFAULT_THEME.get_constant(name, "RadialMenu")


## Gets theme font (or takes it from default theme)
func _get_font(name) -> Font:
	if has_theme_font(name, "RadialMenu"):
		return get_theme_font(name, "RadialMenu")
	else:
		return DEFAULT_THEME.get_font(name, "RadialMenu")


## Gets theme font size (or takes it from default theme)
func _get_fontsize(name) -> int:
	if has_theme_font_size(name, "RadialMenu"):
		return get_theme_font_size(name, "RadialMenu")
	else:
		return DEFAULT_THEME.get_font_size(name, "RadialMenu")


## Gets theme texture (or takes it from default theme)
func _get_texture(name) -> Texture2D:
	if has_theme_icon(name, "RadialMenu"):
		return get_theme_icon(name, "RadialMenu")
	else:
		return DEFAULT_THEME.get_icon(name, "RadialMenu")


## Clears all items from the ring
func _clear_items() -> void:
	var n = $ItemIcons
	if not n:
		return
	for node in n.get_children():
		n.remove_child(node)
		node.queue_free()


func set_tween(property, final_value) -> void:
	tween = create_tween()
	tween.connect("finished", Callable(self, "_on_Tween_tween_all_completed"))
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, property, final_value, animation_speed_factor)


## Given a vector that originates in the center of the radial menu,
## this will return the index of the menu item that lies along that
## vector.
func get_itemindex_from_vector(v: Vector2) -> int:
	var n = menu_items.size()
	var start_angle = center_angle - item_angle * n / 2.0
	var end_angle = start_angle + n * item_angle

	var angle = v.angle_to(Vector2(cos(start_angle), sin(start_angle)))
	if angle < 0:
		angle = -angle
	else:
		angle = 2 * PI - angle
	var section = end_angle - start_angle  # wrap around bug?

	var idx = int(fmod(angle / section, n) * n)
	if idx >= n:
		return -1
	else:
		return idx


func set_selected_item(itemidx) -> void:
	if selected == itemidx:
		return

	selected = itemidx
	if selected != -1:
		emit_signal("item_hovered", menu_items[selected])

	queue_redraw()


## Opens the menu at the given position.
func open_menu(center_position: Vector2) -> void:
	position.x = center_position.x - center_offset.x
	position.y = center_position.y - center_offset.y
	item_angle = circle_coverage * 2 * PI / menu_items.size()
	_calc_new_geometry()
	_about_to_popup()
	show()

	moved_to_position = position + center_offset


## Closes the menu and animates if needed
func close_menu() -> void:
	if state != MenuState.OPEN:
		return
	has_left_center = false
	if not show_animation:
		state = MenuState.CLOSED
		hide()
		if is_submenu:
			get_parent().remove_child(self)
		is_submenu = false
	else:
		state = MenuState.CLOSING
		orig_item_angle = item_angle
		set_tween("item_angle", 0.01)
	emit_signal("menu_closed", self)


## Opens the specified submenu
func open_submenu(submenu: RadialMenu, idx: int) -> void:
	active_submenu_idx = idx
	last_selected_submenu_idx = -1
	queue_redraw()

	var ring_width := submenu.get_total_ring_width()

	submenu.decorator_ring_position = decorator_ring_position
	submenu.center_angle = (
		center_angle - (menu_items.size() / 2.0 * item_angle) + idx * item_angle + item_angle / 2.0
	)
	submenu.radius = radius + ring_width + gap_size * 2
	submenu.center_radius = center_radius  # submenu needs this to determine whether to draw labels
	submenu.is_submenu = true
	submenu.position = moved_to_position - submenu.center_offset
	if theme and submenu_inherit_theme:
		submenu.theme = theme

	get_parent().add_child(submenu)
	_connect_submenu_signals(submenu)

	# now make sure we have room to display the menu
	var move := calc_move_to_fit(submenu)
	if move == Vector2.ZERO:
		submenu.open_menu(moved_to_position)
		return

	if show_animation:
		state = MenuState.MOVING
		set_tween("position", position + move)
	else:
		moved_to_position += move
		position = moved_to_position - center_offset
		queue_redraw()
		submenu.open_menu(moved_to_position)


func calc_move_to_fit(submenu: RadialMenu) -> Vector2:
	var parent_size := get_parent_area_size()
	var parent_rect := Rect2(Vector2.ZERO, parent_size)
	var sub_rect := submenu.get_rect()
	if not parent_rect.encloses(sub_rect):
		var dx: int = 0
		var dy: int = 0
		if sub_rect.position.x + sub_rect.size.x > parent_size.x:
			dx = parent_size.x - sub_rect.position.x - sub_rect.size.x
		elif sub_rect.position.x < 0:
			dx = -sub_rect.position.x
		if sub_rect.position.y + sub_rect.size.y > parent_size.y:
			dy = parent_size.y - sub_rect.position.y - sub_rect.size.y
		elif sub_rect.position.y < 0:
			dy = -sub_rect.position.y
		return Vector2(dx, dy)
	else:
		return Vector2.ZERO


func _on_Tween_tween_all_completed() -> void:
	if state == MenuState.CLOSING:
		state = MenuState.CLOSED
		hide()
		item_angle = circle_coverage * 2 * PI / menu_items.size()
		_calc_new_geometry()
		queue_redraw()
		if is_submenu:
			get_parent().remove_child(self)
			is_submenu = false
	elif state == MenuState.OPENING:
		state = MenuState.OPEN
		item_angle = circle_coverage * 2 * PI / menu_items.size()
		_calc_new_geometry()
		queue_redraw()
	elif state == MenuState.MOVING:
		state = MenuState.OPEN
		moved_to_position = position + center_offset
		menu_items[active_submenu_idx].id.open_menu(moved_to_position)


## Emits either an 'item_selected' or 'canceled' signal
func signal_id() -> void:
	if selected != -1 and menu_items[selected] != null:
		emit_signal("item_selected", menu_items[selected].id, opened_at_position)
	elif selected == -1:
		emit_signal("canceled")


## Changes the menu items. Expects a list of 3-item dictionaries with the
## keys 'texture', 'title' and 'id'.[br]
## The value for the id can be anything you wish. If it is a RadialMenu,
## it will be treated as a submenu.
func set_items(items: Array) -> void:
	_clear_items()
	menu_items = items
	_create_item_icons()
	#create_expand_icons()
	if visible:
		queue_redraw()


## Adds a menu item.[br]
## If [param id] is a [RadialMenu] object, it will be treated as
## a submenu.
func add_icon_item(texture: Texture2D, title: String, id: Variant) -> void:
	var entry = {"texture": texture, "title": title, "id": id}
	menu_items.push_back(entry)
	_create_item_icons()
	if visible:
		queue_redraw()


## Sets the title text of a menu item.
func set_item_text(idx: int, text: String) -> void:
	if idx < menu_items.size():
		menu_items[idx].title = text
		_update_item_icons()
	else:
		print_debug("Invalid index {} in set_item_text" % idx)


## Sets the id of a menu item.
## If [param id] is a [RadialMenu] object, it will be treated as
## a submenu.
func set_item_id(idx: int, id: Variant) -> void:
	if idx < menu_items.size():
		menu_items[idx].id = id
		_update_item_icons()
	else:
		print_debug("Invalid index {} in set_item_id" % idx)


## Sets the icon of a menu item.
func set_item_icon(idx: int, texture: Texture2D) -> void:
	if idx < menu_items.size():
		menu_items[idx].texture = texture
		_update_item_icons()
	else:
		print_debug("Invalid index {} in set_item_texture" % idx)


## Called before showing the menu
func _about_to_popup() -> void:
	selected = -1
	msecs_at_opened = Time.get_ticks_msec()
	opened_at_position = Vector2(offset_left + center_offset.x, offset_top + center_offset.y)
	emit_signal("menu_opened", self)
	if show_animation:
		orig_item_angle = item_angle
		item_angle = 0.01
		_calc_new_geometry()
		queue_redraw()


## Called when menu visibility changes
func _on_visibility_changed() -> void:
	if not visible:
		state = MenuState.CLOSED
	elif show_animation and state == MenuState.CLOSED:
		state = MenuState.OPENING
		set_tween("item_angle", orig_item_angle)
	else:
		state = MenuState.OPEN


## Called when a submenu has an item selected
func _on_submenu_item_selected(id, position) -> void:
	var submenu := get_open_submenu()
	_disconnect_submenu_signals(submenu)
	active_submenu_idx = -1
	close_menu()
	emit_signal("item_selected", id, opened_at_position)


## Called when a submenu item is hovered
func _on_submenu_item_hovered(_item) -> void:
	set_selected_item(active_submenu_idx)


## Called when a submenu closes
func _on_submenu_cancelled() -> void:
	var submenu := get_open_submenu()
	_disconnect_submenu_signals(submenu)
	set_selected_item(get_selected_by_mouse())
	if selected == -1 or selected == active_submenu_idx:
		get_viewport().set_input_as_handled()
	active_submenu_idx = -1
	queue_redraw()
