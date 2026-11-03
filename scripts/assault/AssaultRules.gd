extends RefCounted
class_name AssaultRules
## Melee rules for engagement fighting, as pure functions: which models may
## attack, and rolling one squad's strike against its declared target. Wounds,
## saves and casualties reuse DamageRules and the CasualtyAllocator; the
## EngagementController runs the Assault phase. No scene, input or drawing
## code.
##
## Rules (approved by the project lead):
##   - A model may attack if alive, armed with a melee weapon, and in base
##     contact with an enemy model of its engagement, or within
##     SUPPORT_DISTANCE edge to edge of a same-squad model that is (a Broken
##     squad: contact only). All its attacks go to its squad's declared target.
##   - Each attack rolls one D6 and hits on a roll >= CombatModifiers.hit_target
##     (the established hit rule, no automatic natural-1 miss): Quality, one
##     higher while Shaken, one higher again if the target is in heavy cover.
##   - Line of sight does not apply to melee.

## Tolerance for distance comparisons, in board units.
const EPSILON := 0.001


static func is_melee_weapon(weapon: WeaponProfile) -> bool:
    return weapon != null and weapon.attacks > 0


## Largest edge-to-edge gap, in board units, at which a model supports a
## squad-mate that is in base contact with an enemy.
const SUPPORT_DISTANCE := 1.0


## The models of `squad` eligible to attack in an engagement against the enemy
## squads `enemies`, in model_id order. A model must be alive and have a melee
## weapon, and be in base contact with an enemy model, or (unless the squad is
## Broken) within SUPPORT_DISTANCE edge to edge of a model of its own squad
## that is. Support depends on contact within the engagement, not on the
## squad's chosen target.
static func engagement_eligible(squad: SquadState, enemies: Array) -> Array[ModelState]:
    var in_contact: Array[ModelState] = []
    for model in squad.get_living_models():
        if _touches_enemy(model, enemies):
            in_contact.append(model)
    var eligible: Array[ModelState] = []
    var broken := squad.morale_status == SquadState.MoraleStatus.BROKEN
    for model in squad.get_living_models():
        if not is_melee_weapon(model.get_melee_weapon()):
            continue
        if model in in_contact:
            eligible.append(model)
        elif not broken and _supports(model, in_contact):
            eligible.append(model)
    return eligible


## Why `model` of `squad` cannot attack, or ELIGIBLE, given the snapshot.
static func engagement_eligibility(model: ModelState, eligible: Array) -> int:
    if not is_melee_weapon(model.get_melee_weapon()):
        return CombatResult.Eligibility.NO_MELEE_WEAPON
    return CombatResult.Eligibility.ELIGIBLE if model in eligible else CombatResult.Eligibility.NOT_ENGAGED


## Rolls the melee hits of one squad's strike in an engagement: every model of
## `attacker` listed in `eligible` (the snapshot taken before any strike)
## attacks `target`, its squad's declared target, whether or not it is still
## alive. The target's squad-wide cover and majority armour, and the hit target
## (Quality, +1 Shaken, +1 heavy cover), are recorded as for any attack. Wounds
## and saves are rolled separately by DamageRules; nothing is applied.
static func resolve_strike(attacker: SquadState, target: SquadState, eligible: Array, dice: DiceRoller,
        terrain: TerrainMap = null) -> CombatResult:
    var result := CombatResult.new()
    result.attack_type = CombatResult.AttackType.MELEE
    result.attacker_squad = attacker
    result.target_squad = target
    result.target_cover = TerrainRules.squad_cover(target, terrain)
    result.target_armor_save = TerrainRules.majority_armor_save(target)
    result.hit_target = CombatModifiers.hit_target(attacker, result.target_cover)
    var targets := ShootingRules.target_points(target)
    var models := attacker.get_models().filter(func(m: ModelState) -> bool: return not m.removed or m in eligible)
    for model in models:
        var model_result := CombatResult.ModelResult.new()
        model_result.model_name = model.get_model_name()
        model_result.weapon = model.get_melee_weapon()
        for point in targets:
            model_result.distance = minf(model_result.distance, model.position.distance_to(point))
        model_result.eligibility = engagement_eligibility(model, eligible)
        if model_result.is_eligible():
            model_result.rolls = ShootingRules.roll_attacks(model_result.weapon.attacks, dice)
            for roll in model_result.rolls:
                if ShootingRules.is_hit(roll, result.hit_target):
                    model_result.hits += 1
        result.model_results.append(model_result)
    return result


static func _touches_enemy(model: ModelState, enemies: Array) -> bool:
    for enemy_squad in enemies:
        for enemy in enemy_squad.get_living_models():
            if ModelPlacement.models_in_contact(model, enemy):
                return true
    return false


static func _supports(model: ModelState, in_contact: Array) -> bool:
    for mate in in_contact:
        if mate != model and model.position.distance_to(mate.position) - model.get_base_radius() - mate.get_base_radius() \
                <= SUPPORT_DISTANCE + EPSILON:
            return true
    return false
