@tool
extends Node3D

enum DiagnosticMode {
	LIT_SURFACE,
	GEOMETRIC_NORMAL,
	MAPPED_NORMAL,
	TRIPLANAR_WEIGHTS,
	SLOPE_MASK,
	HEIGHT_MASK,
	WETNESS_MASK,
	DECAL_MASK,
	CAMERA_DETAIL_FADE,
	SHADOW_ISOLATION,
}

enum CameraPreset { NEAR, FAR, MOTION }

const PROTOCOL_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/surface_shading_review_protocol.json"
)
const DRAFT_PATH := "user://tqp23_surface_review_draft.json"
const NEAR_POSITION := Vector3(-25.0, 22.0, 3.0)
const FAR_POSITION := Vector3(-52.0, 42.0, 3.0)
const CAMERA_TARGET := Vector3(3.0, 8.0, 3.0)
const NEAR_FOV := 48.0
const FAR_FOV := 26.0
const LATERAL_AMPLITUDE_M := 8.0
const DIAGNOSTIC_LABELS := [
	"Lit Surface",
	"Geometric Normal",
	"Mapped Normal",
	"Triplanar Weights",
	"Slope Mask",
	"Height Mask",
	"Wetness Mask",
	"Decal Mask",
	"Camera Detail Fade",
	"Shadow Isolation",
]
const CRITERIA := [
	{"id": "projection_world_anchored", "node": "ProjectionAnchored"},
	{"id": "no_temporal_flicker", "node": "NoFlicker"},
	{"id": "triplanar_transition_coherent", "node": "TriplanarCoherent"},
	{"id": "detail_fade_continuous", "node": "DetailFadeContinuous"},
	{"id": "normal_response_coherent", "node": "NormalsCoherent"},
	{"id": "masks_stable_and_attached", "node": "MasksAttached"},
	{"id": "no_new_surface_discontinuity", "node": "NoDiscontinuity"},
	{"id": "shadow_world_anchored", "node": "ShadowAnchored"},
]

@export_group("Surface Review")
@export var editor_diagnostic_mode: DiagnosticMode = DiagnosticMode.LIT_SURFACE:
	set(value):
		editor_diagnostic_mode = value
		if is_inside_tree():
			call_deferred("_apply_diagnostic_mode")
@export var editor_camera_preset: CameraPreset = CameraPreset.NEAR:
	set(value):
		editor_camera_preset = value
		if is_inside_tree():
			call_deferred("_apply_editor_camera_preset")
@export var editor_motion_preview := false:
	set(value):
		editor_motion_preview = value
		if is_inside_tree():
			_motion_enabled = value
@export_range(8.0, 60.0, 1.0) var motion_cycle_seconds := 20.0
@export var editor_sun_shadows := true:
	set(value):
		editor_sun_shadows = value
		if is_inside_tree():
			call_deferred("_set_shadows_enabled", value)
@export var editor_restart_motion := false:
	set(value):
		editor_restart_motion = false
		if value and is_inside_tree():
			_restart_motion()
@export_group("")

@onready var observatory: Node3D = $TerrainObservatory
@onready var camera: Camera3D = $TerrainObservatory/Camera3D
@onready var sun: DirectionalLight3D = $TerrainObservatory/Sun
@onready var mode_option: OptionButton = %DiagnosticMode
@onready var motion_toggle: CheckButton = %MotionToggle
@onready var motion_progress: ProgressBar = %MotionProgress
@onready var shadow_toggle: CheckButton = %ShadowToggle
@onready var review_status: Label = %ReviewStatus
@onready var pass_button: Button = %RecordPassButton
@onready var notes: LineEdit = %ReviewNotes

var _motion_enabled := false
var _motion_elapsed := 0.0
var _motion_cycles := 0
var _criterion_boxes: Array[CheckBox] = []
var _visited_diagnostic_modes := {}
var _visited_shadow_states := {}
var _recorded_draft_status := ""


func _ready() -> void:
	observatory.call("prepare_surface_shading_review")
	_setup_controls()
	_motion_enabled = editor_motion_preview if Engine.is_editor_hint() else true
	motion_toggle.button_pressed = _motion_enabled
	_apply_diagnostic_mode()
	_set_shadows_enabled(editor_sun_shadows)
	if _motion_enabled:
		set_review_camera_progress(0.0, 0.0)
	else:
		_apply_editor_camera_preset()
	_update_review_status()
	set_process(true)


