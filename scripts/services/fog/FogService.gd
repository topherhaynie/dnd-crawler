extends IFogService
class_name FogService

var _fog_state: Dictionary = {
    "enabled": true,
    "revealed": []
}

# Legacy snapshot compatibility storage (mirrors FogManager behavior)
var _fog_state_image: Image = null
var _fog_state_png: PackedByteArray = PackedByteArray()
var _fog_state_size: Vector2i = Vector2i.ZERO
const DEBUG_SAVE_CAPTURE_PNG: bool = false
var _fallback_black_texture: ImageTexture = null

func _ready() -> void:
    # no-op ready hook; services should be registered by bootstrap/autoload
    pass

func reveal_area(pos: Vector2, radius: float) -> void:
    # Minimal implementation: record a reveal entry and emit update
    _fog_state.revealed.append({"pos": pos, "radius": radius})
    emit_signal("fog_updated", _fog_state)

func set_fog_enabled(enabled: bool) -> void:
    _fog_state.enabled = enabled
    emit_signal("fog_updated", _fog_state)

func get_fog_state() -> PackedByteArray:
    # Return the last captured fog snapshot (PNG buffer), if any.
    return _fog_state_png.duplicate()


func get_fog_state_size() -> Vector2i:
    return _fog_state_size


func set_fog_state(data: PackedByteArray) -> bool:
    if data.is_empty():
        _fog_state_image = null
        _fog_state_png = PackedByteArray()
        _fog_state_size = Vector2i.ZERO
        return false
    var image := Image.new()
    var err := image.load_png_from_buffer(data)
    if err != OK or image.is_empty():
        push_warning("FogService: could not decode fog state PNG (err=%d bytes=%d)" % [err, data.size()])
        return false
    _fog_state_image = image
    _fog_state_png = data.duplicate()
    _fog_state_size = Vector2i(image.get_width(), image.get_height())
    return true


func capture_fog_state(viewport: SubViewport) -> PackedByteArray:
    if viewport == null:
        return PackedByteArray()
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    await get_tree().process_frame
    var tex := viewport.get_texture()
    if tex == null:
        return PackedByteArray()
    var image := tex.get_image()
    if image == null or image.is_empty():
        return PackedByteArray()
    if DEBUG_SAVE_CAPTURE_PNG:
        var save_err := image.save_png("user://last_captured_fog.png")
        if save_err != OK:
            push_warning("FogService: failed to save debug capture user://last_captured_fog.png (err=%d)" % save_err)
    image.convert(Image.FORMAT_L8)
    _fog_state_image = image
    _fog_state_png = image.save_png_to_buffer()
    _fog_state_size = Vector2i(image.get_width(), image.get_height())
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    return _fog_state_png.duplicate()


func rect_from_circle(center_px: Vector2, radius_px: float, min_radius_px: float) -> Rect2i:
    var safe_radius := maxf(radius_px, min_radius_px)
    var x0 := floori(center_px.x - safe_radius)
    var y0 := floori(center_px.y - safe_radius)
    var x1 := ceili(center_px.x + safe_radius)
    var y1 := ceili(center_px.y + safe_radius)
    return Rect2i(x0, y0, maxi(1, x1 - x0 + 1), maxi(1, y1 - y0 + 1))


func compact_los_dirty_regions(dirty_regions: Array, merge_padding: int, max_dirty: int) -> Array:
    if dirty_regions == null:
        return []
    if dirty_regions.size() <= 1:
        return dirty_regions.duplicate(true)

    var regions := []
    for item in dirty_regions:
        regions.append(item)

    var i := 0
    while i < regions.size():
        if not regions[i] is Rect2i:
            regions.remove_at(i)
            continue
        var current := regions[i] as Rect2i
        var j := i + 1
        while j < regions.size():
            if not regions[j] is Rect2i:
                regions.remove_at(j)
                continue
            var other := regions[j] as Rect2i
            var current_padded := current.grow(merge_padding)
            var other_padded := other.grow(merge_padding)
            if current_padded.intersects(other) or other_padded.intersects(current):
                current = current.merge(other)
                regions[i] = current
                regions.remove_at(j)
                continue
            j += 1
        i += 1

    if regions.size() <= max_dirty:
        return regions

    var merged := regions[0] as Rect2i
    for idx in range(1, regions.size()):
        if regions[idx] is Rect2i:
            merged = merged.merge(regions[idx] as Rect2i)
    return [merged]


