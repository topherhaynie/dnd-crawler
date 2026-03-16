## DEPRECATED: moved to legacy during fog audit
## Original path: scripts/tools/FogTruthCodec.gd
## Reason: offline/tooling codec; not used at runtime.
extends RefCounted

static func hidden_to_grid_image(map_size: Vector2, cell_px: int, hidden_cells: Dictionary) -> Image:
    var safe_cell_px := maxi(1, cell_px)
    var grid_w := maxi(1, ceili(map_size.x / float(safe_cell_px)))
    var grid_h := maxi(1, ceili(map_size.y / float(safe_cell_px)))
    var img := Image.create(grid_w, grid_h, false, Image.FORMAT_RF)
    img.fill(Color(1.0, 0.0, 0.0, 1.0))
    for key in hidden_cells.keys():
        if not key is Vector2i:
            continue
        var cell := key as Vector2i
        if cell.x < 0 or cell.y < 0 or cell.x >= grid_w or cell.y >= grid_h:
            continue
        img.set_pixel(cell.x, cell.y, Color(0.0, 0.0, 0.0, 1.0))
    return img


static func grid_image_to_hidden(img: Image, threshold: float = 0.5) -> Dictionary:
    var hidden: Dictionary = {}
    if img == null or img.is_empty():
        return hidden
    var w := img.get_width()
    var h := img.get_height()
    for y in range(h):
        for x in range(w):
            if img.get_pixel(x, y).r < threshold:
                hidden[Vector2i(x, y)] = true
    return hidden


static func sampled_mask_to_hidden(mask_img: Image, map_size: Vector2, cell_px: int, threshold: float = 0.5) -> Dictionary:
    return sampled_mask_to_hidden_with_offset(mask_img, map_size, cell_px, Vector2.ZERO, threshold)


static func sampled_mask_to_hidden_with_offset(mask_img: Image, map_size: Vector2, cell_px: int, sample_offset_px: Vector2, threshold: float = 0.5) -> Dictionary:
    var hidden: Dictionary = {}
    if mask_img == null or mask_img.is_empty():
        return hidden
    var safe_cell_px := maxf(float(maxi(1, cell_px)), 1.0)
    var grid_w := maxi(1, ceili(map_size.x / safe_cell_px))
    var grid_h := maxi(1, ceili(map_size.y / safe_cell_px))
    var w := mask_img.get_width()
    var h := mask_img.get_height()
    for gy in range(grid_h):
        for gx in range(grid_w):
            var sx := clampi(int(floor((float(gx) + 0.5) * safe_cell_px + sample_offset_px.x)), 0, w - 1)
            var sy := clampi(int(floor((float(gy) + 0.5) * safe_cell_px + sample_offset_px.y)), 0, h - 1)
            if mask_img.get_pixel(sx, sy).r < threshold:
                hidden[Vector2i(gx, gy)] = true
    return hidden


static func hidden_mismatch_count(a: Dictionary, b: Dictionary) -> int:
    var count := 0
    for k in a.keys():
        if not b.has(k):
            count += 1
    for k in b.keys():
        if not a.has(k):
            count += 1
    return count
