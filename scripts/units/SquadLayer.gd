@tool
extends Node2D
class_name SquadLayer
## Holds the battlefield's SquadToken children: places them from board units
## and turns mouse clicks into squad_clicked / empty_space_clicked.
##
## Must be a direct child of a GameBoard. Knows nothing about turns or phases.

signal squad_clicked(token: SquadToken)
signal empty_space_clicked


func _ready() -> void:
    place_tokens()


func get_tokens() -> Array[SquadToken]:
    var tokens: Array[SquadToken] = []
    for child in get_children():
        if child is SquadToken:
            tokens.append(child)
    return tokens


func get_token(squad_id: StringName) -> SquadToken:
    for token in get_tokens():
        if token.get_squad_id() == squad_id:
            return token
    return null


## Moves every token to the pixel position of its board_position.
func place_tokens() -> void:
    var board := get_parent() as GameBoard
    if board == null:
        return
    for token in get_tokens():
        token.position = board.units_to_pixels(token.board_position)


## The topmost token under `local_point` (this layer's local pixels), or null.
func token_at(local_point: Vector2) -> SquadToken:
    var tokens := get_tokens()
    for i in range(tokens.size() - 1, -1, -1):
        var token := tokens[i]
        if token.contains_local_point(local_point - token.position):
            return token
    return null


## Shows `selected_token` as selected and every other token as not selected.
func show_selection(selected_token: SquadToken) -> void:
    for token in get_tokens():
        token.selected = token == selected_token


func _unhandled_input(event: InputEvent) -> void:
    if Engine.is_editor_hint():
        return
    var click := event as InputEventMouseButton
    if click == null or click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
        return
    var token := token_at(get_global_transform_with_canvas().affine_inverse() * click.position)
    if token:
        squad_clicked.emit(token)
    else:
        empty_space_clicked.emit()
    get_viewport().set_input_as_handled()
