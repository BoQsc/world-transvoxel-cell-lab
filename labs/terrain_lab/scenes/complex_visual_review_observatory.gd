@tool
extends Control

const JsonLoader := preload(
	"res://addons/world_transvoxel_terrain_lab/lab/services/wt_terrain_lab_json.gd"
)
const STANDARD_PATH := (
	"res://addons/world_transvoxel_terrain_lab/standards/complex_visual_temporal_corpus_standard.json"
)

@onready var image_view: TextureRect = %ImageView
@onready var title_label: Label = %TitleLabel
@onready var counter_label: Label = %CounterLabel
@onready var metadata_label: Label = %MetadataLabel
@onready var status_label: Label = %StatusLabel
@onready var criteria: VBoxContainer = %Criteria
@onready var finding_edit: LineEdit = %FindingEdit
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var live_button: Button = %LiveButton
@onready var accept_button: Button = %AcceptButton
@onready var reject_button: Button = %RejectButton
@onready var motion_selector: OptionButton = %MotionSelector
@onready var motion_live_button: Button = %MotionLiveButton

var _standard := {}
var _automation := {}
var _review := {}
var _stills: Array = []
var _motion_paths: Array = []
var _index := 0
var _category_checks := {}
var _open_scene_request := ""
var _visited_stills := {}
var _reviewed_motion_paths := {}
var _requested_live_scenes := {}


func _ready() -> void:
	_load_data()
	_build_criteria()
	previous_button.pressed.connect(_previous)
	next_button.pressed.connect(_next)
	live_button.pressed.connect(_request_live_scene)
	motion_live_button.pressed.connect(_request_motion_scene)
	accept_button.pressed.connect(_record_acceptance)
	reject_button.pressed.connect(_record_rejection)
	_show_current()


func consume_open_scene_request() -> String:
	var result := _open_scene_request
	_open_scene_request = ""
	return result


func _load_data() -> void:
	_standard = JsonLoader.load_dictionary(STANDARD_PATH)
	_automation = JsonLoader.load_dictionary(str(_standard.get("automation_evidence", "")))
	_review = JsonLoader.load_dictionary(str(_standard.get("review_verdict", "")))
	_stills = _automation.get("stills", _standard.get("stills", []))
	_motion_paths = _automation.get("motion_paths", _standard.get("motion_paths", []))
	motion_selector.clear()
	for record_value in _motion_paths:
		var record: Dictionary = record_value
		motion_selector.add_item(str(record.get("id", "")).replace("_", " ").capitalize())
		motion_selector.set_item_metadata(
			motion_selector.item_count - 1, str(record.get("scene", ""))
		)
	motion_live_button.disabled = _motion_paths.is_empty()


func _build_criteria() -> void:
	for child in criteria.get_children():
		child.queue_free()
	_category_checks.clear()
	var saved: Dictionary = _review.get("categories", {})
	var contract: Dictionary = _standard.get("coverage_contract", {})
	for category_value in contract.get("required_review_categories", []):
		var category := str(category_value)
		var check := CheckButton.new()
		check.text = category.replace("_", " ").capitalize()
		check.button_pressed = str(saved.get(category, "")) == "PASS"
		criteria.add_child(check)
		_category_checks[category] = check


func _show_current() -> void:
	if _stills.is_empty():
		status_label.text = "FAIL  AUTOMATION CORPUS ABSENT"
		return
	_index = posmod(_index, _stills.size())
	var record: Dictionary = _stills[_index]
	_visited_stills[str(record.get("id", ""))] = true
	var texture := load(str(record.get("path", ""))) as Texture2D
	image_view.texture = texture
	title_label.text = str(record.get("id", "")).replace("_", " ").capitalize()
	counter_label.text = "%02d / %02d" % [_index + 1, _stills.size()]
	metadata_label.text = "%s  /  %s  /  %s\n%s" % [
		str(record.get("scale", "")).to_upper(), str(record.get("subject", "")),
		str(record.get("angle", "")), ", ".join(record.get("categories", [])),
	]
	var review_status := str(_review.get("status", "PENDING_HUMAN_REVIEW"))
	status_label.text = "%s  CORPUS %s" % [
		review_status, str(_automation.get("corpus_signature", "missing")).left(12),
	]
	previous_button.disabled = _stills.size() < 2
	next_button.disabled = _stills.size() < 2
	live_button.disabled = str(record.get("scene", "")).is_empty()


