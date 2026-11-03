extends RefCounted
class_name CohesionRules
## Squad cohesion, as pure functions. Informational only: being out of
## cohesion has no rules effect yet, and nothing ever moves a model to restore
## it. Cohesion is separate from the physical no-overlap rule.
##
## Rule (approved by the project lead): a squad is in cohesion when its living
## models form one connected chain, two models being linked when their bases
## are no more than MAX_GAP apart edge to edge. A squad with one living model
## is always in cohesion.

## Largest edge-to-edge gap between linked bases, in board units.
const MAX_GAP := 1.0
const EPSILON := 0.001


static func are_linked(a: ModelState, b: ModelState) -> bool:
    return a.position.distance_to(b.position) - a.get_base_radius() - b.get_base_radius() <= MAX_GAP + EPSILON


## The squad's living models split into connected groups; the leader's group
## first, then the others in original model order.
static func groups(state: SquadState) -> Array:
    var remaining := state.get_living_models()
    var result := []
    while not remaining.is_empty():
        var group: Array[ModelState] = [remaining.pop_front()]
        var i := 0
        while i < group.size():
            for other in remaining.duplicate():
                if are_linked(group[i], other):
                    group.append(other)
                    remaining.erase(other)
            i += 1
        group.sort_custom(func(a: ModelState, b: ModelState) -> bool: return a.model_id < b.model_id)
        result.append(group)
    return result


static func is_coherent(state: SquadState) -> bool:
    return groups(state).size() <= 1


## Living models not connected to the leader's group, in original order.
static func out_of_cohesion(state: SquadState) -> Array[ModelState]:
    var stragglers: Array[ModelState] = []
    var all := groups(state)
    for i in range(1, all.size()):
        stragglers.append_array(all[i])
    stragglers.sort_custom(func(a: ModelState, b: ModelState) -> bool: return a.model_id < b.model_id)
    return stragglers


## "Cohesion: OK" or "Out of cohesion: N model(s)", for the UI.
static func describe(state: SquadState) -> String:
    var count := out_of_cohesion(state).size()
    if count == 0:
        return "Cohesion: OK"
    return "Out of cohesion: %d model%s" % [count, "" if count == 1 else "s"]
