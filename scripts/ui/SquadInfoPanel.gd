extends PanelContainer
class_name SquadInfoPanel
## Shows the selected squad's identity, affiliation and statistics.
##
## Reads straight from the SquadData it is given each time selection changes;
## it keeps no copy of the statistics.

const EMPTY_TEXT := "No unit selected"

@onready var name_label: Label = %NameLabel
@onready var player_label: Label = %PlayerLabel
@onready var stats_grid: GridContainer = %StatsGrid
@onready var movement_value: Label = %MovementValue
@onready var quality_value: Label = %QualityValue
@onready var toughness_value: Label = %ToughnessValue
@onready var wounds_value: Label = %WoundsValue
@onready var leadership_value: Label = %LeadershipValue


func _ready() -> void:
    show_squad(null)


func show_squad(squad: SquadData) -> void:
    if squad == null or squad.profile == null:
        name_label.text = EMPTY_TEXT
        player_label.visible = false
        stats_grid.visible = false
        return
    var profile := squad.profile
    name_label.text = squad.display_name
    player_label.text = "Player %d" % squad.player
    player_label.visible = true
    movement_value.text = String.num(profile.movement)
    quality_value.text = str(profile.quality)
    toughness_value.text = str(profile.toughness)
    wounds_value.text = str(profile.wounds)
    leadership_value.text = str(profile.leadership)
    stats_grid.visible = true
