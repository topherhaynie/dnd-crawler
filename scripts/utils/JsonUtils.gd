extends Node
class_name JsonUtils

static func parse_json_text(text: String) -> Variant:
    if text == null or text == "":
        return null
    var parsed: Variant = JSON.parse_string(text)
    if parsed == null:
        return null
    # Unwrap Godot's parse wrapper if present { "result": <value> }
    if parsed is Dictionary and parsed.has("result"):
        return parsed["result"]
    return parsed

static func read_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        return null
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("JsonUtils: could not open %s" % path)
        return null
    var text := f.get_as_text()
    f.close()
    return parse_json_text(text)