func should_bake_los_now(los_bake_pending: bool, last_msec: int, interval_msec: int) -> bool:
    if not los_bake_pending:
        return false
    if interval_msec <= 0:
        return true
    var now := Time.get_ticks_msec()
    if last_msec == 0:
        return true
    return (now - last_msec) >= interval_msec


# merge_live_los_into_history removed — GPU-only; no CPU fallback permitted.

func _create_or_update_image_texture(existing: ImageTexture, image: Image) -> ImageTexture:
    if image == null or image.is_empty():
        return existing
    if existing == null:
        return ImageTexture.create_from_image(image)

    var tex_size := existing.get_size()
    if int(tex_size.x) != image.get_width() or int(tex_size.y) != image.get_height():
        return ImageTexture.create_from_image(image)

    existing.update(image)
    return existing


func _get_or_create_fallback_black_texture() -> ImageTexture:
    if _fallback_black_texture != null:
        return _fallback_black_texture
    var img := Image.create(1, 1, false, Image.FORMAT_L8)
    img.fill(Color(0.0, 0.0, 0.0, 1.0))
    _fallback_black_texture = ImageTexture.create_from_image(img)
    return _fallback_black_texture


func seed_gpu_history_from_image(history_viewports: Array, history_merge_rects: Array, history_image: Image, existing_seed_texture: ImageTexture, los_bake_gain: float) -> Dictionary:
    if history_image == null or history_image.is_empty():
        return {"ok": false}
    if history_viewports == null or history_merge_rects == null:
        return {"ok": false}

    var seed_texture := _create_or_update_image_texture(existing_seed_texture, history_image)

    for i in range(history_viewports.size()):
        var merge := history_merge_rects[i] as ColorRect
        var vp := history_viewports[i] as SubViewport
        if merge == null or vp == null:
            continue
        var mat := merge.material as ShaderMaterial
        if mat == null:
            continue
        mat.set_shader_parameter("seed_mode", true)
        mat.set_shader_parameter("seed_tex", seed_texture)
        mat.set_shader_parameter("prev_history_tex", seed_texture)
        mat.set_shader_parameter("live_lights_tex", _get_or_create_fallback_black_texture())
        mat.set_shader_parameter("los_bake_gain", los_bake_gain)
        mat.set_shader_parameter("has_paint_tex", false)
        vp.render_target_update_mode = SubViewport.UPDATE_ONCE

    var history_texture: Texture2D = null
    if history_viewports.size() > 0:
        var vp0 := history_viewports[0] as SubViewport
        history_texture = vp0.get_texture() if vp0 else null

    return {
        "ok": true,
        "seed_texture": seed_texture,
        "history_texture": history_texture,
        "active_index": 0,
        "swap_pending": false,
        "pending_target_index": - 1,
        "seed_pending": true,
    }


func upload_history_texture(history_image: Image, history_gpu_ready: bool, existing_history_texture: ImageTexture, history_viewports: Array, history_merge_rects: Array, los_bake_gain: float = 1.0) -> Dictionary:
    if history_image == null:
        return {"ok": false, "history_texture": existing_history_texture}
    if history_gpu_ready:
        var res := seed_gpu_history_from_image(history_viewports, history_merge_rects, history_image, null, los_bake_gain)
        if res.get("ok", false):
            return {"ok": true, "history_texture": res.get("history_texture", existing_history_texture), "seed_texture": res.get("seed_texture", null), "history_dirty": false}
        return {"ok": false, "history_texture": existing_history_texture}

    var new_tex: ImageTexture = existing_history_texture
    if new_tex == null:
        new_tex = ImageTexture.create_from_image(history_image)
    else:
        if new_tex is ImageTexture:
            new_tex = _create_or_update_image_texture(new_tex, history_image)

    return {"ok": true, "history_texture": new_tex, "history_dirty": false}


