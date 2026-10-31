extends Resource
class_name WeaponProfile
## Statistics for one weapon type.
##
## Data only: how each stat is used is defined by the rules scripts. Defaults
## are zero and are not balance values; real profiles live in .tres files.

@export var weapon_name: String = ""
## Maximum range in board distance units. A weapon with range 0 is not a
## ranged weapon.
@export var range: float = 0.0
## Number of attacks (shots) per model firing this weapon.
@export var attacks: int = 0
## Strength rating used by D6 wound resolution.
@export var strength: int = 0
## Armor Piercing (AP): added to the target's armor save target number.
@export var armor_piercing: int = 0
