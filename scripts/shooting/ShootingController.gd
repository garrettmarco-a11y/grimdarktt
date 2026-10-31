extends Node
class_name ShootingController
## Coordinates a shooting order: validates it with ShootingRules, resolves it,
## reports the result, and ends the firing squad's activation through the
## ActivationController. Has no input or drawing code.

signal shot_resolved(result: ShootingResult)
signal shot_rejected(firing: SquadState, target: SquadState, result: ShootingRules.OrderResult)

var line_of_sight := LineOfSight.new()
var dice := DiceRoller.new()

var _turn_manager: TurnManager
var _activation: ActivationController


func bind(turn_manager: TurnManager, activation: ActivationController) -> void:
    _turn_manager = turn_manager
    _activation = activation


## Orders `firing` to shoot at `target`. A valid order always resolves and
## spends the activation, even if no model can fire.
func order_shot(firing: SquadState, target: SquadState) -> ShootingRules.OrderResult:
    var result := ShootingRules.validate_order(firing, target, _turn_manager.current_phase,
        _activation.is_active_squad(firing))
    if result != ShootingRules.OrderResult.OK:
        shot_rejected.emit(firing, target, result)
        return result
    var outcome := ShootingRules.resolve(firing, target, line_of_sight, dice)
    shot_resolved.emit(outcome)
    _activation.end_activation()
    return result
