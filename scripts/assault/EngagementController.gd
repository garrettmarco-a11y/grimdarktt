extends Node
class_name EngagementController
## Runs the Assault phase as a procedure: discovers the round's engagements,
## then fights them one at a time. For each engagement it collects every
## squad's attack target, snapshots which models may attack, rolls every
## strike (hits, wounds, saves), and only then hands all the strikes to the
## CasualtyAllocator's queue, where each defending player allocates and
## casualties are applied. When the last engagement is done it completes the
## phase. Has no input or drawing code.
##
## Rules (approved by the project lead):
##   - Engagements are the groups EngagementRules proposes from current enemy
##     contact and the round's commitments; each is committed explicitly
##     through the EngagementTracker before fighting.
##   - Charging engagements (with a successful charge this round) are fought
##     first, in the order of their first charge; then ongoing ones, ordered by
##     their first squad in turn order (priority player first, then squad_id).
##   - Within an engagement, squads act in turn order: alternating players,
##     priority player first, each player's squads by squad_id.
##   - Every squad attacks exactly one enemy squad of its engagement. A charger
##     keeps the target it declared when charging; a squad with only one
##     possible target gets it automatically; any other declares, in turn
##     order. No strike is rolled until every declaration is made.
##   - Eligibility is snapshotted before any strike: contact, or support within
##     AssaultRules.SUPPORT_DISTANCE of a same-squad model in contact; Broken
##     squads, contact only. A snapshotted model attacks even if killed in the
##     same exchange: every strike is rolled before any casualty is applied.
##   - Strikes are rolled and allocated in turn order.
##   - Once every casualty is applied the engagement is scored side-wide
##     (CombatScoring) and every surviving squad of the losing side takes an
##     assault-loss test through the MoraleController, in squad_id order: a
##     failure makes it Broken and it falls back at once (existing rules).
##   - Only then is the engagement marked resolved and the next one begun.

signal engagement_started(engagement: EngagementTracker.Engagement, squads: Array)
## `squad` must declare one of `options` (enemy squads) as its target.
signal target_declaration_required(squad: SquadState, options: Array)
signal target_declared(squad: SquadState, target: SquadState)
## Every strike of the engagement is rolled; allocation begins next.
signal strikes_rolled(engagement: EngagementTracker.Engagement, results: Array[CombatResult])
## The engagement's casualties are all allocated and applied (it is not yet
## scored or resolved).
signal engagement_fought(engagement: EngagementTracker.Engagement, results: Array[CombatResult])
## Scored, assault-loss tests taken, and marked resolved.
signal engagement_resolved(outcome: EngagementOutcome)
signal assault_completed

var dice := DiceRoller.new()
## Battlefield terrain, for the defenders' cover.
var terrain: TerrainMap
## Takes the losing side's assault-loss tests; with none bound, losers are
## identified but untested.
var morale: MoraleController
## Every engagement finished this phase, in order.
var outcomes: Array[EngagementOutcome] = []

var _turn_manager: TurnManager
var _battle: BattleState
var _tracker: EngagementTracker
var _allocator: CasualtyAllocator

var _running := false
var _order: Array[EngagementTracker.Engagement] = []
var _current: EngagementTracker.Engagement
var _current_squads: Array[SquadState] = []
var _pending_declarers: Array[SquadState] = []
var _awaiting_allocation := false


func bind(turn_manager: TurnManager, battle: BattleState, tracker: EngagementTracker,
        allocator: CasualtyAllocator) -> void:
    _turn_manager = turn_manager
    _battle = battle
    _tracker = tracker
    _allocator = allocator
    allocator.queue_resolved.connect(_on_queue_resolved)
    turn_manager.register_procedure(TurnManager.Phase.ASSAULT, _begin)


func is_running() -> bool:
    return _running


## The engagement being fought, or null.
func get_current_engagement() -> EngagementTracker.Engagement:
    return _current


## Squads of the current engagement, in turn order.
func get_current_squads() -> Array[SquadState]:
    return _current_squads.duplicate()


## The squad that must declare a target now, or null.
func get_declaring_squad() -> SquadState:
    return _pending_declarers.front() if not _pending_declarers.is_empty() else null


## Enemy squads of the current engagement that `squad` may target.
func get_target_options(squad: SquadState) -> Array[SquadState]:
    var options: Array[SquadState] = []
    for other in _current_squads:
        if other.get_player() != squad.get_player() and other.get_model_count() > 0:
            options.append(other)
    return options


## The declaring squad declares `target`. Refused unless it is that squad's
## turn to declare and `target` is one of its options.
func declare_target(squad: SquadState, target: SquadState) -> bool:
    if squad == null or squad != get_declaring_squad() or target not in get_target_options(squad):
        return false
    if not _tracker.set_attack_target(squad.squad_id, target.squad_id):
        return false
    _pending_declarers.pop_front()
    target_declared.emit(squad, target)
    _ask_next_declaration()
    return true


