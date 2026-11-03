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
@onready var status_label: Label = %StatusLabel
@onready var cover_label: Label = %CoverLabel
@onready var cohesion_label: Label = %CohesionLabel

## Battlefield terrain, for the cover line; none if null.
var terrain: TerrainMap
@onready var movement_label: Label = %MovementLabel

var _shown: SquadState


func _ready() -> void:
    show_squad(null)


func show_squad(state: SquadState) -> void:
    if _shown:
        _shown.movement_changed.disconnect(_update_movement)
        _shown.position_changed.disconnect(_update_movement)
        _shown.models_changed.disconnect(_update_models)
        _shown.morale_changed.disconnect(_update_status)
    _shown = null
    var squad := state.data if state else null
    if squad == null or squad.profile == null:
        name_label.text = EMPTY_TEXT
        player_label.visible = false
        stats_grid.visible = false
        movement_label.visible = false
        models_label.visible = false
        status_label.visible = false
        cover_label.visible = false
        cohesion_label.visible = false
        return
    _shown = state
    state.movement_changed.connect(_update_movement)
    state.position_changed.connect(_update_movement)
    state.models_changed.connect(_update_models)
    state.morale_changed.connect(_update_status)
    _update_movement(state)
    _update_models(state)
    _update_status(state)
    _update_cover(state)
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


## Squad-wide cover and majority armour save, recalculated from current
## positions whenever the squad moves or loses models.
func _update_cover(state: SquadState) -> void:
    var save := TerrainRules.majority_armor_save(state)
    cover_label.text = "Cover: %s, Sv %s" % [TerrainPiece.cover_name(TerrainRules.squad_cover(state, terrain)),
        "%d+" % save if save > 0 else "-"]
    cover_label.visible = true


## Cohesion of the living models, recalculated whenever they move or one is
## removed. Report only.
func _update_cohesion(state: SquadState) -> void:
    cohesion_label.text = CohesionRules.describe(state)
    cohesion_label.modulate = Color.WHITE if CohesionRules.is_coherent(state) else Color(1.0, 0.6, 0.4)
    cohesion_label.visible = true


func _update_movement(state: SquadState) -> void:
    if state.movement_complete:
        movement_label.text = "Moved %.1f / %s (done)" % [state.movement_used, String.num(state.movement_allowance)]
    else:
        movement_label.text = "Moved %.1f / %s" % [state.movement_used, String.num(state.movement_allowance)]
    movement_label.visible = true
    _update_cover(state)
    _update_cohesion(state)


func _update_models(state: SquadState) -> void:
    _update_cover(state)
    _update_cohesion(state)
    var wounds_left := 0
    for model in state.get_living_models():
        wounds_left += model.wounds_remaining
    models_label.text = "Models %d/%d, %d W left" % [state.get_model_count(), state.get_models().size(), wounds_left]
    models_label.visible = true


static func status_text(state: SquadState) -> String:
    var text: String = ["Steady", "Shaken", "Broken"][state.morale_status]
    if state.morale_restricted_this_turn:
        text += " (no shooting/charging)"
    return text


func _update_status(state: SquadState) -> void:
    status_label.text = "Status: %s" % status_text(state)
    status_label.visible = true
