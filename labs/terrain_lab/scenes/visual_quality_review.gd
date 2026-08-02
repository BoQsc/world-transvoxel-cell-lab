@tool
extends Node3D

enum Fixture { NATURAL, CONSTRUCTED, DESTROYED, ADVERSARIAL }

const Catalog := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_visual_quality_catalog.gd"
)
const DRAFT_PATH := "user://tqp25_visual_quality_review_draft.json"

@export_group("Visual Quality Review")
@export var editor_fixture: Fixture = Fixture.NATURAL:
	set(value):
		editor_fixture = value
		if is_inside_tree():
			call_deferred("_set_fixture_index", int(value))
@export var editor_motion_preview := false:
	set(value):
		editor_motion_preview = value
		_motion_enabled = value
@export_range(8.0, 60.0, 1.0) var motion_cycle_seconds := 18.0
@export var editor_sun_shadows := true:
	set(value):
		editor_sun_shadows = value
		if is_inside_tree():
			call_deferred("set_shadows_enabled", value)
@export var editor_restart_motion := false:
	set(value):
		editor_restart_motion = false
		if value and is_inside_tree():
			_restart_motion()
@export_group("")

@onready var observatory: Node3D = $TerrainObservatory
@onready var camera: Camera3D = $TerrainObservatory/Camera3D
@onready var sun: DirectionalLight3D = $TerrainObservatory/Sun
@onready var review_interface: CanvasLayer = %ReviewInterface
@onready var fixture_option: OptionButton = %FixtureOption
@onready var motion_toggle: CheckButton = %MotionToggle
@onready var shadow_toggle: CheckButton = %ShadowToggle
@onready var review_status: Label = %ReviewStatus
@onready var target_label: Label = %TargetLabel
@onready var review_notes: LineEdit = %ReviewNotes
@onready var candidate_button: Button = %RecordCandidateButton

var _standard := {}
var _fixtures: Array = []
var _fixture_index := 0
var _fixture_result := {}
var _motion_enabled := false
var _motion_elapsed := 0.0
var _visited_fixtures := {}
var _motion_cycles_by_fixture := {}
var _visited_shadow_states := {}
var _criterion_boxes: Array[CheckBox] = []
var _recorded_draft_status := ""


func _ready() -> void:
	_standard = Catalog.standard()
	_fixtures = _standard.get("fixtures", [])
	_setup_controls()
	_motion_enabled = editor_motion_preview if Engine.is_editor_hint() else true
	motion_toggle.set_pressed_no_signal(_motion_enabled)
	_set_fixture_index(clampi(int(editor_fixture), 0, maxi(_fixtures.size() - 1, 0)))
	set_shadows_enabled(editor_sun_shadows)
	set_process(true)


func _process(delta: float) -> void:
	if not _motion_enabled or _fixtures.is_empty():
		return
	var previous_phase := _motion_elapsed / motion_cycle_seconds
	_motion_elapsed = fmod(_motion_elapsed + delta, motion_cycle_seconds)
	var phase := _motion_elapsed / motion_cycle_seconds
	if phase < previous_phase:
		var fixture_id := current_fixture_id()
		_motion_cycles_by_fixture[fixture_id] = int(
			_motion_cycles_by_fixture.get(fixture_id, 0)
		) + 1
		_update_review_status()
	set_motion_phase(phase)


