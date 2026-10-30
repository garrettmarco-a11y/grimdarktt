extends RefCounted
class_name BattleState
## The squads currently on the battlefield, keyed by their stable squad id.
##
## Owns the authoritative SquadState objects. Views (SquadLayer) and selection
## follow it through squad_added / squad_removed.

signal squad_added(state: SquadState)
signal squad_removed(state: SquadState)

var _squads: Dictionary = {}


func add_squad(state: SquadState) -> bool:
    if state == null or state.squad_id == &"":
        push_error("BattleState.add_squad: squad has no id")
        return false
    if _squads.has(state.squad_id):
        push_error("BattleState.add_squad: duplicate squad id %s" % state.squad_id)
        return false
    _squads[state.squad_id] = state
    squad_added.emit(state)
    return true


func remove_squad(squad_id: StringName) -> bool:
    var state: SquadState = _squads.get(squad_id)
    if state == null:
        push_error("BattleState.remove_squad: no squad %s" % squad_id)
        return false
    _squads.erase(squad_id)
    squad_removed.emit(state)
    return true


func get_squad(squad_id: StringName) -> SquadState:
    return _squads.get(squad_id)


## Squads in the order they were added.
func get_squads() -> Array[SquadState]:
    var squads: Array[SquadState] = []
    squads.assign(_squads.values())
    return squads
