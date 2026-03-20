extends Node2D
class_name FogPaintCanvas

## FogPaintCanvas — GPU-side paint canvas for DM fog brush/rect strokes.
##
## Placed inside a transparent SubViewport. Each stroke is rendered via
## CanvasItem draw calls (draw_circle / draw_rect) so the GPU merge shader
## can sample the result via paint_tex.
##
## Stroke dict schema:
##   Brush: {type: "brush", center: Vector2, radius: float, reveal: bool}
##   Rect:  {type: "rect",  a: Vector2,      b: Vector2,   reveal: bool}
##
## reveal=true  → Color.WHITE (r=1) → history_merge sets pixel revealed
## reveal=false → Color.BLACK (r=0) → history_merge sets pixel hidden

var _strokes: Array = []


func queue_stroke(stroke: Dictionary) -> void:
	_strokes.append(stroke)
	queue_redraw()


func clear_strokes() -> void:
	_strokes.clear()
	queue_redraw()


func _draw() -> void:
	for raw_stroke in _strokes:
		if not raw_stroke is Dictionary:
			continue
		var stroke := raw_stroke as Dictionary
		var type_val: Variant = stroke.get("type", "")
		var type: String = str(type_val)
		var reveal_val: Variant = stroke.get("reveal", true)
		var reveal: bool = bool(reveal_val)
		var paint_color := Color(1.0, 1.0, 1.0, 1.0) if reveal else Color(0.0, 0.0, 0.0, 1.0)

		if type == "brush":
			var center_val: Variant = stroke.get("center", Vector2.ZERO)
			var radius_val: Variant = stroke.get("radius", 64.0)
			var center := center_val as Vector2
			var radius: float = float(radius_val)
			draw_circle(center, radius, paint_color)

		elif type == "rect":
			var a_val: Variant = stroke.get("a", Vector2.ZERO)
			var b_val: Variant = stroke.get("b", Vector2.ZERO)
			var a := a_val as Vector2
			var b := b_val as Vector2
			var rect := Rect2(
				Vector2(minf(a.x, b.x), minf(a.y, b.y)),
				Vector2(absf(b.x - a.x), absf(b.y - a.y))
			)
			if rect.size.x > 0.0 and rect.size.y > 0.0:
				draw_rect(rect, paint_color)