func _previous() -> void:
	_index -= 1
	_show_current()


func _next() -> void:
	_index += 1
	_show_current()


func _request_live_scene() -> void:
	if not _stills.is_empty():
		_open_scene_request = str((_stills[_index] as Dictionary).get("scene", ""))
		_requested_live_scenes[_open_scene_request] = true


func _request_motion_scene() -> void:
	if _motion_paths.is_empty() or motion_selector.selected < 0:
		return
	var record: Dictionary = _motion_paths[motion_selector.selected]
	_open_scene_request = str(record.get("scene", ""))
	_reviewed_motion_paths[str(record.get("id", ""))] = true
	_requested_live_scenes[_open_scene_request] = true


func _record_acceptance() -> void:
	if _visited_stills.size() != _stills.size():
		status_label.text = "PENDING  STILLS %d / %d" % [_visited_stills.size(), _stills.size()]
		return
	if _reviewed_motion_paths.size() != _motion_paths.size():
		status_label.text = "PENDING  MOTION %d / %d" % [_reviewed_motion_paths.size(), _motion_paths.size()]
		return
	var required_scenes := _required_live_scenes()
	for scene in required_scenes:
		if not _requested_live_scenes.has(scene):
			status_label.text = "PENDING  LIVE SOURCES %d / %d" % [
				_requested_live_scenes.size(), required_scenes.size(),
			]
			return
	for category in _category_checks:
		if not (_category_checks[category] as CheckButton).button_pressed:
			status_label.text = "PENDING  REVIEW EVERY CATEGORY"
			return
	_write_review("PASS", "")


func _record_rejection() -> void:
	var finding := finding_edit.text.strip_edges()
	if finding.is_empty():
		status_label.text = "PENDING  FINDING REQUIRED FOR REJECTION"
		return
	_write_review("FAIL", finding)


func _write_review(status: String, finding: String) -> void:
	var category_status := {}
	for category in _category_checks:
		category_status[category] = (
			"PASS" if (_category_checks[category] as CheckButton).button_pressed else "FAIL"
		)
	var findings: Array = []
	if not finding.is_empty():
		findings.append(finding)
	_review = {
		"schema": "world_transvoxel.terrain_lab.complex_visual_temporal_corpus_human_review.v1",
		"milestone": "TQP-44",
		"status": status,
		"reviewer": OS.get_environment("USERNAME"),
		"reviewed_at": Time.get_datetime_string_from_system(true),
		"corpus_signature": str(_automation.get("corpus_signature", "")),
		"categories": category_status,
		"reviewed_still_ids": _sorted_keys(_visited_stills),
		"reviewed_motion_path_ids": _sorted_keys(_reviewed_motion_paths),
		"requested_live_scenes": _sorted_keys(_requested_live_scenes),
		"findings": findings,
		"note": "Recorded by the TQP-44 @tool review observatory after explicit human action.",
	}
	var path := str(_standard.get("review_verdict", ""))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status_label.text = "FAIL  COULD NOT WRITE REVIEW VERDICT"
		return
	file.store_string(JSON.stringify(_review, "\t", false) + "\n")
	file.close()
	status_label.text = status + "  HUMAN VERDICT RECORDED"


func _required_live_scenes() -> Array[String]:
	var scenes := {}
	for group in [_stills, _motion_paths]:
		for record_value in group:
			var scene := str((record_value as Dictionary).get("scene", ""))
			if not scene.is_empty():
				scenes[scene] = true
	return _sorted_keys(scenes)


static func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if not str(value).is_empty():
			result.append(str(value))
	result.sort()
	return result
