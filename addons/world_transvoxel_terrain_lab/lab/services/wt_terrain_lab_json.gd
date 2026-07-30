@tool
extends RefCounted
class_name WtTerrainLabJson


static func load_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


static func stable_file_signature(paths: Array[String]) -> Dictionary:
	var hashes := {}
	var signature_lines: Array[String] = []
	for path in paths:
		if not FileAccess.file_exists(path):
			hashes[path] = ""
			signature_lines.append(path + ":MISSING")
			continue
		var digest := FileAccess.get_sha256(path)
		hashes[path] = digest
		signature_lines.append(path + ":" + digest)
	signature_lines.sort()
	return {
		"algorithm": "sha256",
		"files": hashes,
		"aggregate": "\n".join(signature_lines).sha256_text(),
	}
