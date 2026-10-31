extends PanelContainer
class_name SquadInfoPanel
## Shows the selected squad's identity, affiliation and statistics.
##
## Reads through the selected SquadState to its SquadData each time selection
## changes; it keeps no copy of the statistics. W is the profile's Wounds
## characteristic; the models line shows the squad's current condition. Both
## that line and the movement line follow the shown squad as it changes.

const EMPTY_TEXT := "No unit selected"

@onready var name_label: Label = %NameLabel
@onready var player_label: Label = %PlayerLabel
@onready var stats_grid: GridContainer = %StatsGrid
@onready var movement_value: Label = %MovementValue
@onready var quality_value: Label = %QualityValue
@onready var toughness_value: Label = %ToughnessValue
@onready var wounds_value: Label = %WoundsValue
@onready var leadership_value: Label = %LeadershipValue
@onready var save_value: Label = %SaveValue
@onready var models_label: Label = %ModelsLabel
@onready var movement_label: Label = %MovementLabel

var _shown: SquadState


func _ready() -> void:
    show_squad(null)


func show_squad(state: SquadState) -> void:
    if _shown:
        _shown.movement_changed.disconnect(_update_movement)
        _shown.position_changed.disconnect(_update_movement)
        _shown.models_changed.disconnect(_update_models)
    _shown = null
    var squad := state.data if state else null
    if squad == null or squad.profile == null:
        name_label.text = EMPTY_TEXT
        player_label.visible = false
        stats_grid.visible = false
        movement_label.visible = false
        models_label.visible = false
        return
    _shown = state
    state.movement_changed.connect(_update_movement)
    state.position_changed.connect(_update_movement)
    state.models_changed.connect(_update_models)
    _update_movement(state)
    _update_models(state)
    var profile := squad.profile
    name_label.text = squad.display_name
    player_label.text = "Player %d" % squad.player
    player_label.visible = true
    movement_value.text = String.num(profile.movement)
    quality_value.text = str(profile.quality)
    toughness_value.text = str(profile.toughness)
    wounds_value.text = str(profile.wounds)
    leadership_value.text = str(profile.leadership)
    save_value.text = "%d+" % profile.armor_save if profile.armor_save > 0 else "-"
    stats_grid.visible = true


func _update_movement(state: SquadState) -> void:
    if state.movement_complete:
        movement_label.text = "Moved %.1f / %s (done)" % [state.distance_moved, String.num(state.movement_allowance)]
    else:
        movement_label.text = "Moved %.1f / %s" % [state.distance_moved, String.num(state.movement_allowance)]
    movement_label.visible = true


func _update_models(state: SquadState) -> void:
    var wounds_left := 0
    for model in state.get_living_models():
        wounds_left += model.wounds_remaining
    models_label.text = "Models %d/%d, %d W left" % [state.get_model_count(), state.get_models().size(), wounds_left]
    models_label.visible = true
