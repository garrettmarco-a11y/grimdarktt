extends Node
class_name ChargeController
## Applies charge declarations in the Charge phase: validates them with
## ChargeRules, rolls the squad's single D6, moves the models with
## SquadMover.plan_charge, records a successful charge in the round-long
## EngagementTracker, and ends the charging squad's activation. Has no input
## or drawing code.
##
##   - A refused declaration changes nothing and does not spend the
##     activation; the player may declare again or end the activation.
##   - An accepted declaration always spends the activation. A failed charge
##     still moves the models as far as the roll allows, but commits nobody.
##   - A successful charge commits the charger and its target to one
##     engagement (joining the target's if it already has one) and locks the
##     charger's attack target. A target that had not yet activated this phase
##     loses its Charge activation: it is now engaged.

signal charge_resolved(result: ChargeResult)
signal charge_rejected(charger: SquadState, target: SquadState, result: ChargeRules.Result)

var dice := DiceRoller.new()
## Battlefield terrain: difficult and impassable areas. None if null.
var terrain: TerrainMap
var board_size := Vector2.ZERO
## The last accepted charge.
var last_result: ChargeResult

var _turn_manager: TurnManager
var _activation: ActivationController
var _battle: BattleState
var _tracker: EngagementTracker


func bind(turn_manager: TurnManager, activation: ActivationController, battle: BattleState,
        tracker: EngagementTracker, board_units: Vector2) -> void:
    _turn_manager = turn_manager
    _activation = activation
    _battle = battle
    _tracker = tracker
    board_size = board_units
    activation.charge_rule = func(state: SquadState) -> bool:
        return ChargeRules.can_declare_any(state, _battle.get_squads(), _tracker)


## Declares a charge by `charger` against `target`. Returns the result; only
## an OK declaration rolls, moves models and spends the activation.
func declare_charge(charger: SquadState, target: SquadState) -> ChargeRules.Result:
    var activated := _activation.is_active_squad(charger)
    var result := ChargeRules.validate(charger, target, _turn_manager.current_phase, activated,
        _battle.get_squads(), _tracker)
    if result != ChargeRules.Result.OK:
        charge_rejected.emit(charger, target, result)
        return result
    var outcome := ChargeResult.new()
    outcome.charger = charger
    outcome.target = target
    outcome.roll = dice.roll_d6()
    outcome.distance = ChargeRules.charge_distance(charger, outcome.roll)
    var plan := SquadMover.plan_charge(charger, target, outcome.distance, _battle.get_squads(), terrain, board_size)
    var positions := {}
    for model in charger.get_living_models():
        outcome.paths[model.model_id] = [model.position, plan.position_of(model)]
        positions[model.model_id] = plan.position_of(model)
    charger.place_models(positions)
    _check_layout()
    for model in charger.get_living_models():
        for enemy in target.get_living_models():
            if ModelPlacement.models_in_contact(model, enemy):
                outcome.models_in_contact += 1
                break
    outcome.succeeded = outcome.models_in_contact > 0
    if outcome.succeeded:
        outcome.engagement = _tracker.record_charge(charger.squad_id, target.squad_id)
        _activation.withdraw(target)
    last_result = outcome
    charge_resolved.emit(outcome)
    if _activation.is_active_squad(charger):
        _activation.end_activation()
    return result


## Charges must never leave bases overlapping, nor touch a non-target enemy.
func _check_layout() -> void:
    for pair in ModelPlacement.find_overlaps(_battle.get_squads()):
        push_error("ChargeController: %s overlaps %s" % [ModelPlacement.describe(pair[0], pair[1]),
            ModelPlacement.describe(pair[2], pair[3])])