func set_history_seed_from_hidden(history_image: Image, cell_px: int, hidden_cells: Dictionary) -> Dictionary:
    if history_image == null or history_image.is_empty():
        return {"changed": false, "history_image": history_image, "seed_cell_px": 1}
    # Start from fully revealed, then paint hidden cells from map truth.
    history_image.fill(Color(1.0, 0.0, 0.0, 1.0))
    var safe_cell_px := maxi(1, cell_px)
    for key in hidden_cells.keys():
        if not key is Vector2i:
            continue
        var cell := key as Vector2i
        _paint_cell_block_internal(history_image, cell, safe_cell_px, 0.0)
    return {"changed": true, "history_image": history_image, "seed_cell_px": safe_cell_px}


func apply_history_seed_delta(history_image: Image, revealed_cells: Array, hidden_cells: Array, cell_px: int) -> bool:
    if history_image == null or history_image.is_empty():
        return false
    if revealed_cells.is_empty() and hidden_cells.is_empty():
        return false
    var safe_cell_px := maxi(1, cell_px)
    var changed := false
    for raw in revealed_cells:
        var cell := _to_cell_internal(raw)
        if cell.x < 0 or cell.y < 0:
            continue
        _paint_cell_block_internal(history_image, cell, safe_cell_px, 1.0)
        changed = true
    for raw in hidden_cells:
        var cell := _to_cell_internal(raw)
        if cell.x < 0 or cell.y < 0:
            continue
        _paint_cell_block_internal(history_image, cell, safe_cell_px, 0.0)
        changed = true
    return changed


func apply_history_brush(history_image: Image, world_pos: Vector2, radius_px: float, reveal: bool) -> bool:
    if history_image == null or history_image.is_empty():
        return false
    var safe_radius := maxf(1.0, radius_px)
    var min_x := maxi(0, int(floor(world_pos.x - safe_radius)))
    var min_y := maxi(0, int(floor(world_pos.y - safe_radius)))
    var max_x := mini(history_image.get_width() - 1, int(ceil(world_pos.x + safe_radius)))
    var max_y := mini(history_image.get_height() - 1, int(ceil(world_pos.y + safe_radius)))
    if min_x > max_x or min_y > max_y:
        return false
    var target := Color(1.0 if reveal else 0.0, 0.0, 0.0, 1.0)
    for py in range(min_y, max_y + 1):
        for px in range(min_x, max_x + 1):
            if Vector2(float(px) + 0.5, float(py) + 0.5).distance_to(world_pos) <= safe_radius:
                history_image.set_pixel(px, py, target)
    return true


func apply_history_rect(history_image: Image, a: Vector2, b: Vector2, reveal: bool) -> bool:
    if history_image == null or history_image.is_empty():
        return false
    var min_x := maxi(0, int(floor(minf(a.x, b.x))))
    var min_y := maxi(0, int(floor(minf(a.y, b.y))))
    var max_x := mini(history_image.get_width() - 1, int(ceil(maxf(a.x, b.x))))
    var max_y := mini(history_image.get_height() - 1, int(ceil(maxf(a.y, b.y))))
    if min_x > max_x or min_y > max_y:
        return false
    history_image.fill_rect(
            Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1),
            Color(1.0 if reveal else 0.0, 0.0, 0.0, 1.0))
    return true


# export_hidden_cells_for_sync removed — fog state is managed as GPU texture snapshot.
# commit_runtime_history_to_seed removed — legacy stats, unused.


func _paint_cell_block_internal(history_image: Image, cell: Vector2i, cell_px: int, value: float) -> void:
    if history_image == null:
        return
    var x0 := cell.x * cell_px
    var y0 := cell.y * cell_px
    var x1 := x0 + cell_px
    var y1 := y0 + cell_px
    var w := history_image.get_width()
    var h := history_image.get_height()
    if x1 <= 0 or y1 <= 0 or x0 >= w or y0 >= h:
        return
    x0 = maxi(0, x0)
    y0 = maxi(0, y0)
    x1 = mini(w, x1)
    y1 = mini(h, y1)
    history_image.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), Color(value, 0.0, 0.0, 1.0))


func _to_cell_internal(v: Variant) -> Vector2i:
    if v is Vector2i:
        return v as Vector2i
    if v is Vector2:
        var p := v as Vector2
        return Vector2i(int(round(p.x)), int(round(p.y)))
    if v is Dictionary:
        return Vector2i(int(v.get("x", -1)), int(v.get("y", -1)))
    if v is Array and (v as Array).size() >= 2:
        var arr := v as Array
        return Vector2i(int(arr[0]), int(arr[1]))
    return Vector2i(-1, -1)
