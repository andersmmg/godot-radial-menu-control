extends Object

"""
(c) 2021-2024 by Pascal Schuppli

This code is licensed under the MIT license. See LICENSE file for details.
"""

const RAD_360 := 2 * PI
const RAD_270 := 1.5 * PI
const RAD_180 := PI
const RAD_90 := 0.5 * PI


## Calculates [param npoints] coordinates on a circle with a given [param radius].[br]
## The first point lies at 3 o'clock unless you specify an [param angle_offset]
## (in radians)
static func calc_circle_coordinates(
	radius: float, npoints: int, angle_offset: float = 0, offset := Vector2.ZERO
) -> PackedVector2Array:
	var coords := PackedVector2Array()
	var angle := RAD_360 / npoints
	for i in range(npoints):
		var y := radius * sin(angle_offset + i * angle)
		var x := radius * cos(angle_offset + i * angle)
		coords.append(Vector2(x, y) + offset)
	return coords


## Calculates the axis-aligned bounding box of the arc defined by the parameters.
static func calc_arc_AABB(
	radius: float, start_angle: float, end_angle: float, center := Vector2.ZERO
) -> Rect2:
	if end_angle - start_angle > RAD_360 - 0.0001:
		return Rect2(center.x - radius, center.y - radius, 2 * radius, 2 * radius)
	start_angle = fposmod(start_angle, RAD_360)
	end_angle = fposmod(end_angle, RAD_360)

	var ps := Vector2(radius * cos(start_angle), radius * sin(start_angle))
	var pe := Vector2(radius * cos(end_angle), radius * sin(end_angle))

	var minx: float = 0
	var maxx: float = 0
	var miny: float = 0
	var maxy: float = 0

	if fposmod(start_angle - RAD_90, RAD_360) > fposmod(end_angle - RAD_90, RAD_360):
		maxy = radius
	if fposmod(start_angle - RAD_180, RAD_360) > fposmod(end_angle - RAD_180, RAD_360):
		minx = -radius
	if fposmod(start_angle - RAD_270, RAD_360) > fposmod(end_angle - RAD_270, RAD_360):
		miny = -radius
	if start_angle > end_angle:
		maxx = radius

	if minx == 0:
		minx = minf(ps.x, pe.x)
	if maxx == 0:
		maxx = maxf(ps.x, pe.x)
	if miny == 0:
		miny = minf(ps.y, pe.y)
	if maxy == 0:
		maxy = maxf(ps.y, pe.y)

	return Rect2(minx + center.x, miny + center.y, maxx - minx, maxy - miny)


## Calculates the coordinates of a ring segment
static func calc_ring_segment(
	inner_radius: float,
	outer_radius: float,
	start_angle: float,
	end_angle: float,
	offset := Vector2.ZERO
) -> PackedVector2Array:
	var coords := PackedVector2Array()
	var fraction_of_full := (end_angle - start_angle) / RAD_360
	var nopoints: int = maxi(2, int(outer_radius * fraction_of_full))
	var nipoints: int = maxi(2, int(inner_radius * fraction_of_full))
	var angle := (end_angle - start_angle) / nopoints
	for i in range(nopoints + 1):
		var y := outer_radius * sin(start_angle + i * angle)
		var x := outer_radius * cos(start_angle + i * angle)
		coords.append(Vector2(x, y) + offset)
	angle = (end_angle - start_angle) / nipoints
	for i in range(nipoints + 1):
		var y := inner_radius * sin(end_angle - i * angle)
		var x := inner_radius * cos(end_angle - i * angle)
		coords.append(Vector2(x, y) + offset)
	return coords


static func calc_ring_segment_centers(
	radius: float,
	n_points: int,
	start_angle: float,
	end_angle: float,
	offset := Vector2.ZERO,
	last_included := false
) -> PackedVector2Array:
	var coords := PackedVector2Array()
	var angle: float
	if last_included:
		angle = (end_angle - start_angle) / (n_points - 1)
	else:
		angle = (end_angle - start_angle) / n_points
	for i in range(n_points):
		var y := radius * sin(start_angle + i * angle)
		var x := radius * cos(start_angle + i * angle)
		coords.append(Vector2(x, y) + offset)
	return coords


## Calculates the axis-aligned bounding box of a ring segment
static func calc_ring_segment_AABB(
	inner: float, outer: float, start_angle: float, end_angle: float, center := Vector2.ZERO
) -> Rect2:
	var i_aabb := calc_arc_AABB(inner, start_angle, end_angle, center)
	var o_aabb := calc_arc_AABB(outer, start_angle, end_angle, center)
	return i_aabb.merge(o_aabb)


