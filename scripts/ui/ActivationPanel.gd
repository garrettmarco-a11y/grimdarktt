extends PanelContainer
class_name ActivationPanel
## Shows who may activate, the active squad and the squads already activated
## this phase, with one button to activate the selected squad or end the
## current activation, plus a Regroup button for a Shaken squad. It only
## reads state and sends orders to the ActivationController and
## MoraleController; it never changes game state itself.

@onready var player_label: Label = %ActivePlayerLabel
@onready var active_label: Label = %ActiveSquadLabel
@onready var activated_label: Label = %ActivatedLabel
@onready var action_button: Button = %ActionButton
@onready var hint_label: Label = %HintLabel
@onready var regroup_button: Button = %RegroupButton

var _activation: ActivationController
var _selection: SelectionManager
var _morale: MoraleController


func bind(activation: ActivationController, selection: SelectionManager) -> void:
    _activation = activation
    _selection = selection
    activation.activation_changed.connect(refresh)
    selection.selection_changed.connect(func(_state): refresh())
    action_button.pressed.connect(_on_action_pressed)
    regroup_button.pressed.connect(_on_regroup_pressed)
    refresh()


func bind_morale(morale: MoraleController) -> void:
    _morale = morale
    morale.regrouped.connect(func(_state): refresh())
    morale.morale_tested.connect(func(_result): refresh())
    refresh()


func refresh() -> void:
    if _activation == null:
        return
    var player := _activation.get_active_player()
    player_label.text = "Player %d to activate" % player if player != TurnManager.NO_PLAYER else "No activations left"
    var active := _activation.active_squad
    active_label.text = "Active: %s" % (active.data.display_name if active else "none")
    var names := PackedStringArray()
    for state in _activation.get_activated_squads():
        names.append(state.data.display_name)
    activated_label.text = "Done: %s" % (", ".join(names) if not names.is_empty() else "none")

    regroup_button.visible = _morale != null and active != null \
        and _morale.can_regroup(active) == MoraleController.RegroupResult.OK
    if active:
        action_button.text = "End activation"
        action_button.disabled = _activation.locked
        if _activation.locked:
            hint_label.text = "Waiting for wound allocation"
            return
        if not MoraleRules.may_attack(active) and _activation.get_phase() == TurnManager.Phase.SHOOTING:
            hint_label.text = "Morale: cannot shoot this turn"
            return
        match _activation.get_phase():
            TurnManager.Phase.MOVEMENT:
                hint_label.text = "Right-click to move"
            TurnManager.Phase.SHOOTING:
                hint_label.text = "Right-click an enemy squad to shoot"
            TurnManager.Phase.CHARGE:
                hint_label.text = "Right-click an enemy squad to charge, or end to hold"
            _:
                hint_label.text = ""
        return
    action_button.text = "Activate"
    var selected := _selection.selected_squad
    var result := _activation.can_activate(selected)
    action_button.disabled = result != ActivationController.Result.OK
    match result:
        ActivationController.Result.OK:
            hint_label.text = "Activate %s" % selected.data.display_name
        ActivationController.Result.NO_SQUAD:
            hint_label.text = "Select one of your squads"
        ActivationController.Result.WRONG_PLAYER:
            hint_label.text = "Not Player %d's squad" % player
        ActivationController.Result.ALREADY_ACTIVATED:
            hint_label.text = "Already activated this phase"
        ActivationController.Result.NOT_ELIGIBLE:
            hint_label.text = "Not eligible this phase"
        ActivationController.Result.ENGAGED:
            hint_label.text = "Engaged this round: fights in Assault"
        _:
            hint_label.text = ""


func _on_action_pressed() -> void:
    if _activation.active_squad:
        _activation.end_activation()
    else:
        _activation.activate(_selection.selected_squad)


func _on_regroup_pressed() -> void:
    if _morale and _activation.active_squad:
        _morale.regroup(_activation.active_squad)
