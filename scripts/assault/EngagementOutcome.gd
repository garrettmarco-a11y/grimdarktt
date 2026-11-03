extends RefCounted
class_name EngagementOutcome
## How one engagement ended: each side's losses, survivors, outnumbering bonus
## and combat score, the winner, and the assault-loss tests that followed.
## Sides are players (TurnManager.PLAYER_ONE / PLAYER_TWO).

enum Reason { SCORE, SIDE_DESTROYED, BOTH_DESTROYED }

var engagement: EngagementTracker.Engagement
## Every squad that fought, in turn order (destroyed ones included).
var squads: Array[SquadState] = []
var results: Array[CombatResult] = []
## player -> models that side lost in this engagement's strikes.
var models_lost := {}
## player -> living models that side has after casualties.
var survivors := {}
## player -> outnumbering bonus (0, 1 or 2).
var outnumbering := {}
## player -> enemy models lost + outnumbering bonus.
var scores := {}
## The winning player, or TurnManager.NO_PLAYER for a draw.
var winner := TurnManager.NO_PLAYER
var reason := Reason.SCORE
## Surviving squads of the losing side that take an assault-loss test, in
## test order (squad_id).
var testing: Array[SquadState] = []
## Their tests, in the same order (empty if no MoraleController is bound).
var loss_tests: Array[MoraleResult] = []


func is_draw() -> bool:
    return winner == TurnManager.NO_PLAYER


func loser() -> int:
    return TurnManager.NO_PLAYER if is_draw() else TurnManager.other_player(winner)
