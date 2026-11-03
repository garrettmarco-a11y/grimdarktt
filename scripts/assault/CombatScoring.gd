extends RefCounted
class_name CombatScoring
## Combat scoring for an engagement, as pure functions. Nothing here changes
## state or rolls dice.
##
## Rules (approved by the project lead):
##   - Scoring is side-wide across the whole engagement, never pairwise or per
##     squad. A side's score is the number of enemy models lost in the
##     engagement, plus an outnumbering bonus.
##   - Outnumbering uses each side's surviving models after casualties: +1 for
##     more than the other side, +2 instead for at least twice as many. The two
##     bonuses are exclusive.
##   - The higher score wins; equal scores draw.
##   - A side with every squad destroyed loses automatically; if both sides are
##     destroyed the engagement is a draw.
##   - On the losing side every surviving squad takes an assault-loss test,
##     whether or not it was targeted or lost models; destroyed squads never
##     test. Tests run in squad_id order. Winners and draws test nobody.


## The outnumbering bonus for a side with `mine` survivors against `theirs`.
static func outnumbering_bonus(mine: int, theirs: int) -> int:
    if mine <= theirs:
        return 0
    return 2 if mine >= 2 * theirs else 1


## Scores `engagement`, fought by `squads` with the allocated strikes
## `results`. `squads` must include squads destroyed in the fight.
static func score(engagement: EngagementTracker.Engagement, squads: Array, results: Array) -> EngagementOutcome:
    var outcome := EngagementOutcome.new()
    outcome.engagement = engagement
    outcome.squads.assign(squads)
    outcome.results.assign(results)
    var sides := [TurnManager.PLAYER_ONE, TurnManager.PLAYER_TWO]
    for player in sides:
        outcome.models_lost[player] = 0
        outcome.survivors[player] = 0
    for result in results:
        for allocation in result.allocations:
            if allocation.removed:
                outcome.models_lost[result.target_squad.get_player()] += 1
    for squad in squads:
        outcome.survivors[squad.get_player()] += squad.get_model_count()
    for player in sides:
        var enemy: int = TurnManager.other_player(player)
        outcome.outnumbering[player] = outnumbering_bonus(outcome.survivors[player], outcome.survivors[enemy])
        outcome.scores[player] = outcome.models_lost[enemy] + outcome.outnumbering[player]
    var p1_gone: bool = outcome.survivors[TurnManager.PLAYER_ONE] == 0
    var p2_gone: bool = outcome.survivors[TurnManager.PLAYER_TWO] == 0
    if p1_gone and p2_gone:
        outcome.reason = EngagementOutcome.Reason.BOTH_DESTROYED
        outcome.winner = TurnManager.NO_PLAYER
    elif p1_gone or p2_gone:
        outcome.reason = EngagementOutcome.Reason.SIDE_DESTROYED
        outcome.winner = TurnManager.PLAYER_TWO if p1_gone else TurnManager.PLAYER_ONE
    else:
        var s1: int = outcome.scores[TurnManager.PLAYER_ONE]
        var s2: int = outcome.scores[TurnManager.PLAYER_TWO]
        outcome.winner = TurnManager.NO_PLAYER if s1 == s2 else (TurnManager.PLAYER_ONE if s1 > s2 else TurnManager.PLAYER_TWO)
    if not outcome.is_draw():
        for squad in squads:
            if squad.get_player() == outcome.loser() and squad.get_model_count() > 0:
                outcome.testing.append(squad)
        outcome.testing.sort_custom(func(a: SquadState, b: SquadState) -> bool: return String(a.squad_id) < String(b.squad_id))
    return outcome
