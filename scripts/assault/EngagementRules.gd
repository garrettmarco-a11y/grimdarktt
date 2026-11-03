extends RefCounted
class_name EngagementRules
## Physical contact between squads and engagement grouping, as pure functions.
## Reads squads and an EngagementTracker; changes nothing.
##
## Rules (approved by the project lead):
##   - Two models are in base-to-base contact when their bases are at most
##     ModelPlacement.ENGAGEMENT_CONTACT apart edge to edge.
##   - Only contact between enemy models links squads. Friendly contact,
##     proximity and support distance never do.
##   - An engagement is a connected group of squads so linked.
##   - Round-long commitment (EngagementTracker) is authoritative: squads
##     committed to the same engagement stay grouped whatever their contacts
##     now; contact between squads committed to different engagements does not
##     merge them (merging is an explicit tracker operation); and squads whose
##     engagement is already resolved take no further part this round.


## Every enemy model pair currently in base-to-base contact, as
## [squad, model, other squad, other model], in squad_id then model_id order.
static func contact_pairs(squads: Array) -> Array:
    var ordered := _sorted(squads)
    var pairs := []
    for i in ordered.size():
        for j in range(i + 1, ordered.size()):
            var a: SquadState = ordered[i]
            var b: SquadState = ordered[j]
            if a.get_player() == b.get_player():
                continue
            for ma in a.get_living_models():
                for mb in b.get_living_models():
                    if ModelPlacement.models_in_contact(ma, mb):
                        pairs.append([a, ma, b, mb])
    return pairs


## True if any living model of `a` is in base contact with one of `b`'s and
## they are enemies.
static func squads_in_contact(a: SquadState, b: SquadState) -> bool:
    if a == b or a.get_player() == b.get_player():
        return false
    for ma in a.get_living_models():
        for mb in b.get_living_models():
            if ModelPlacement.models_in_contact(ma, mb):
                return true
    return false


## True if `model` (of `squad`) is in base contact with any living enemy model
## among `squads`.
static func model_in_enemy_contact(squad: SquadState, model: ModelState, squads: Array) -> bool:
    for other in squads:
        if other.get_player() == squad.get_player():
            continue
        for enemy in other.get_living_models():
            if ModelPlacement.models_in_contact(model, enemy):
                return true
    return false


## Proposed engagement groups among `squads` (the squads on the battlefield),
## from current enemy contact and the round's commitments in `tracker` (none if
## null). Each group is a Dictionary:
##   "squads":      Array[SquadState] in the group, by squad_id
##   "engagements": Array[int] ids of tracker engagements it contains, sorted
## Groups are ordered by their lowest squad_id. A group of one (an uncommitted
## squad touching no enemy) is not an engagement and is left out. Nothing is
## committed: callers commit a group explicitly through the tracker.
static func group(squads: Array, tracker: EngagementTracker = null) -> Array:
    var nodes: Array[SquadState] = []
    for squad in _sorted(squads):
        var engagement := tracker.engagement_of(squad.squad_id) if tracker else null
        if engagement and engagement.resolved:
            continue  # already fought this round
        nodes.append(squad)
    var parent := {}
    for squad in nodes:
        parent[squad.squad_id] = squad.squad_id
    # Commitment links, whatever the geometry.
    if tracker:
        for squad in nodes:
            var engagement := tracker.engagement_of(squad.squad_id)
            if engagement:
                for other in nodes:
                    if engagement.has_member(other.squad_id):
                        _union(parent, squad.squad_id, other.squad_id)
    # Contact links, except between squads committed to different engagements.
    for i in nodes.size():
        for j in range(i + 1, nodes.size()):
            var a := nodes[i]
            var b := nodes[j]
            if tracker:
                var ea := tracker.engagement_of(a.squad_id)
                var eb := tracker.engagement_of(b.squad_id)
                if ea and eb and ea != eb:
                    continue
            if squads_in_contact(a, b):
                _union(parent, a.squad_id, b.squad_id)
    var by_root := {}
    for squad in nodes:
        var root: StringName = _find(parent, squad.squad_id)
        if not by_root.has(root):
            by_root[root] = []
        by_root[root].append(squad)
    var groups := []
    for root in by_root:
        var members: Array = by_root[root]
        var ids: Array[int] = []
        if tracker:
            for squad in members:
                var engagement := tracker.engagement_of(squad.squad_id)
                if engagement and engagement.id not in ids:
                    ids.append(engagement.id)
        ids.sort()
        if members.size() < 2 and ids.is_empty():
            continue
        groups.append({"squads": members, "engagements": ids})
    groups.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
        return String(x.squads[0].squad_id) < String(y.squads[0].squad_id))
    return groups


static func _sorted(squads: Array) -> Array:
    var ordered := squads.duplicate()
    ordered.sort_custom(func(a: SquadState, b: SquadState) -> bool: return String(a.squad_id) < String(b.squad_id))
    return ordered


static func _find(parent: Dictionary, key: StringName) -> StringName:
    while parent[key] != key:
        parent[key] = parent[parent[key]]
        key = parent[key]
    return key


static func _union(parent: Dictionary, a: StringName, b: StringName) -> void:
    var ra := _find(parent, a)
    var rb := _find(parent, b)
    if ra == rb:
        return
    if String(ra) < String(rb):
        parent[rb] = ra
    else:
        parent[ra] = rb
