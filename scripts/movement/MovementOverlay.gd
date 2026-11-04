extends Node2D
class_name MovementOverlay
## Draws movement guidance for the selected squad under the squad tokens: the
## leader's remaining movement range from where it stands (movement is paid
## along the path travelled), the line from where it began the turn, and a
## brief marker where an order was rejected.
##
## In the Charge phase it instead shows the selected squad's maximum possible
## charge reach, but only while that squad could still declare a charge
## (ChargeRules.can_declare_any, and `charge_available`): around each model a
## circle of M + 6 plus its base radius, so an enemy base whose edge falls
## inside is within M + 6 edge to edge; and a ring on every model of each
## enemy squad ChargeRules.validate would accept. It shows reach, not that a
## charge will make contact: the D6 decides that.
##
## In the Shooting phase, while the selected squad is the one activated to
## shoot, it rings every model of each enemy squad it may fire at
## (`shoot_targets`, i.e. ShootingController.valid_targets): never a friendly
## squad, nor an enemy squad engaged in combat.
##
## Must be a direct child of a GameBoard. Reads SquadState; changes nothing.

const RANGE_COLOR := Color(1.0, 0.86, 0.35, 0.10)
const RANGE_EDGE_COLOR := Color(1.0, 0.86, 0.35, 0.45)
const PATH_COLOR := Color(1.0, 0.86, 0.35, 0.8)
const REJECT_COLOR := Color(1.0, 0.3, 0.25)
const CHARGE_COLOR := Color(0.95, 0.45, 0.2, 0.07)
const CHARGE_EDGE_COLOR := Color(0.95, 0.45, 0.2, 0.55)
const CHARGE_TARGET_COLOR := Color(0.95, 0.45, 0.2, 0.95)
const SHOOT_TARGET_COLOR := Color(0.45, 0.8, 1.0, 0.95)
## Seconds a rejected-order marker stays visible.
const REJECT_DURATION := 1.0

## The current phase; the charge reach is shown only in the Charge phase.
var phase := TurnManager.Phase.MOVEMENT:
    set(value):
        phase = value
        queue_redraw()
## Battle and round-long commitments, for charge reach and valid targets.
var battle: BattleState
var engagements: EngagementTracker
## Callable(state: SquadState) -> bool: whether the squad can still declare a
## charge this phase (activating now, or yet to activate). Always if unset.
var charge_available := Callable()
## Callable(state: SquadState) -> Array[SquadState]: the squads `state` may
## shoot at now (empty unless it is activated to shoot). None if unset.
var shoot_targets := Callable()

var _squad: SquadState
var _orders_enabled := true
var _reject_point := Vector2.ZERO
var _reject_time_left := 0.0


## Shows guidance for `state`, or nothing when it is null.
func show_squad(state: SquadState) -> void:
    if _squad:
        _squad.position_changed.disconnect(_on_squad_changed)
        _squad.movement_changed.disconnect(_on_squad_changed)
    _squad = state
    if _squad:
        _squad.position_changed.connect(_on_squad_changed)
        _squad.movement_changed.connect(_on_squad_changed)
    queue_redraw()


## Range guidance is only drawn while move orders can be given.
func set_orders_enabled(enabled: bool) -> void:
    _orders_enabled = enabled
    queue_redraw()


## Marks `board_point` (board units) as a rejected destination.
func show_rejected(board_point: Vector2) -> void:
    _reject_point = board_point
    _reject_time_left = REJECT_DURATION
    set_process(true)
    queue_redraw()


## True if the selected squad's maximum charge reach is being shown.
func is_showing_charge_reach() -> bool:
    if phase != TurnManager.Phase.CHARGE or _squad == null or battle == null:
        return false
    if not ChargeRules.can_declare_any(_squad, battle.get_squads(), engagements):
        return false
    return not charge_available.is_valid() or charge_available.call(_squad)


## Radius, in board units, of the reach circle drawn around `model`.
func charge_reach_radius(model: ModelState) -> float:
    return ChargeRules.max_charge_distance(_squad) + model.get_base_radius()


## Enemy squads highlighted as valid charge targets (empty unless shown).
func charge_targets() -> Array[SquadState]:
    if not is_showing_charge_reach():
        return []
    return ChargeRules.valid_targets(_squad, battle.get_squads(), engagements)


## Enemy squads ringed as valid shooting targets (empty outside Shooting).
func shooting_targets() -> Array[SquadState]:
    var targets: Array[SquadState] = []
    if phase != TurnManager.Phase.SHOOTING or _squad == null or not shoot_targets.is_valid():
        return targets
    targets.assign(shoot_targets.call(_squad))
    return targets


func is_showing_rejection() -> bool:
    return _reject_time_left > 0.0


func _ready() -> void:
    set_process(false)


func _process(delta: float) -> void:
    _reject_time_left = maxf(_reject_time_left - delta, 0.0)
    if _reject_time_left == 0.0:
        set_process(false)
    queue_redraw()


func _on_squad_changed(_state: SquadState) -> void:
    queue_redraw()


func _draw() -> void:
    var board := get_parent() as GameBoard
    if board == null:
        return
    if _squad and _orders_enabled:
        var start := board.units_to_pixels(_squad.turn_start_position)
        var current := board.units_to_pixels(_squad.board_position)
        if not _squad.movement_complete:
            var radius := _squad.get_remaining_movement() * board.pixels_per_unit
            draw_circle(current, radius, RANGE_COLOR)
            draw_circle(current, radius, RANGE_EDGE_COLOR, false, 1.5)
        if start != current:
            draw_circle(start, 3.0, PATH_COLOR)
            draw_line(start, current, PATH_COLOR, 2.0)
    if is_showing_charge_reach():
        for model in _squad.get_living_models():
            var centre := board.units_to_pixels(model.position)
            var reach := charge_reach_radius(model) * board.pixels_per_unit
            draw_circle(centre, reach, CHARGE_COLOR)
            draw_circle(centre, reach, CHARGE_EDGE_COLOR, false, 1.5)
        for target in charge_targets():
            for model in target.get_living_models():
                draw_circle(board.units_to_pixels(model.position),
                    (model.get_base_radius() * board.pixels_per_unit) + 4.0, CHARGE_TARGET_COLOR, false, 2.0)
    for target in shooting_targets():
        for model in target.get_living_models():
            draw_circle(board.units_to_pixels(model.position),
                (model.get_base_radius() * board.pixels_per_unit) + 4.0, SHOOT_TARGET_COLOR, false, 2.0)
    if _reject_time_left > 0.0:
        var p := board.units_to_pixels(_reject_point)
        var color := REJECT_COLOR
        color.a = _reject_time_left / REJECT_DURATION
        draw_line(p + Vector2(-8, -8), p + Vector2(8, 8), color, 3.0)
        draw_line(p + Vector2(-8, 8), p + Vector2(8, -8), color, 3.0)
