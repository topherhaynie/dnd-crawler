extends RefCounted
class_name QRCode

## Pure GDScript QR Code generator.
## Supports Version 1–6 (up to 134 bytes at EC level L), byte mode only.
## Usage:
##   var img: Image = QRCode.generate("https://example.com", 8)
##   var tex := ImageTexture.create_from_image(img)

# Error correction level L (lowest — 7% recovery, maximum data capacity).
# We only need L for URLs displayed on a trusted screen.

# Version capacities in byte mode at EC level L (data codewords).
const _VERSION_CAPACITY: Array[int] = [
	0, # placeholder for index 0
	17, # v1: 19 data codewords, 2 EC = 17 usable bytes
	32, # v2
	53, # v3
	78, # v4
	106, # v5
	134, # v6
]

# Total data codewords per version at EC level L.
const _DATA_CODEWORDS: Array[int] = [0, 19, 34, 55, 80, 108, 136]

# EC codewords per block at EC level L.
const _EC_PER_BLOCK: Array[int] = [0, 7, 10, 15, 20, 26, 18]

# Number of EC blocks at EC level L.
const _NUM_BLOCKS: Array[int] = [0, 1, 1, 1, 1, 1, 2]

# Alignment pattern center coordinates per version (empty for v1).
const _ALIGN_CENTERS: Array = [
	[], # v0 placeholder
	[], # v1
	[6, 18], # v2
	[6, 22], # v3
	[6, 26], # v4
	[6, 30], # v5
	[6, 34], # v6
]

# Module size: version * 4 + 17
static func _qr_size(version: int) -> int:
	return version * 4 + 17


## Generate a QR code Image from the given text.
## scale = pixels per module (e.g. 8 gives an image that is size*8 px wide).
## Returns an RGBA8 Image with white background and black modules.
static func generate(text: String, scale: int = 8) -> Image:
	var data: PackedByteArray = text.to_utf8_buffer()
	var version: int = _pick_version(data.size())
	var size: int = _qr_size(version)

	# Encode data into codewords
	var codewords: PackedByteArray = _encode_data(data, version)

	# Generate EC codewords and interleave
	var final_msg: PackedByteArray = _add_error_correction(codewords, version)

	# Place modules on the grid
	var modules: Array = [] # Array of Array[bool]
	var is_function: Array = [] # tracks function pattern cells
	for y: int in range(size):
		var row: Array[bool] = []
		var func_row: Array[bool] = []
		row.resize(size)
		func_row.resize(size)
		for x: int in range(size):
			row[x] = false
			func_row[x] = false
		modules.append(row)
		is_function.append(func_row)

	_place_finder_patterns(modules, is_function, size)
	_place_alignment_patterns(modules, is_function, version, size)
	_place_timing_patterns(modules, is_function, size)
	_place_dark_module(modules, is_function, version)
	_reserve_format_area(is_function, size)

	# Place data bits
	_place_data_bits(modules, is_function, final_msg, size)

	# Apply best mask
	var best_mask: int = _apply_best_mask(modules, is_function, size)

	# Write format info
	_place_format_info(modules, best_mask, size)

	# Render to Image
	return _render_image(modules, size, scale)


static func _pick_version(byte_count: int) -> int:
	for v: int in range(1, 7):
		if byte_count <= _VERSION_CAPACITY[v]:
			return v
	push_error("QRCode: data too large for Version 1-6 (%d bytes)" % byte_count)
	return 6


