extends Node
class_name SelectionManager
## Tracks which squad is selected. Selection is an interface operation only:
## it never activates a squad and is independent of turns and phases.
##
## The selection is the squad's SquadState (identified by its stable squad
## id), never a visual token, list index or position.

signal selection_changed(state: SquadState)

var selected_squad: SquadState = null


## Clears the selection when its squad is removed from `battle`.
func bind_battle(battle: BattleState) -> void:
    battle.squad_removed.connect(_on_squad_removed)


func select(state: SquadState) -> void:
    if state == selected_squad:
        return
    selected_squad = state
    selection_changed.emit(selected_squad)


func clear_selection() -> void:
    select(null)


func get_selected_squad_id() -> StringName:
    return selected_squad.squad_id if selected_squad else &""


func _on_squad_removed(state: SquadState) -> void:
    if state == selected_squad:
        clear_selection()
