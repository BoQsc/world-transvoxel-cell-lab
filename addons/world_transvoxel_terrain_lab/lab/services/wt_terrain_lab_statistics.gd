@tool
extends RefCounted
class_name WtTerrainLabStatistics


static func distribution(samples_usec: Array[float]) -> Dictionary:
	var sorted := samples_usec.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return {
			"sample_count": 0,
			"p50_usec": 0.0,
			"p95_usec": 0.0,
			"p99_usec": 0.0,
			"worst_usec": 0.0,
		}
	return {
		"sample_count": sorted.size(),
		"p50_usec": _percentile(sorted, 0.50),
		"p95_usec": _percentile(sorted, 0.95),
		"p99_usec": _percentile(sorted, 0.99),
		"worst_usec": sorted[-1],
	}


static func provenance(workload_signature: String) -> Dictionary:
	var version := Engine.get_version_info()
	return {
		"workload_signature": workload_signature,
		"build_type": "debug" if OS.is_debug_build() else "release",
		"os": OS.get_name(),
		"architecture": Engine.get_architecture_name(),
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"godot_version": str(version.get("string", "")),
		"backend_revision": _world_transvoxel_signature(),
	}


static func memory_metrics() -> Dictionary:
	return {
		"retained_bytes": OS.get_static_memory_usage(),
		"peak_bytes": OS.get_static_memory_peak_usage(),
	}


static func _percentile(sorted: Array[float], fraction: float) -> float:
	var index := ceili(fraction * float(sorted.size())) - 1
	return sorted[clampi(index, 0, sorted.size() - 1)]


static func _world_transvoxel_signature() -> String:
	var paths: Array[String] = [
		"res://addons/world_transvoxel/world_transvoxel.gdextension",
		"res://addons/world_transvoxel/bin/world_transvoxel.windows.template_debug.x86_64.dll",
		"res://addons/world_transvoxel/bin/world_transvoxel.windows.template_release.x86_64.dll",
	]
	var parts: Array[String] = []
	for path in paths:
		if FileAccess.file_exists(path):
			parts.append(path.get_file() + ":" + FileAccess.get_sha256(path))
		else:
			parts.append(path.get_file() + ":MISSING")
	return "|".join(parts).sha256_text()
