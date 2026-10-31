extends Resource
class_name SquadData
## Identity, affiliation and statistics of one squad. Data only: how the squad
## is drawn and selected lives in SquadToken.
##
## `models` lists the squad's models; the first is the leader. One UnitProfile
## still describes all of them until models carry their own profiles.

## Stable identifier, unique among squads in a battle.
@export var squad_id: StringName = &""
@export var display_name: String = ""
## Owning player: TurnManager.PLAYER_ONE or TurnManager.PLAYER_TWO.
@export var player: int = 0
@export var profile: UnitProfile
## The squad's models; the first entry is the leader.
@export var models: Array[SquadModel] = []
