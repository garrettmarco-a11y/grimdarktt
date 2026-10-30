extends Resource
class_name SquadData
## Identity, affiliation and statistics of one squad. Data only: how the squad
## is drawn and selected lives in SquadToken.
##
## Squad composition (leader and members, possibly with different profiles) is
## not defined yet; for now one UnitProfile describes the squad's models.

## Stable identifier, unique among squads in a battle.
@export var squad_id: StringName = &""
@export var display_name: String = ""
## Owning player: TurnManager.PLAYER_ONE or TurnManager.PLAYER_TWO.
@export var player: int = 0
@export var profile: UnitProfile
