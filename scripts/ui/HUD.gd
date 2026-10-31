extends CanvasLayer
class_name HUD
## Displays game state. Reads from the turn manager, selection, activation,
## movement and shooting controllers through signals only.

@onready var phase_banner: PhaseBanner = $PhaseBanner
@onready var squad_info_panel: SquadInfoPanel = $SquadInfoPanel
@onready var order_feedback: Label = $OrderFeedback
@onready var activation_panel: ActivationPanel = $ActivationPanel
@onready var allocation_panel: AllocationPanel = $AllocationPanel


func bind_turn_manager(turn_manager: TurnManager) -> void:
    turn_manager.phase_changed.connect(phase_banner.show_phase)


func bind_selection(selection: SelectionManager) -> void:
    selection.selection_changed.connect(squad_info_panel.show_squad)


func bind_activation(activation: ActivationController, selection: SelectionManager) -> void:
    activation_panel.bind(activation, selection)


func bind_movement(movement: MovementController) -> void:
    movement.move_ordered.connect(_on_move_ordered)
    movement.move_rejected.connect(_on_move_rejected)


func bind_shooting(shooting: ShootingController) -> void:
    shooting.shot_resolved.connect(_on_shot_resolved)
    shooting.shot_rejected.connect(_on_shot_rejected)
    shooting.allocation_required.connect(_on_allocation_required)
    allocation_panel.bind(shooting)


func _on_move_ordered(state: SquadState, _from: Vector2, _to: Vector2) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = "%s moving (%.1f left)" % [state.data.display_name, state.get_remaining_movement()]


func _on_move_rejected(state: SquadState, destination: Vector2, result: MovementRules.Result) -> void:
    order_feedback.modulate = Color(1.0, 0.45, 0.4)
    match result:
        MovementRules.Result.NO_SQUAD:
            order_feedback.text = "Select a squad to move"
        MovementRules.Result.WRONG_PHASE:
            order_feedback.text = "Move orders only in the Movement phase"
        MovementRules.Result.NOT_ACTIVATED:
            order_feedback.text = "Activate %s before moving it" % state.data.display_name
        MovementRules.Result.MOVEMENT_COMPLETE:
            order_feedback.text = "%s has finished moving" % state.data.display_name
        MovementRules.Result.OFF_BOARD:
            order_feedback.text = "Destination is off the battlefield"
        MovementRules.Result.OUT_OF_RANGE:
            order_feedback.text = "Out of range: %.1f > %s" % [
                MovementRules.distance(state.turn_start_position, destination),
                String.num(state.movement_allowance)]


func _on_shot_resolved(result: ShootingResult) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = format_shooting_result(result)


func _on_shot_rejected(_firing: SquadState, _target: SquadState, result: ShootingRules.OrderResult) -> void:
    order_feedback.modulate = Color(1.0, 0.45, 0.4)
    match result:
        ShootingRules.OrderResult.NO_SQUAD:
            order_feedback.text = "Activate a squad to shoot"
        ShootingRules.OrderResult.NO_TARGET:
            order_feedback.text = "Choose a target squad"
        ShootingRules.OrderResult.WRONG_PHASE:
            order_feedback.text = "Shooting only in the Shooting phase"
        ShootingRules.OrderResult.NOT_ACTIVATED:
            order_feedback.text = "Activate the squad before shooting"
        ShootingRules.OrderResult.OWN_SQUAD:
            order_feedback.text = "Cannot shoot your own squad"
        ShootingRules.OrderResult.ALLOCATION_PENDING:
            order_feedback.text = "Allocate the pending wounds first"


func _on_allocation_required(result: ShootingResult, _wounds_left: int) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = format_shooting_result(result)


static func format_shooting_result(result: ShootingResult) -> String:
    var lines := PackedStringArray()
    lines.append("%s shot %s" % [result.firing_squad.data.display_name, result.target_squad.data.display_name])
    lines.append("Fired: %d  Unable: %d" % [result.get_eligible_count(), result.get_ineligible_count()])
    lines.append("Attacks %d: %d hit, %d miss" % [result.get_total_attacks(), result.get_hits(), result.get_misses()])
    lines.append("Wounds %d: %d saved, %d unsaved" % [result.get_wounds(), result.get_saves(), result.get_unsaved_wounds()])
    if result.get_eligible_count() == 0:
        lines.append("No model could fire")
    for model in result.model_results:
        if not model.is_eligible():
            lines.append("%s: %s" % [model.model_name, eligibility_text(model.eligibility)])
        elif model.hits == 0:
            lines.append("%s: %d/%d hit" % [model.model_name, model.hits, model.rolls.size()])
        else:
            lines.append("%s: %d/%d hit, %d wnd (%d+), %d saved (%s)" % [model.model_name, model.hits,
                model.rolls.size(), model.wounds, model.wound_target, model.saves, save_text(model.save_target)])
    var casualties := result.get_casualties()
    lines.append("Casualties: %s" % (", ".join(casualties) if not casualties.is_empty() else "none"))
    var target := result.target_squad.data.display_name
    if result.target_destroyed:
        lines.append("%s destroyed" % target)
    elif result.get_unsaved_wounds() > result.allocations.size():
        lines.append("%s: allocating wounds" % target)
    else:
        lines.append("%s: %d models left" % [target, result.models_remaining])
    return "\n".join(lines)


static func save_text(target: int) -> String:
    if target <= 0:
        return "no save"
    if not DamageRules.can_be_saved(target):
        return "%d+, unsavable" % target
    return "%d+" % target


static func eligibility_text(eligibility: int) -> String:
    match eligibility:
        ShootingRules.Eligibility.NO_RANGED_WEAPON:
            return "no ranged weapon"
        ShootingRules.Eligibility.OUT_OF_RANGE:
            return "out of range"
        ShootingRules.Eligibility.NO_LINE_OF_SIGHT:
            return "no line of sight"
    return "can fire"
