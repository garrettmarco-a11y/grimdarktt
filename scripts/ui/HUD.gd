extends CanvasLayer
class_name HUD
## Displays game state. Reads from the turn manager, selection and movement
## controller through signals only.

@onready var phase_banner: PhaseBanner = $PhaseBanner
@onready var squad_info_panel: SquadInfoPanel = $SquadInfoPanel
@onready var order_feedback: Label = $OrderFeedback


func bind_turn_manager(turn_manager: TurnManager) -> void:
    turn_manager.phase_changed.connect(phase_banner.show_phase)


func bind_selection(selection: SelectionManager) -> void:
    selection.selection_changed.connect(squad_info_panel.show_squad)


func bind_movement(movement: MovementController) -> void:
    movement.move_ordered.connect(_on_move_ordered)
    movement.move_rejected.connect(_on_move_rejected)


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
        MovementRules.Result.MOVEMENT_COMPLETE:
            order_feedback.text = "%s has finished moving" % state.data.display_name
        MovementRules.Result.OFF_BOARD:
            order_feedback.text = "Destination is off the battlefield"
        MovementRules.Result.OUT_OF_RANGE:
            order_feedback.text = "Out of range: %.1f > %s" % [
                MovementRules.distance(state.turn_start_position, destination),
                String.num(state.movement_allowance)]