## Draws a segment of a ring. The ring coordinates must be passed in; they can be
## generated with calc_ring_segment.[br][br]
## If fill_color is null, only the segment's outline will be drawn. If stroke_color
## is null, no border outline will be drawn.
static func draw_ring_segment(
	canvas: CanvasItem,
	coords: PackedVector2Array,
	fill_color: Color,
	stroke_color := Color.TRANSPARENT,
	width: float = 1.0,
	antialiased := true
) -> void:
	if coords.size() == 0:
		return
	if fill_color:
		canvas.draw_colored_polygon(coords, fill_color, PackedVector2Array(), null)
	if not stroke_color == Color.TRANSPARENT:
		canvas.draw_polyline(coords, stroke_color, width, antialiased)
		canvas.draw_line(coords[-1], coords[0], stroke_color, width, antialiased)


## Draws a ring.[br][br]
## Caveat: If you draw an antialiased ring with a partially transparent fill_color
## without a stroke, you will get an ugly seam where the polygon joins
## itself.
static func draw_ring(
	canvas: CanvasItem,
	inner_radius: float,
	outer_radius: float,
	fill_color: Color,
	stroke_color := Color.TRANSPARENT,
	width: float = 1.0,
	antialiased := true,
	offset := Vector2.ZERO
) -> void:
	var coords_inner: PackedVector2Array
	var coords_outer: PackedVector2Array
	if not stroke_color == Color.TRANSPARENT:
		coords_inner = PackedVector2Array()
		coords_outer = PackedVector2Array()
	var coords_all := PackedVector2Array()
	var nopoints := maxi(2, int(outer_radius))
	var nipoints := maxi(2, int(inner_radius))
	var full360 := 2 * PI
	var angle: float = full360 / nopoints
	for i in range(nopoints + 1):
		var y := outer_radius * sin(i * angle)
		var x := outer_radius * cos(i * angle)
		var v := Vector2(x, y)
		if stroke_color:
			coords_outer.append(v + offset)
		coords_all.append(v + offset)

	angle = full360 / nipoints
	for i in range(nipoints + 1):
		var y := inner_radius * sin(full360 - i * angle)
		var x := inner_radius * cos(full360 - i * angle)
		var v := Vector2(x, y)
		if not stroke_color == Color.TRANSPARENT:
			coords_inner.append(v + offset)
		coords_all.append(v + offset)

	if not stroke_color == Color.TRANSPARENT:
		canvas.draw_colored_polygon(coords_all, fill_color, PackedVector2Array(), null)
	else:
		canvas.draw_colored_polygon(coords_all, fill_color, PackedVector2Array(), null)
	if not stroke_color == Color.TRANSPARENT:
		canvas.draw_polyline(coords_inner, stroke_color, width, antialiased)
		canvas.draw_polyline(coords_outer, stroke_color, width, antialiased)


static func calc_faux_ring_segment(
	inner_radius: float,
	outer_radius: float,
	separation: float,
	start_angle: float,
	end_angle: float,
	offset := Vector2.ZERO
) -> PackedVector2Array:
	var sep_inner_angle := asin(separation / inner_radius)
	var sep_outer_angle := asin(separation / outer_radius)

	# this limits the gap to avoid creating very strange-looking
	# gaps or invalid polygons
	if sep_inner_angle > 0.18 * (end_angle - start_angle):
		sep_inner_angle = 0.18 * (end_angle - start_angle)
	if sep_outer_angle > 0.18 * (end_angle - start_angle):
		sep_outer_angle = 0.18 * (end_angle - start_angle)

	var inner_start := start_angle + sep_inner_angle
	var inner_end := end_angle - sep_inner_angle

	var outer_start := start_angle + sep_outer_angle
	var outer_end := end_angle - sep_outer_angle

	var fraction_of_full := (end_angle - start_angle) / RAD_360
	var nopoints := maxi(2, int(outer_radius * fraction_of_full))
	var nipoints := maxi(2, int(inner_radius * fraction_of_full))

	var coords := calc_ring_segment_centers(
		outer_radius, nopoints, outer_start, outer_end, offset, true
	)
	coords.append_array(
		calc_ring_segment_centers(inner_radius, nipoints, inner_end, inner_start, offset, true)
	)
	return coords
