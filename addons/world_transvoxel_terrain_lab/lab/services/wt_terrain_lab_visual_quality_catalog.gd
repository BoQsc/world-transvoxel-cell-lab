@tool
extends RefCounted
class_name WtTerrainLabVisualQualityCatalog

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/visual_quality_corpus_standard.json"
)


static func standard() -> Dictionary:
	return JsonLoader.load_dictionary(STANDARD_PATH)


static func fixtures() -> Array:
	return standard().get("fixtures", [])


static func fixture_ids() -> Array[String]:
	var result: Array[String] = []
	for fixture_value in fixtures():
		var fixture: Dictionary = fixture_value
		result.append(str(fixture.get("id", "")))
	return result


static func fixture_by_id(fixture_id: String) -> Dictionary:
	for fixture_value in fixtures():
		var fixture: Dictionary = fixture_value
		if str(fixture.get("id", "")) == fixture_id:
			return fixture.duplicate(true)
	return {}


static func vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