func _process(delta: float) -> void:
	if not _motion_enabled:
		return
	var previous_phase := _motion_elapsed / motion_cycle_seconds
	_motion_elapsed = fmod(_motion_elapsed + delta, motion_cycle_seconds)
	if _motion_elapsed / motion_cycle_seconds < previous_phase:
		_motion_cycles += 1
		_update_review_status()
	var phase := _motion_elapsed / motion_cycle_seconds
	var progress := 0.5 - 0.5 * cos(TAU * phase)
	set_review_camera_progress(progress, sin(TAU * phase))
	motion_progress.value = progress * 100.0


func _setup_controls() -> void:
	mode_option.clear()
	for mode_id in range(DIAGNOSTIC_LABELS.size()):
		mode_option.add_item(DIAGNOSTIC_LABELS[mode_id], mode_id)
	mode_option.select(editor_diagnostic_mode)
	mode_option.item_selected.connect(_on_diagnostic_selected)
	%NearButton.pressed.connect(_set_camera_preset.bind(CameraPreset.NEAR))
	%FarButton.pressed.connect(_set_camera_preset.bind(CameraPreset.FAR))
	%MotionButton.pressed.connect(_set_camera_preset.bind(CameraPreset.MOTION))
	motion_toggle.toggled.connect(_set_motion_enabled)
	shadow_toggle.toggled.connect(_set_shadows_enabled)
	%RestartButton.pressed.connect(_restart_motion)
	%RecordFailureButton.pressed.connect(_record_review_draft.bind("REJECTED"))
	pass_button.pressed.connect(_record_review_draft.bind("CANDIDATE_ACCEPTED"))
	for criterion in CRITERIA:
		var box := get_node("%" + str(criterion["node"])) as CheckBox
		box.toggled.connect(_on_criterion_toggled)
		_criterion_boxes.append(box)


func _on_diagnostic_selected(index: int) -> void:
	editor_diagnostic_mode = mode_option.get_item_id(index)
	_apply_diagnostic_mode()


func _apply_diagnostic_mode() -> void:
	if not is_instance_valid(observatory):
		return
	observatory.call("set_surface_shading_diagnostic_mode", int(editor_diagnostic_mode))
	_visited_diagnostic_modes[int(editor_diagnostic_mode)] = true
	if is_instance_valid(mode_option):
		mode_option.select(int(editor_diagnostic_mode))
	if is_instance_valid(review_status):
		_update_review_status()


func _apply_editor_camera_preset() -> void:
	if not is_instance_valid(camera):
		return
	_set_camera_preset(editor_camera_preset)


func _set_camera_preset(preset: int) -> void:
	if preset == CameraPreset.NEAR:
		_set_motion_enabled(false)
		set_review_camera_progress(0.0, 0.0)
	elif preset == CameraPreset.FAR:
		_set_motion_enabled(false)
		set_review_camera_progress(1.0, 0.0)
	else:
		_set_motion_enabled(true)


func _set_motion_enabled(enabled: bool) -> void:
	_motion_enabled = enabled
	if is_instance_valid(motion_toggle):
		motion_toggle.set_pressed_no_signal(enabled)


func _restart_motion() -> void:
	_motion_elapsed = 0.0
	_motion_cycles = 0
	set_review_camera_progress(0.0, 0.0)
	motion_progress.value = 0.0
	_update_review_status()


func _set_shadows_enabled(enabled: bool) -> void:
	if not is_instance_valid(sun):
		return
	sun.shadow_enabled = enabled
	_visited_shadow_states[enabled] = true
	if is_instance_valid(shadow_toggle):
		shadow_toggle.set_pressed_no_signal(enabled)
	if is_instance_valid(review_status):
		_update_review_status()


func set_review_camera_progress(progress: float, lateral_phase: float = 0.0) -> void:
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var position := NEAR_POSITION.lerp(FAR_POSITION, clamped_progress)
	position.z += lateral_phase * LATERAL_AMPLITUDE_M
	camera.position = position
	camera.fov = lerpf(NEAR_FOV, FAR_FOV, clamped_progress)
	camera.look_at(CAMERA_TARGET, Vector3.UP)


