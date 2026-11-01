extends Node
class_name AssaultController
## Coordinates an assault order: validates it with AssaultRules, rolls melee
## hits, then wounds and saves with DamageRules, and hands the result to the
## shared CasualtyAllocator, which runs the defender's allocation, applies
## casualties and ends the attacking squad's activation. Has no input or
## drawing code.

signal assault_resolved(result: CombatResult)
signal assault_rejected(attacker: SquadState, target: SquadState, result: AssaultRules.OrderResult)

var dice := DiceRoller.new()
## Shared with the ShootingController; created here if none is supplied.
var allocator: CasualtyAllocator

var _turn_manager: TurnManager
var _activation: ActivationController


func bind(turn_manager: TurnManager, activation: ActivationController, battle: BattleState,
        casualty_allocator: CasualtyAllocator = null) -> void:
    _turn_manager = turn_manager
    _activation = activation
    allocator = casualty_allocator
    if allocator == null:
        allocator = CasualtyAllocator.new()
        allocator.bind(activation, battle)
    allocator.resolved.connect(_on_resolved)


## Orders `attacker` to assault `target`. A valid order always resolves and
## spends the activation, even if no model is engaged; if wounds go unsaved the
## activation ends once the defender has allocated them.
func order_assault(attacker: SquadState, target: SquadState) -> AssaultRules.OrderResult:
    var result := AssaultRules.OrderResult.ALLOCATION_PENDING if allocator.is_pending() else \
        AssaultRules.validate_order(attacker, target, _turn_manager.current_phase,
            _activation.is_active_squad(attacker))
    if result != AssaultRules.OrderResult.OK:
        assault_rejected.emit(attacker, target, result)
        return result
    var outcome := AssaultRules.resolve(attacker, target, dice)
    DamageRules.resolve_wounds_and_saves(outcome, dice)
    allocator.begin(outcome)
    return result


func _on_resolved(result: CombatResult) -> void:
    if result.attack_type == CombatResult.AttackType.MELEE:
        assault_resolved.emit(result)
