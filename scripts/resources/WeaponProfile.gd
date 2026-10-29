extends Resource
class_name WeaponProfile
## Baseline statistics for one weapon type.
##
## Data only: how each stat is used by the rules is defined by later tasks.
## Defaults are zero and are not balance values; real profiles live in .tres files.

## Strength rating used by D6 wound resolution.
@export var strength: int = 0
## Armor Value rating used by D6 armor-save resolution.
@export var armor_value: int = 0
## Armor Piercing rating applied against the target's armor save.
@export var armor_piercing: int = 0
