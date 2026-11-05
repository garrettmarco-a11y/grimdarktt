extends Node2D
class_name ObjectiveLayer
## Draws the battlefield's fixed objectives above the terrain and beneath the
## movement overlay and squad tokens. Visual only: it owns no objective or
## control state, and shows control as ObjectiveRules computes it from the
## models' current positions. Must be a direct child of a GameBoard.
##
## Each objective is a marker with its display name and its control-radius
## outline: neutral when uncontrolled, the controlling player's colour when
## controlled, and dashed in both players' colours when contested.

const CONTESTED_DASHES := 24
const OUTLINE_WIDTH := 2.0
const MARKER_RADIUS := 6.0
const FILL_ALPHA := 0.10
const LABEL_SIZE := 14

var _objectives: Array[ObjectiveSetup] = []
var _battle: BattleState


## Shows `objectives`, with control from the squads on `battle`, and redraws
## whenever a squad is added or removed or its models, position or morale
## change.
func bind(objectives: Array[ObjectiveSetup], battle: BattleState) -> void:
    _objectives = objectives
    _battle = battle
    battle.squad_added.connect(_watch)
    battle.squad_removed.connect(_unwatch)
    for squad in battle.get_squads():
        _watch(squad)
    queue_redraw()


func get_objectives() -> Array[ObjectiveSetup]:
    return _objectives


## The control shown for `objective` now (as ObjectiveRules computes it).
func displayed_status(objective: ObjectiveSetup) -> ObjectiveRules.Status:
    return ObjectiveRules.status_of(objective, _battle) if _battle else ObjectiveRules.Status.new()


## Outline colours for `status`: one colour, or both players' for contested.
static func colors_for(status: ObjectiveRules.Status) -> Array[Color]:
    var colors: Array[Color] = []
    match status.control:
        ObjectiveRules.ControlState.CONTROLLED:
            colors.append(SquadToken.PLAYER_COLORS[status.player])
        ObjectiveRules.ControlState.CONTESTED:
            colors.append(SquadToken.PLAYER_COLORS[TurnManager.PLAYER_ONE])
            colors.append(SquadToken.PLAYER_COLORS[TurnManager.PLAYER_TWO])
        _:
            colors.append(SquadToken.NEUTRAL_COLOR)
    return colors


func _draw() -> void:
    var board := get_parent() as GameBoard
    if board == null:
        return
    var font := ThemeDB.fallback_font
    for objective in _objectives:
        var centre := board.units_to_pixels(objective.position)
        var radius := objective.control_radius * board.pixels_per_unit
        var colors := colors_for(displayed_status(objective))
        var fill := colors[0] if colors.size() == 1 else SquadToken.NEUTRAL_COLOR
        draw_circle(centre, radius, Color(fill, FILL_ALPHA))
        if colors.size() == 1:
            draw_arc(centre, radius, 0.0, TAU, 64, colors[0], OUTLINE_WIDTH)
        else:
            var step := TAU / CONTESTED_DASHES
            for i in CONTESTED_DASHES:
                draw_arc(centre, radius, i * step, (i + 1) * step, 6, colors[i % 2], OUTLINE_WIDTH)
        draw_circle(centre, MARKER_RADIUS, Color(0.08, 0.08, 0.09, 0.85))
        draw_circle(centre, MARKER_RADIUS, fill, false, 1.5)
        var text_size := font.get_string_size(objective.display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_SIZE)
        draw_string(font, centre + Vector2(-text_size.x / 2.0, -MARKER_RADIUS - 4.0), objective.display_name,
            HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_SIZE, Color(0.95, 0.92, 0.8))


func _watch(squad: SquadState) -> void:
    for changed in [squad.position_changed, squad.models_changed, squad.morale_changed]:
        if not changed.is_connected(_on_squad_changed):
            changed.connect(_on_squad_changed)
    queue_redraw()


func _unwatch(squad: SquadState) -> void:
    for changed in [squad.position_changed, squad.models_changed, squad.morale_changed]:
        if changed.is_connected(_on_squad_changed):
            changed.disconnect(_on_squad_changed)
    queue_redraw()


func _on_squad_changed(_squad: SquadState) -> void:
    queue_redraw()