func _setup_controls() -> void:
	fixture_option.clear()
	for index in range(_fixtures.size()):
		var fixture: Dictionary = _fixtures[index]
		fixture_option.add_item(str(fixture.get("label", fixture.get("id", ""))), index)
	fixture_option.item_selected.connect(_set_fixture_index)
	%PreviousButton.pressed.connect(_step_fixture.bind(-1))
	%NextButton.pressed.connect(_step_fixture.bind(1))
	motion_toggle.toggled.connect(_set_motion_enabled)
	shadow_toggle.toggled.connect(set_shadows_enabled)
	%RestartButton.pressed.connect(_restart_motion)
	%RecordFailureButton.pressed.connect(_record_review_draft.bind("REJECTED"))
	candidate_button.pressed.connect(_record_review_draft.bind("CANDIDATE_ACCEPTED"))
	for criterion_value in _standard.get("criteria", []):
		var criterion: Dictionary = criterion_value
		var box := CheckBox.new()
		box.name = str(criterion.get("id", "criterion"))
		box.text = str(criterion.get("label", criterion.get("id", "")))
		box.tooltip_text = str(criterion.get("failure", ""))
		box.toggled.connect(_update_review_status.unbind(1))
		%Criteria.add_child(box)
		_criterion_boxes.append(box)


func _step_fixture(offset: int) -> void:
	if _fixtures.is_empty():
		return
	_set_fixture_index(posmod(_fixture_index + offset, _fixtures.size()))


func _set_fixture_index(index: int) -> void:
	if _fixtures.is_empty() or not is_instance_valid(observatory):
		return
	_fixture_index = clampi(index, 0, _fixtures.size() - 1)
	fixture_option.select(_fixture_index)
	var fixture: Dictionary = _fixtures[_fixture_index]
	_fixture_result = observatory.call("prepare_visual_quality_fixture", fixture)
	_visited_fixtures[str(fixture.get("id", ""))] = true
	_motion_elapsed = 0.0
	_set_fixed_camera(fixture)
	_update_target(fixture)
	set_shadows_enabled(editor_sun_shadows)
	_update_review_status()


func set_fixture_by_id(fixture_id: String) -> Dictionary:
	for index in range(_fixtures.size()):
		if str((_fixtures[index] as Dictionary).get("id", "")) == fixture_id:
			_set_fixture_index(index)
			return _fixture_result.duplicate(true)
	return {"status": "FAIL", "failures": ["unknown fixture: " + fixture_id]}


func current_fixture_id() -> String:
	if _fixtures.is_empty():
		return ""
	return str((_fixtures[_fixture_index] as Dictionary).get("id", ""))


func current_fixture() -> Dictionary:
	if _fixtures.is_empty():
		return {}
	return (_fixtures[_fixture_index] as Dictionary).duplicate(true)


func _set_fixed_camera(fixture: Dictionary) -> void:
	var camera_config: Dictionary = fixture.get("camera", {})
	camera.position = Catalog.vector3(camera_config.get("still_position", []))
	camera.fov = float(camera_config.get("fov_degrees", 45.0))
	camera.look_at(Catalog.vector3(camera_config.get("target", [])), Vector3.UP)


func set_fixed_camera() -> void:
	var fixture := current_fixture()
	if not fixture.is_empty():
		_set_fixed_camera(fixture)


func set_motion_phase(phase: float) -> void:
	var path_progress := 0.5 - 0.5 * cos(TAU * clampf(phase, 0.0, 1.0))
	set_motion_path_progress(path_progress)


func set_motion_path_progress(progress: float) -> void:
	var fixture := current_fixture()
	if fixture.is_empty():
		return
	var camera_config: Dictionary = fixture.get("camera", {})
	var target := Catalog.vector3(camera_config.get("target", []))
	var start_angle := deg_to_rad(float(camera_config.get("motion_start_degrees", 0.0)))
	var end_angle := deg_to_rad(float(camera_config.get("motion_end_degrees", 180.0)))
	var angle := lerpf(start_angle, end_angle, clampf(progress, 0.0, 1.0))
	var radius_m := float(camera_config.get("motion_radius_m", 30.0))
	var height_m := float(camera_config.get("motion_height_m", 14.0))
	camera.position = target + Vector3(cos(angle) * radius_m, height_m, sin(angle) * radius_m)
	camera.fov = float(camera_config.get("fov_degrees", 45.0))
	camera.look_at(target, Vector3.UP)


