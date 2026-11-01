extends Node
class_name ShootingController
## Coordinates a shooting order: validates it with ShootingRules, rolls hits,
## then wounds and saves with DamageRules, and hands the result to the shared
## CasualtyAllocator, which runs the defender's allocation, applies casualties
## and ends the firing squad's activation. Has no input or drawing code.

signal shot_resolved(result: CombatResult)
signal shot_rejected(firing: SquadState, target: SquadState, result: ShootingRules.OrderResult)
## The defender must allocate `wounds_left` more unsaved wounds from a shot.
signal allocation_required(result: CombatResult, wounds_left: int)

var line_of_sight := LineOfSight.new()
var dice := DiceRoller.new()
## Shared with the AssaultController; created here if none is supplied.
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
    allocator.allocation_required.connect(_on_allocation_required)
    allocator.resolved.connect(_on_resolved)


func is_allocation_pending() -> bool:
    return allocator.is_pending()


func get_pending_result() -> CombatResult:
    return allocator.get_pending_result()


func get_wounds_left() -> int:
    return allocator.get_wounds_left()


## Orders `firing` to shoot at `target`. A valid order always resolves and
## spends the activation, even if no model can fire; if wounds go unsaved the
## activation ends once the defender has allocated them.
func order_shot(firing: SquadState, target: SquadState) -> ShootingRules.OrderResult:
    var result := ShootingRules.OrderResult.ALLOCATION_PENDING if allocator.is_pending() else \
        ShootingRules.validate_order(firing, target, _turn_manager.current_phase,
            _activation.is_active_squad(firing))
    if result != ShootingRules.OrderResult.OK:
        shot_rejected.emit(firing, target, result)
        return result
    var outcome := ShootingRules.resolve(firing, target, line_of_sight, dice)
    DamageRules.resolve_wounds_and_saves(outcome, dice)
    allocator.begin(outcome)
    return result


## The defender allocates one pending unsaved wound to model `model_id`.
func allocate_wound(model_id: int) -> DamageRules.AllocationResult:
    return allocator.allocate_wound(model_id)


func _on_allocation_required(result: CombatResult, wounds_left: int) -> void:
    if result.attack_type == CombatResult.AttackType.RANGED:
        allocation_required.emit(result, wounds_left)


func _on_resolved(result: CombatResult) -> void:
    if result.attack_type == CombatResult.AttackType.RANGED:
        shot_resolved.emit(result)