func get_review_camera_state() -> Dictionary:
	return {
		"position": camera.position,
		"fov_degrees": camera.fov,
		"target": CAMERA_TARGET,
		"motion_cycles": _motion_cycles,
	}


func get_review_contract() -> Dictionary:
	var criterion_ids: Array[String] = []
	for criterion in CRITERIA:
		criterion_ids.append(str(criterion["id"]))
	return {
		"milestone": "TQP-23",
		"protocol": PROTOCOL_PATH,
		"draft_path": DRAFT_PATH,
		"diagnostic_mode_count": DIAGNOSTIC_LABELS.size(),
		"required_diagnostic_modes": DIAGNOSTIC_LABELS.size(),
		"shadow_comparison_required": true,
		"fixture_sample_scale_m": float(observatory.get("editor_sample_scale_m")),
		"criterion_ids": criterion_ids,
		"minimum_motion_cycles": 2,
		"formal_decision_required": true,
	}


func _on_criterion_toggled(_enabled: bool) -> void:
	_update_review_status()


func _all_criteria_pass() -> bool:
	for box in _criterion_boxes:
		if not box.button_pressed:
			return false
	return not _criterion_boxes.is_empty()


func _update_review_status() -> void:
	if not is_instance_valid(review_status):
		return
	if not _recorded_draft_status.is_empty():
		pass_button.disabled = true
		%RecordFailureButton.disabled = true
		review_status.text = (
			_recorded_draft_status + " DRAFT RECORDED\nFormal decision still required"
		)
		return
	pass_button.disabled = not _candidate_pass_ready()
	var checked := 0
	for box in _criterion_boxes:
		if box.button_pressed:
			checked += 1
	review_status.text = (
		"PENDING HUMAN REVIEW\n%d / %d diagnostics viewed\n%d / %d criteria checked\n%d / 2 motion cycles observed\n%d / 1 shadow comparison"
		% [
			_visited_diagnostic_modes.size(),
			DIAGNOSTIC_LABELS.size(),
			checked,
			_criterion_boxes.size(),
			mini(_motion_cycles, 2),
			1 if _visited_shadow_states.size() == 2 else 0,
		]
	)


func _record_review_draft(status: String) -> void:
	if status == "CANDIDATE_ACCEPTED" and not _candidate_pass_ready():
		return
	var criteria: Array[Dictionary] = []
	for index in range(CRITERIA.size()):
		criteria.append({
			"id": str(CRITERIA[index]["id"]),
			"passed": _criterion_boxes[index].button_pressed,
		})
	var visited_diagnostic_modes: Array[int] = []
	for diagnostic_mode in _visited_diagnostic_modes:
		visited_diagnostic_modes.append(int(diagnostic_mode))
	visited_diagnostic_modes.sort()
	var draft := {
		"schema": "world_transvoxel.terrain_lab.surface_shading_review_draft.v1",
		"milestone": "TQP-23",
		"status": status,
		"recorded_at_utc": Time.get_datetime_string_from_system(true, true),
		"protocol": PROTOCOL_PATH,
		"motion_cycles_observed": _motion_cycles,
		"diagnostic_mode": int(editor_diagnostic_mode),
		"diagnostic_modes_viewed": visited_diagnostic_modes,
		"shadow_states_viewed": _visited_shadow_states.keys(),
		"criteria": criteria,
		"notes": notes.text.strip_edges(),
		"environment": {
			"platform": OS.get_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"godot": str(Engine.get_version_info().get("string", "")),
		},
		"authority": "DRAFT_ONLY_REPOSITORY_DECISION_REQUIRED",
	}
	var file := FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	if file == null:
		review_status.text = "DRAFT WRITE FAILED\n" + DRAFT_PATH
		return
	file.store_string(JSON.stringify(draft, "\t", false) + "\n")
	_recorded_draft_status = status
	_update_review_status()


func _candidate_pass_ready() -> bool:
	return (
		_all_criteria_pass()
		and _motion_cycles >= 2
		and _visited_diagnostic_modes.size() == DIAGNOSTIC_LABELS.size()
		and _visited_shadow_states.size() == 2
		and sun.shadow_enabled
	)
