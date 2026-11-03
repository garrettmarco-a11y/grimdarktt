extends Node
class_name ConsolidationController
## Runs the Consolidation phase as an automatic procedure, after every Assault
## engagement has resolved. Has no input or drawing code.
##
## Rules (approved by the project lead):
##   - Every surviving, non-Broken squad that fought in an engagement this
##     round consolidates, whether its side won, lost or drew. Broken squads
##     (including those that failed an assault-loss test and fell back) do not.
##   - Squads go in engagement resolution order, each engagement's squads in
##     its turn order; models in the mover's deterministic order.
##   - Each living model may move up to DISTANCE (fixed, not a share of
##     Movement), with difficult terrain ignored and impassable terrain, the
##     board edge and every base blocking. A model already in base contact
##     with an enemy model stays where it is.
##   - The others head for the nearest living model of the squad's declared
##     attack target, if that squad is still on the battlefield; otherwise of
##     the nearest living enemy squad of the engagement (edge to edge, ties by
##     squad_id). With no enemy left, the squad stays.
##   - Consolidation uses no Movement allowance, grants no attack, starts no
##     assault and changes no engagement record: contacts it makes count as
##     ongoing engagements next round.

signal consolidated(entries: Array)

## Fixed consolidation distance, in board units.
const DISTANCE := 2.0

## Battlefield terrain: impassable areas block. None if null.
var terrain: TerrainMap
var board_size := Vector2.ZERO
## The last phase's report: one Dictionary per consolidating squad with
## "squad", "target", "moved" (models that moved), "held" (models that stayed
## in contact) and "paths" (model_id -> [start, end]).
var last_report: Array = []

var _turn_manager: TurnManager
var _battle: BattleState
var _tracker: EngagementTracker
var _engagements: EngagementController


func bind(turn_manager: TurnManager, battle: BattleState, tracker: EngagementTracker,
        engagements: EngagementController, board_units: Vector2) -> void:
    _turn_manager = turn_manager
    _battle = battle
    _tracker = tracker
    _engagements = engagements
    board_size = board_units
    turn_manager.register_procedure(TurnManager.Phase.CONSOLIDATION, _run)


## Consolidates every eligible squad of `outcomes` (engagements in resolution
## order). Returns the report.
func consolidate(outcomes: Array) -> Array:
    var report := []
    for outcome in outcomes:
        var enemies_of := func(squad: SquadState) -> Array:
            return outcome.squads.filter(func(s: SquadState) -> bool:
                return s.get_player() != squad.get_player() and _on_battlefield(s))
        for squad in outcome.squads:
            if not _on_battlefield(squad) or squad.morale_status == SquadState.MoraleStatus.BROKEN:
                continue
            var enemies: Array = enemies_of.call(squad)
            var target := _target_for(squad, enemies)
            if target == null:
                continue
            var moving: Array[ModelState] = []
            var held := 0
            for model in squad.get_living_models():
                if EngagementRules.model_in_enemy_contact(squad, model, _battle.get_squads()):
                    held += 1
                else:
                    moving.append(model)
            var entry := {"squad": squad, "target": target, "moved": 0, "held": held, "paths": {}}
            if not moving.is_empty():
                var plan := SquadMover.plan_consolidate(squad, moving, target, DISTANCE, _battle.get_squads(),
                    terrain, board_size)
                var positions := {}
                for model in moving:
                    var end := plan.position_of(model)
                    entry.paths[model.model_id] = [model.position, end]
                    if end.distance_to(model.position) > ModelPlacement.CONTACT_TOLERANCE:
                        entry.moved += 1
                    positions[model.model_id] = end
                squad.place_models(positions)
            report.append(entry)
    _check_layout()
    last_report = report
    return report


func _run() -> void:
    var outcomes: Array = _engagements.outcomes if _engagements else []
    consolidated.emit(consolidate(outcomes))
    _turn_manager.complete_procedure_phase(TurnManager.Phase.CONSOLIDATION)


## The squad's declared target if still on the battlefield, else the nearest
## living enemy squad of the engagement.
func _target_for(squad: SquadState, enemies: Array) -> SquadState:
    var declared := _battle.get_squad(_tracker.attack_target_of(squad.squad_id)) if _tracker else null
    if declared and declared in enemies:
        return declared
    var best: SquadState = null
    var best_distance := INF
    var ordered := enemies.duplicate()
    ordered.sort_custom(func(a: SquadState, b: SquadState) -> bool: return String(a.squad_id) < String(b.squad_id))
    for enemy in ordered:
        var d := ChargeRules.closest_edge_distance(squad, enemy)
        if d < best_distance:
            best = enemy
            best_distance = d
    return best


func _on_battlefield(squad: SquadState) -> bool:
    return squad.get_model_count() > 0 and _battle.get_squad(squad.squad_id) == squad


func _check_layout() -> void:
    for pair in ModelPlacement.find_overlaps(_battle.get_squads()):
        push_error("ConsolidationController: %s overlaps %s" % [ModelPlacement.describe(pair[0], pair[1]),
            ModelPlacement.describe(pair[2], pair[3])])