## Engagements to fight this phase, in resolution order. Commits each proposed
## group explicitly (merging engagements a bridging squad connects).
func discover_engagements() -> Array[EngagementTracker.Engagement]:
    var found: Array[EngagementTracker.Engagement] = []
    for group in EngagementRules.group(_battle.get_squads(), _tracker):
        var ids: Array = group.squads.map(func(s: SquadState) -> StringName: return s.squad_id)
        var engagement := _tracker.commit(ids)
        if engagement and engagement not in found:
            found.append(engagement)
    var charging := found.filter(func(e): return e.charge_order >= 0)
    charging.sort_custom(func(a, b) -> bool: return a.charge_order < b.charge_order)
    var ongoing := found.filter(func(e): return e.charge_order < 0)
    ongoing.sort_custom(func(a, b) -> bool: return _order_key(a) < _order_key(b))
    var ordered: Array[EngagementTracker.Engagement] = []
    ordered.assign(charging + ongoing)
    return ordered


## Squads of `engagement` still on the battlefield, in turn order.
func squads_in_turn_order(engagement: EngagementTracker.Engagement) -> Array[SquadState]:
    var first := _turn_manager.priority_player
    var sides := {first: [], TurnManager.other_player(first): []}
    for squad_id in engagement.members:
        var squad := _battle.get_squad(squad_id)
        if squad and squad.get_model_count() > 0 and sides.has(squad.get_player()):
            sides[squad.get_player()].append(squad)
    for side in sides.values():
        side.sort_custom(func(a: SquadState, b: SquadState) -> bool: return String(a.squad_id) < String(b.squad_id))
    var ordered: Array[SquadState] = []
    var a: Array = sides[first]
    var b: Array = sides[TurnManager.other_player(first)]
    for i in maxi(a.size(), b.size()):
        if i < a.size():
            ordered.append(a[i])
        if i < b.size():
            ordered.append(b[i])
    return ordered


func _begin() -> void:
    _running = true
    outcomes.clear()
    _order = discover_engagements()
    _next_engagement()


func _next_engagement() -> void:
    if _order.is_empty():
        _current = null
        _current_squads.clear()
        _running = false
        assault_completed.emit()
        _turn_manager.complete_procedure_phase(TurnManager.Phase.ASSAULT)
        return
    _current = _order.pop_front()
    _current_squads = squads_in_turn_order(_current)
    engagement_started.emit(_current, _current_squads.duplicate())
    _pending_declarers.clear()
    for squad in _current_squads:
        var options := get_target_options(squad)
        if options.is_empty() or _tracker.charge_target_of(squad.squad_id) != &"":
            continue  # nothing to attack, or locked to its charge target
        if options.size() == 1:
            _tracker.set_attack_target(squad.squad_id, options[0].squad_id)
        else:
            _pending_declarers.append(squad)
    _ask_next_declaration()


func _ask_next_declaration() -> void:
    var squad := get_declaring_squad()
    if squad:
        target_declaration_required.emit(squad, get_target_options(squad))
    else:
        _roll_strikes()


## Snapshots every squad's eligible models, then rolls every strike, then
## starts allocation: no casualty is applied before all strikes are rolled.
func _roll_strikes() -> void:
    var snapshot := []
    for squad in _current_squads:
        var target := _battle.get_squad(_tracker.attack_target_of(squad.squad_id))
        if target == null or target not in _current_squads:
            continue
        var enemies := _current_squads.filter(func(s: SquadState) -> bool: return s.get_player() != squad.get_player())
        snapshot.append([squad, target, AssaultRules.engagement_eligible(squad, enemies)])
    var results: Array[CombatResult] = []
    for entry in snapshot:
        var result := AssaultRules.resolve_strike(entry[0], entry[1], entry[2], dice, terrain)
        DamageRules.resolve_wounds_and_saves(result, dice)
        result.engagement_id = _current.id
        results.append(result)
    strikes_rolled.emit(_current, results)
    _awaiting_allocation = true
    _allocator.enqueue(results)


func _on_queue_resolved(results: Array[CombatResult]) -> void:
    if not _awaiting_allocation:
        return
    _awaiting_allocation = false
    var fought := _current
    var fought_squads := _current_squads.duplicate()
    engagement_fought.emit(fought, results)
    var outcome := CombatScoring.score(fought, fought_squads, results)
    if morale:
        for squad in outcome.testing:
            outcome.loss_tests.append(morale.resolve_assault_loss(squad))
    _tracker.mark_resolved(fought)
    outcomes.append(outcome)
    engagement_resolved.emit(outcome)
    _next_engagement()


func _order_key(engagement: EngagementTracker.Engagement) -> String:
    var squads := squads_in_turn_order(engagement)
    if squads.is_empty():
        return "~"
    var first: SquadState = squads[0]
    return "%d%s" % [0 if first.get_player() == _turn_manager.priority_player else 1, first.squad_id]
