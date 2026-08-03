@tool
extends RefCounted
class_name WtTerrainLabTransitionField

const CHUNK_CELLS_PER_AXIS := 16
const SAMPLE_SCALE_M := 0.5

var mode := "surface"
var center_grid := Vector3i.ZERO
var extent_grid := 32


func configure(coarse_coordinate: Vector3i, coarse_lod: int, field_mode: String = "surface") -> bool:
	if coarse_lod < 1 or coarse_lod > 3 or field_mode not in ["surface", "empty", "full"]:
		return false
	mode = field_mode
	extent_grid = CHUNK_CELLS_PER_AXIS * (1 << coarse_lod)
	center_grid = coarse_coordinate * extent_grid + Vector3i.ONE * (extent_grid / 2)
	return true


func sample(point: Vector3i) -> Dictionary:
	if mode == "empty":
		return {"density": 1000000.0, "material": 0, "material_authored": false}
	if mode == "full":
		return {"density": -1000000.0, "material": 1, "material_authored": true}
	var local := Vector3(point - center_grid) * SAMPLE_SCALE_M
	var density_value := local.x + local.y + local.z \
		+ 0.18 * sin((local.x + local.z) * 0.21) \
		+ 0.11 * cos((local.y - local.z) * 0.17)
	var material_id := 1 + posmod(point.x + point.y * 3 + point.z * 5, 4)
	return {
		"density": density_value,
		"material": material_id if density_value < 0.0 else 0,
		"material_authored": density_value < 0.0,
	}


func definition_signature() -> String:
	return JSON.stringify({
		"mode": mode,
		"center_grid": center_grid,
		"extent_grid": extent_grid,
		"sample_scale_m": SAMPLE_SCALE_M,
	}).sha256_text()
