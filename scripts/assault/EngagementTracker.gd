extends RefCounted
class_name EngagementTracker
## The round-long record of which squads are committed to which engagement.
##
## Three things are kept deliberately apart:
##   1. Commitment (this class): a squad that charges, is charged, or fights in
##      an engagement is committed to that one engagement until the round ends.
##      Only explicit calls change it: record_charge(), commit() and the
##      merges they perform. Physical contact never changes it by itself.
##   2. Physical contact (EngagementRules / ModelPlacement): where bases touch
##      right now. It is read to propose groups, never stored here, and it may
##      change (casualties, consolidation) without changing any commitment.
##   3. Attack targets: the enemy squad each committed squad directs its attacks
##      at. A charger's target is fixed when it charges; others are declared
##      later. Stored per squad, separate from membership.
##
## Squads are recorded by squad_id, so a destroyed squad stays recorded for the
## rest of the round although it has left the battlefield. Everything resets
## when a new round (turn) starts. Owned by Main and shared by the charge and
## assault controllers.
##
## Rules (approved by the project lead): a squad may take part in only one
## engagement per round; an unengaged squad may charge a squad in an existing
## engagement and so joins it; joining two engagements merges them into one.

enum Origin { ONGOING, CHARGE }


## One engagement this round.
class Engagement:
    extends RefCounted
    ## Stable id for the round.
    var id := 0
    ## Committed squads, by squad_id, in the order they were committed.
    var members: Array[StringName] = []
    ## CHARGE if any member charged into it this round, else ONGOING.
    var origin := Origin.ONGOING
    ## Order of the first successful charge into it this round (-1 if none);
    ## charging engagements resolve in this order.
    var charge_order := -1
    var resolved := false

    func has_member(squad_id: StringName) -> bool:
        return squad_id in members


signal engagements_changed

## The round this record belongs to (the TurnManager turn number).
var round_number := 0

var _engagements: Array[Engagement] = []
## squad_id -> Engagement
var _by_squad := {}
## squad_id -> squad_id of the target it declared when charging (locked).
var _charge_targets := {}
## squad_id -> squad_id of the squad it attacks in the Assault phase.
var _attack_targets := {}
var _next_id := 1
var _charges := 0


## Resets the record at the start of every round.
func bind(turn_manager: TurnManager) -> void:
    turn_manager.turn_started.connect(reset)


func reset(new_round := 0) -> void:
    round_number = new_round
    _engagements.clear()
    _by_squad.clear()
    _charge_targets.clear()
    _attack_targets.clear()
    _next_id = 1
    _charges = 0
    engagements_changed.emit()


## Every engagement this round, in creation order (merged ones excluded).
func get_engagements() -> Array[Engagement]:
    return _engagements.duplicate()


func get_engagement(engagement_id: int) -> Engagement:
    for engagement in _engagements:
        if engagement.id == engagement_id:
            return engagement
    return null


## The engagement `squad_id` is committed to this round, or null.
func engagement_of(squad_id: StringName) -> Engagement:
    return _by_squad.get(squad_id)


func is_committed(squad_id: StringName) -> bool:
    return _by_squad.has(squad_id)


## Records a successful charge by `charger` against `target`. The charger
## joins the target's engagement (merging if the target is already committed),
## or both start a new one; the engagement becomes a charging engagement, and
## the charger's attack target is locked to `target`. Refused (null) if the
## charger is already committed this round, or the target's engagement has
## already been resolved.
func record_charge(charger: StringName, target: StringName) -> Engagement:
    if is_committed(charger):
        push_error("EngagementTracker.record_charge: %s is already committed this round" % charger)
        return null
    var existing := engagement_of(target)
    if existing and existing.resolved:
        push_error("EngagementTracker.record_charge: %s's engagement is already resolved" % target)
        return null
    var engagement := commit([target, charger], Origin.CHARGE)
    if engagement == null:
        return null
    _charges += 1
    if engagement.charge_order < 0:
        engagement.charge_order = _charges
    _charge_targets[charger] = target
    _attack_targets[charger] = target
    engagements_changed.emit()
    return engagement


## Commits `squad_ids` to one engagement. Squads not yet committed join it;
## squads already committed bring their engagements, which are merged into the
## earliest of them. Returns the engagement, or null if any involved
## engagement is already resolved (a squad fights only once per round).
func commit(squad_ids: Array, origin := Origin.ONGOING) -> Engagement:
    var involved: Array[Engagement] = []
    for squad_id in squad_ids:
        var engagement := engagement_of(squad_id)
        if engagement and engagement not in involved:
            if engagement.resolved:
                push_error("EngagementTracker.commit: %s's engagement is already resolved" % squad_id)
                return null
            involved.append(engagement)
    var result: Engagement
    if involved.is_empty():
        result = Engagement.new()
        result.id = _next_id
        _next_id += 1
        _engagements.append(result)
    else:
        involved.sort_custom(func(a: Engagement, b: Engagement) -> bool: return a.id < b.id)
        result = involved[0]
        for other in involved.slice(1):
            _merge(result, other)
    for squad_id in squad_ids:
        if not result.has_member(squad_id):
            result.members.append(squad_id)
            _by_squad[squad_id] = result
    if origin == Origin.CHARGE:
        result.origin = Origin.CHARGE
    engagements_changed.emit()
    return result


func mark_resolved(engagement: Engagement) -> void:
    engagement.resolved = true
    engagements_changed.emit()


## The target `squad_id` declared when it charged this round, or &"".
func charge_target_of(squad_id: StringName) -> StringName:
    return _charge_targets.get(squad_id, &"")


## The squad `squad_id` attacks this round, or &"" if none is set yet.
func attack_target_of(squad_id: StringName) -> StringName:
    return _attack_targets.get(squad_id, &"")


## Sets `squad_id`'s attack target. Refused for an uncommitted squad, for a
## target outside its engagement, and for a charger, whose target is locked to
## the squad it charged.
func set_attack_target(squad_id: StringName, target: StringName) -> bool:
    var engagement := engagement_of(squad_id)
    if engagement == null or not engagement.has_member(target) or target == squad_id:
        push_error("EngagementTracker.set_attack_target: %s cannot target %s" % [squad_id, target])
        return false
    if _charge_targets.has(squad_id) and _charge_targets[squad_id] != target:
        push_error("EngagementTracker.set_attack_target: %s is locked to its charge target %s" % [squad_id, _charge_targets[squad_id]])
        return false
    _attack_targets[squad_id] = target
    engagements_changed.emit()
    return true


func _merge(into: Engagement, other: Engagement) -> void:
    for squad_id in other.members:
        if not into.has_member(squad_id):
            into.members.append(squad_id)
        _by_squad[squad_id] = into
    if other.origin == Origin.CHARGE:
        into.origin = Origin.CHARGE
    if other.charge_order >= 0 and (into.charge_order < 0 or other.charge_order < into.charge_order):
        into.charge_order = other.charge_order
    _engagements.erase(other)