func _set_motion_enabled(enabled: bool) -> void:
	_motion_enabled = enabled
	if is_instance_valid(motion_toggle):
		motion_toggle.set_pressed_no_signal(enabled)


func _restart_motion() -> void:
	_motion_elapsed = 0.0
	set_motion_phase(0.0)


func set_shadows_enabled(enabled: bool) -> void:
	if not is_instance_valid(sun):
		return
	sun.shadow_enabled = enabled
	_visited_shadow_states[enabled] = true
	if is_instance_valid(shadow_toggle):
		shadow_toggle.set_pressed_no_signal(enabled)
	_update_review_status()


func set_capture_mode(enabled: bool) -> void:
	if is_instance_valid(review_interface):
		review_interface.visible = not enabled
	observatory.get_node("Interface").visible = false


func get_geometry_evidence() -> Dictionary:
	return {
		"metrics": observatory.call("get_mesh_metrics"),
		"seams": observatory.call("get_seam_report"),
		"topology": observatory.call("get_topology_report"),
	}


func get_review_contract() -> Dictionary:
	var criterion_ids: Array[String] = []
	for criterion_value in _standard.get("criteria", []):
		criterion_ids.append(str((criterion_value as Dictionary).get("id", "")))
	return {
		"milestone": "TQP-25",
		"fixture_ids": Catalog.fixture_ids(),
		"criterion_ids": criterion_ids,
		"draft_path": DRAFT_PATH,
		"formal_decision_required": true,
		"finding": str((_standard.get("finding_resolution", {}) as Dictionary).get("finding", "")),
		"decision_policy": _standard.get("decision_policy", {}),
	}


func _update_target(fixture: Dictionary) -> void:
	var target: Dictionary = fixture.get("art_direction_target", {})
	target_label.text = str(target.get("intent", ""))
	target_label.tooltip_text = "Reject if: " + ", ".join(target.get("reject_if", []))


func _candidate_ready() -> bool:
	for fixture_id in Catalog.fixture_ids():
		if not _visited_fixtures.has(fixture_id):
			return false
		if int(_motion_cycles_by_fixture.get(fixture_id, 0)) < 1:
			return false
	if not _visited_shadow_states.has(true) or not _visited_shadow_states.has(false):
		return false
	for box in _criterion_boxes:
		if not box.button_pressed:
			return false
	return not _criterion_boxes.is_empty()


func _update_review_status() -> void:
	if not is_instance_valid(review_status):
		return
	var visited_count := _visited_fixtures.size()
	var completed_motion := 0
	for fixture_id in Catalog.fixture_ids():
		if int(_motion_cycles_by_fixture.get(fixture_id, 0)) >= 1:
			completed_motion += 1
	var shadow_count := _visited_shadow_states.size()
	review_status.text = "%d/4 fixtures | %d/4 motion | %d/2 shadows" % [
		visited_count,
		completed_motion,
		shadow_count,
	]
	candidate_button.disabled = not _candidate_ready() or not _recorded_draft_status.is_empty()
	%RecordFailureButton.disabled = not _recorded_draft_status.is_empty()


func _record_review_draft(status: String) -> void:
	var criteria := {}
	for box in _criterion_boxes:
		criteria[box.name] = box.button_pressed
	var draft := {
		"schema": "world_transvoxel.terrain_lab.visual_quality_review_draft.v1",
		"milestone": "TQP-25",
		"status": status,
		"visited_fixtures": _visited_fixtures,
		"motion_cycles_by_fixture": _motion_cycles_by_fixture,
		"visited_shadow_states": _visited_shadow_states.keys(),
		"criteria": criteria,
		"notes": review_notes.text,
		"finding": "TQP-F001",
		"formal_decision_required": true,
		"authoritative": false,
	}
	var file := FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	if file == null:
		review_status.text = "Draft write failed"
		return
	file.store_string(JSON.stringify(draft, "\t", false) + "\n")
	_recorded_draft_status = status
	review_status.text = status + " draft recorded; repository decision required"
	_update_review_status()