static func _encode_data(data: PackedByteArray, version: int) -> PackedByteArray:
	var total_data_cw: int = _DATA_CODEWORDS[version]
	var bits: Array[int] = [] # stream of individual bits

	# Mode indicator: byte mode = 0100
	_append_bits(bits, 0b0100, 4)

	# Character count (8 bits for versions 1-9 in byte mode)
	_append_bits(bits, data.size(), 8)

	# Data
	for b: int in data:
		_append_bits(bits, b, 8)

	# Terminator (up to 4 zero bits)
	var capacity_bits: int = total_data_cw * 8
	var terminator_len: int = mini(4, capacity_bits - bits.size())
	for _i: int in range(terminator_len):
		bits.append(0)

	# Pad to byte boundary
	while bits.size() % 8 != 0:
		bits.append(0)

	# Pad codewords (alternating 0xEC, 0x11)
	var pad_byte: int = 0
	while bits.size() < capacity_bits:
		_append_bits(bits, 0xEC if pad_byte % 2 == 0 else 0x11, 8)
		pad_byte += 1

	# Convert bit stream to bytes
	var result: PackedByteArray = PackedByteArray()
	result.resize(total_data_cw)
	for i: int in range(total_data_cw):
		var byte_val: int = 0
		for bit: int in range(8):
			byte_val = (byte_val << 1) | bits[i * 8 + bit]
		result[i] = byte_val

	return result


