extends Resource
class_name UnitProfile
## Baseline statistics for one model type.
##
## Data only: how each stat is used by the rules (hit, wound, save and morale
## resolution) is defined by later tasks. Defaults are zero and are not balance
## values; real profiles live in .tres files.

## Maximum move distance per Movement phase, in board distance units.
## The board-unit-to-pixel scale is not defined yet.
@export var movement: float = 0.0
## Quality rating used by D6 resolution.
@export var quality: int = 0
## Toughness rating used by D6 wound resolution.
@export var toughness: int = 0
## Number of wounds the model can suffer before removal.
@export var wounds: int = 0
## Leadership rating used by morale tests.
@export var leadership: int = 0
