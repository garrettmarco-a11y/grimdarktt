extends Node2D
class_name SquadLayer
## Draws the battlefield's squads: keeps one SquadToken per SquadState in a
## BattleState, points each token at its state's position, and turns mouse
## clicks into squad_clicked / empty_space_clicked (left button) and
## destination_clicked (right button).
##
## Must be a direct child of a GameBoard. Knows nothing about turns or phases
## and owns no battlefield or selection state.

signal squad_clicked(state: SquadState)
signal empty_space_clicked
## A right-click at `board_point` (board units), offered as a move destination.
signal destination_clicked(board_point: Vector2)

@export var token_scene: PackedScene = preload("res://scenes/units/SquadToken.tscn")

var _tokens: Dictionary = {}


## Shows every squad in `battle` and follows its later additions and removals.
func bind_battle(battle: BattleState) -> void:
    battle.squad_added.connect(_add_token)
    battle.squad_removed.connect(_remove_token)
    for state in battle.get_squads():
        _add_token(state)


func get_tokens() -> Array[SquadToken]:
    var tokens: Array[SquadToken] = []
    for child in get_children():
        if child is SquadToken:
            tokens.append(child)
    return tokens


func get_token(squad_id: StringName) -> SquadToken:
    return _tokens.get(squad_id)


## The topmost token under `local_point` (this layer's local pixels), or null.
func token_at(local_point: Vector2) -> SquadToken:
    var tokens := get_tokens()
    for i in range(tokens.size() - 1, -1, -1):
        var token := tokens[i]
        if token.contains_local_point(local_point - token.position):
            return token
    return null


## Shows `selected` as selected and every other squad as not selected.
func show_selection(selected: SquadState) -> void:
    for token in get_tokens():
        token.selected = selected != null and token.state == selected


func _add_token(state: SquadState) -> void:
    var token := token_scene.instantiate() as SquadToken
    token.name = String(state.squad_id)
    token.state = state
    _tokens[state.squad_id] = token
    add_child(token)
    state.position_changed.connect(_sync_token_position)
    _sync_token_position(state)
    token.snap_to_target()


func _remove_token(state: SquadState) -> void:
    var token: SquadToken = _tokens.get(state.squad_id)
    if token == null:
        return
    state.position_changed.disconnect(_sync_token_position)
    _tokens.erase(state.squad_id)
    remove_child(token)
    token.queue_free()


func _sync_token_position(state: SquadState) -> void:
    var token: SquadToken = _tokens.get(state.squad_id)
    var board := get_parent() as GameBoard
    if token and board:
        token.target_position = board.units_to_pixels(state.board_position)


func _unhandled_input(event: InputEvent) -> void:
    var click := event as InputEventMouseButton
    if click == null or not click.pressed:
        return
    var local_point := get_global_transform_with_canvas().affine_inverse() * click.position
    if click.button_index == MOUSE_BUTTON_RIGHT:
        var board := get_parent() as GameBoard
        if board:
            destination_clicked.emit(board.pixels_to_units(local_point))
            get_viewport().set_input_as_handled()
        return
    if click.button_index != MOUSE_BUTTON_LEFT:
        return
    var token := token_at(local_point)
    if token:
        squad_clicked.emit(token.state)
    else:
        empty_space_clicked.emit()
    get_viewport().set_input_as_handled()