static func _append_bits(bits: Array[int], value: int, length: int) -> void:
	for i: int in range(length - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _add_error_correction(data_cw: PackedByteArray, version: int) -> PackedByteArray:
	var num_blocks: int = _NUM_BLOCKS[version]
	var ec_per_block: int = _EC_PER_BLOCK[version]
	var total_data: int = data_cw.size()
	@warning_ignore("integer_division")
	var block_size: int = total_data / num_blocks

	var data_blocks: Array = []
	var ec_blocks: Array = []
	var offset: int = 0

	for b: int in range(num_blocks):
		var this_block_size: int = block_size
		# Last block gets remaining bytes for uneven splits
		if b == num_blocks - 1:
			this_block_size = total_data - offset
		var block: PackedByteArray = data_cw.slice(offset, offset + this_block_size)
		data_blocks.append(block)
		ec_blocks.append(_reed_solomon(block, ec_per_block))
		offset += this_block_size

	# Interleave data codewords
	var result: PackedByteArray = PackedByteArray()
	var max_data_len: int = 0
	for block: PackedByteArray in data_blocks:
		max_data_len = maxi(max_data_len, block.size())
	for i: int in range(max_data_len):
		for block: PackedByteArray in data_blocks:
			if i < block.size():
				result.append(block[i])

	# Interleave EC codewords
	for i: int in range(ec_per_block):
		for block: PackedByteArray in ec_blocks:
			if i < block.size():
				result.append(block[i])

	return result


# GF(256) Reed-Solomon with generator polynomial for the given EC length.
static func _reed_solomon(data: PackedByteArray, ec_count: int) -> PackedByteArray:
	# Build generator polynomial
	var gen: PackedByteArray = PackedByteArray([1])
	for i: int in range(ec_count):
		var new_gen: PackedByteArray = PackedByteArray()
		new_gen.resize(gen.size() + 1)
		for j: int in range(new_gen.size()):
			new_gen[j] = 0
		for j: int in range(gen.size()):
			new_gen[j] ^= gen[j]
			new_gen[j + 1] ^= _gf_mul(gen[j], _gf_exp(i))
		gen = new_gen

	# Polynomial long division
	var result: PackedByteArray = PackedByteArray()
	result.resize(ec_count)
	for i: int in range(ec_count):
		result[i] = 0

	var work: PackedByteArray = PackedByteArray()
	work.resize(data.size() + ec_count)
	for i: int in range(data.size()):
		work[i] = data[i]
	for i: int in range(data.size(), work.size()):
		work[i] = 0

	for i: int in range(data.size()):
		var coef: int = work[i]
		if coef != 0:
			for j: int in range(1, gen.size()):
				work[i + j] ^= _gf_mul(gen[j], coef)

	for i: int in range(ec_count):
		result[i] = work[data.size() + i]
	return result


# GF(256) lookup tables
const _GF_EXP_TABLE: Array[int] = [
	1, 2, 4, 8, 16, 32, 64, 128, 29, 58, 116, 232, 205, 135, 19, 38, 76, 152, 45, 90, 180, 117, 234, 201, 143, 3, 6, 12, 24, 48, 96, 192,
	157, 39, 78, 156, 37, 74, 148, 53, 106, 212, 181, 119, 238, 193, 159, 35, 70, 140, 5, 10, 20, 40, 80, 160, 93, 186, 105, 210, 185, 111, 222, 161,
	95, 190, 97, 194, 153, 47, 94, 188, 101, 202, 137, 15, 30, 60, 120, 240, 253, 231, 211, 187, 107, 214, 177, 127, 254, 225, 223, 163, 91, 182, 113, 226,
	217, 175, 67, 134, 17, 34, 68, 136, 13, 26, 52, 104, 208, 189, 103, 206, 129, 31, 62, 124, 248, 237, 199, 147, 57, 114, 228, 213, 183, 115, 230, 209,
	191, 99, 198, 145, 63, 126, 252, 229, 215, 179, 123, 246, 241, 255, 227, 219, 171, 75, 150, 49, 98, 196, 149, 55, 110, 220, 165, 87, 174, 65, 130, 25,
	50, 100, 200, 141, 7, 14, 28, 56, 112, 224, 221, 167, 83, 166, 81, 162, 89, 178, 121, 242, 249, 239, 195, 155, 43, 86, 172, 69, 138, 9, 18, 36,
	72, 144, 61, 122, 244, 245, 247, 243, 251, 235, 203, 139, 11, 22, 44, 88, 176, 125, 250, 233, 207, 131, 27, 54, 108, 216, 173, 71, 142, 1, 2, 4,
	8, 16, 32, 64, 128, 29, 58, 116, 232, 205, 135, 19, 38, 76, 152, 45, 90, 180, 117, 234, 201, 143, 3, 6, 12, 24, 48, 96, 192, 157, 39, 78,
]

const _GF_LOG_TABLE: Array[int] = [
	-1, 0, 1, 25, 2, 50, 26, 198, 3, 223, 51, 238, 27, 104, 199, 75, 4, 100, 224, 14, 52, 141, 239, 129, 28, 193, 105, 248, 200, 8, 76, 113,
	5, 138, 101, 47, 225, 36, 15, 33, 53, 147, 142, 218, 240, 18, 130, 69, 29, 181, 194, 125, 106, 39, 249, 185, 201, 154, 9, 120, 77, 228, 114, 166,
	6, 191, 139, 98, 102, 221, 48, 253, 226, 152, 37, 179, 16, 145, 34, 136, 54, 208, 148, 206, 143, 150, 219, 189, 241, 210, 19, 92, 131, 56, 70, 64,
	30, 66, 182, 163, 195, 72, 126, 110, 107, 58, 40, 84, 250, 133, 186, 61, 202, 94, 155, 159, 10, 21, 121, 43, 78, 212, 229, 172, 115, 243, 167, 87,
	7, 112, 192, 247, 140, 128, 99, 13, 103, 74, 222, 237, 49, 197, 254, 24, 227, 165, 153, 119, 38, 184, 180, 124, 17, 68, 146, 217, 35, 32, 137, 46,
	55, 63, 209, 91, 149, 188, 207, 205, 144, 135, 151, 178, 220, 252, 190, 97, 242, 86, 211, 171, 20, 42, 93, 158, 132, 60, 57, 83, 71, 109, 65, 162,
	31, 45, 67, 216, 183, 123, 164, 118, 196, 23, 73, 236, 127, 12, 111, 246, 108, 161, 59, 82, 41, 157, 85, 170, 251, 96, 134, 177, 187, 204, 62, 90,
	203, 89, 95, 176, 156, 169, 160, 81, 11, 245, 22, 235, 122, 117, 44, 215, 79, 174, 213, 233, 230, 231, 173, 232, 116, 214, 244, 234, 168, 80, 88, 175,
]


static func _gf_exp(a: int) -> int:
	return _GF_EXP_TABLE[a % 255]


static func _gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _GF_EXP_TABLE[(_GF_LOG_TABLE[a] + _GF_LOG_TABLE[b]) % 255]


# ── Module placement ────────────────────────────────────────────────────────

static func _place_finder_patterns(modules: Array, is_function: Array, size: int) -> void:
	var positions: Array[Vector2i] = [Vector2i(0, 0), Vector2i(size - 7, 0), Vector2i(0, size - 7)]
	for pos: Vector2i in positions:
		for dy: int in range(-1, 8):
			for dx: int in range(-1, 8):
				var x: int = pos.x + dx
				var y: int = pos.y + dy
				if x < 0 or x >= size or y < 0 or y >= size:
					continue
				var in_outer: bool = (dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6)
				var in_inner: bool = (dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4)
				var on_border: bool = (dx == 0 or dx == 6 or dy == 0 or dy == 6)
				var dark: bool = in_inner or (in_outer and on_border)
				modules[y][x] = dark
				is_function[y][x] = true


static func _place_alignment_patterns(modules: Array, is_function: Array, version: int, size: int) -> void:
	var centers: Array = _ALIGN_CENTERS[version]
	if centers.is_empty():
		return
	for cy: int in centers:
		for cx: int in centers:
			# Skip if overlapping finder patterns
			if (cx <= 8 and cy <= 8):
				continue
			if (cx <= 8 and cy >= size - 8):
				continue
			if (cx >= size - 8 and cy <= 8):
				continue
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					var dark: bool = (abs(dx) == 2 or abs(dy) == 2 or (dx == 0 and dy == 0))
					modules[cy + dy][cx + dx] = dark
					is_function[cy + dy][cx + dx] = true


static func _place_timing_patterns(modules: Array, is_function: Array, size: int) -> void:
	for i: int in range(8, size - 8):
		var dark: bool = (i % 2 == 0)
		if not is_function[6][i]:
			modules[6][i] = dark
			is_function[6][i] = true
		if not is_function[i][6]:
			modules[i][6] = dark
			is_function[i][6] = true


static func _place_dark_module(modules: Array, is_function: Array, version: int) -> void:
	var row: int = (4 * version) + 9
	modules[row][8] = true
	is_function[row][8] = true


static func _reserve_format_area(is_function: Array, size: int) -> void:
	# Around top-left finder
	for i: int in range(9):
		is_function[8][i] = true
		is_function[i][8] = true
	# Around top-right finder
	for i: int in range(8):
		is_function[8][size - 1 - i] = true
	# Around bottom-left finder
	for i: int in range(7):
		is_function[size - 1 - i][8] = true


static func _place_data_bits(modules: Array, is_function: Array, data: PackedByteArray, size: int) -> void:
	var bit_idx: int = 0
	var total_bits: int = data.size() * 8
	var right: int = size - 1

	while right >= 1:
		if right == 6:
			right = 5 # skip vertical timing column
		@warning_ignore("integer_division")
		var upward: bool = ((size - 1 - right) / 2) % 2 == 0

		for row_offset: int in range(size):
			var y: int = (size - 1 - row_offset) if upward else row_offset
			for col_offset: int in range(2):
				var x: int = right - col_offset
				if x < 0 or x >= size:
					continue
				if is_function[y][x]:
					continue
				if bit_idx < total_bits:
					@warning_ignore("integer_division")
					var byte_i: int = bit_idx / 8
					var bit_i: int = 7 - (bit_idx % 8)
					modules[y][x] = ((data[byte_i] >> bit_i) & 1) == 1
				else:
					modules[y][x] = false
				bit_idx += 1
		right -= 2


# ── Masking ────────────────────────────────────────────────────────────────

static func _mask_condition(mask: int, y: int, x: int) -> bool:
	match mask:
		0: return (y + x) % 2 == 0
		1: return y % 2 == 0
		2: return x % 3 == 0
		3: return (y + x) % 3 == 0
		4:
			@warning_ignore("integer_division")
			var v4: int = (y / 2 + x / 3) % 2
			return v4 == 0
		5: return (y * x) % 2 + (y * x) % 3 == 0
		6: return ((y * x) % 2 + (y * x) % 3) % 2 == 0
		7: return ((y + x) % 2 + (y * x) % 3) % 2 == 0
	return false


static func _apply_best_mask(modules: Array, is_function: Array, size: int) -> int:
	var best_mask: int = 0
	var best_penalty: int = 999999999

	for mask: int in range(8):
		# Apply mask
		for y: int in range(size):
			for x: int in range(size):
				if not is_function[y][x] and _mask_condition(mask, y, x):
					modules[y][x] = not modules[y][x]

		var penalty: int = _evaluate_penalty(modules, size)
		if penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask

		# Remove mask
		for y: int in range(size):
			for x: int in range(size):
				if not is_function[y][x] and _mask_condition(mask, y, x):
					modules[y][x] = not modules[y][x]

	# Apply the best mask permanently
	for y: int in range(size):
		for x: int in range(size):
			if not is_function[y][x] and _mask_condition(best_mask, y, x):
				modules[y][x] = not modules[y][x]

	return best_mask


static func _evaluate_penalty(modules: Array, size: int) -> int:
	var penalty: int = 0

	# Rule 1: runs of same color (≥5 in a row)
	for y: int in range(size):
		var run: int = 1
		for x: int in range(1, size):
			if modules[y][x] == modules[y][x - 1]:
				run += 1
			else:
				if run >= 5:
					penalty += run - 2
				run = 1
		if run >= 5:
			penalty += run - 2

	for x: int in range(size):
		var run: int = 1
		for y: int in range(1, size):
			if modules[y][x] == modules[y - 1][x]:
				run += 1
			else:
				if run >= 5:
					penalty += run - 2
				run = 1
		if run >= 5:
			penalty += run - 2

	# Rule 2: 2×2 blocks of same color
	for y: int in range(size - 1):
		for x: int in range(size - 1):
			var c: bool = modules[y][x]
			if c == modules[y][x + 1] and c == modules[y + 1][x] and c == modules[y + 1][x + 1]:
				penalty += 3

	# Rule 3-4 simplified: just use rules 1+2 for reasonable mask selection
	return penalty


# ── Format info ────────────────────────────────────────────────────────────

# Pre-computed format strings for EC level L (indicator 01), masks 0-7.
# Each is a 15-bit integer including BCH error correction.
const _FORMAT_BITS: Array[int] = [
	0x77C4, # L, mask 0
	0x72F3, # L, mask 1
	0x7DAA, # L, mask 2
	0x789D, # L, mask 3
	0x662F, # L, mask 4
	0x6318, # L, mask 5
	0x6C41, # L, mask 6
	0x6976, # L, mask 7
]

static func _place_format_info(modules: Array, mask: int, size: int) -> void:
	var bits: int = _FORMAT_BITS[mask]

	# Place around top-left finder (horizontal then vertical)
	var horiz_positions: Array[int] = [0, 1, 2, 3, 4, 5, 7, 8]
	for i: int in range(8):
		var bit: bool = ((bits >> (14 - i)) & 1) == 1
		modules[8][horiz_positions[i]] = bit

	# Top-left vertical (reading down column 8)
	var vert_positions: Array[int] = [0, 1, 2, 3, 4, 5, 7, 8]
	for i: int in range(8, 15):
		var bit: bool = ((bits >> (14 - i)) & 1) == 1
		var idx: int = 14 - i
		if idx < 7:
			modules[size - 1 - idx][8] = bit

	# Additional format bits around top-right and bottom-left finders
	for i: int in range(7):
		var bit: bool = ((bits >> (14 - i)) & 1) == 1
		modules[8][size - 1 - (6 - i)] = bit # was wrong direction

	for i: int in range(8):
		var bit: bool = ((bits >> (7 - i)) & 1) == 1
		modules[vert_positions[7 - i]][8] = bit


# ── Rendering ──────────────────────────────────────────────────────────────

static func _render_image(modules: Array, size: int, scale: int) -> Image:
	var quiet: int = 4 # quiet zone modules
	var img_size: int = (size + quiet * 2) * scale
	var img: Image = Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)

	var black: Color = Color.BLACK
	for y: int in range(size):
		for x: int in range(size):
			if modules[y][x]:
				var px: int = (x + quiet) * scale
				var py: int = (y + quiet) * scale
				for dy: int in range(scale):
					for dx: int in range(scale):
						img.set_pixel(px + dx, py + dy, black)
	return img
