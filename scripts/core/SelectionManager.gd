extends Node
class_name SelectionManager
## Tracks which squad is selected. Selection is an interface operation only:
## it never activates a squad and is independent of turns and phases.
##
## The selection is held as a reference to the squad's token, so it does not
## depend on list order or position.

signal selection_changed(token: SquadToken)

var selected_squad: SquadToken = null


func select(token: SquadToken) -> void:
    if token == selected_squad:
        return
    if selected_squad and selected_squad.tree_exiting.is_connected(clear_selection):
        selected_squad.tree_exiting.disconnect(clear_selection)
    selected_squad = token
    if token:
        token.tree_exiting.connect(clear_selection, CONNECT_ONE_SHOT)
    selection_changed.emit(selected_squad)


func clear_selection() -> void:
    select(null)


func get_selected_squad_id() -> StringName:
    return selected_squad.get_squad_id() if selected_squad else &""
