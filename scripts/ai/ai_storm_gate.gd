class_name AiStormGate
extends RefCounted
## Rival storm sizing for walled land (issue #1314).
##
## Every Old World province starts behind a wall, and the resolver prices the
## wall plus its standing battery before a host may storm an empty one
## ([method FortRules.storm_threshold], with the battery the **defender's**
## studies set). The gate cannot read another court's ledger, so it prices the
## top of the emplaced line ([method FortRules.storm_ceiling]): a host it sizes
## clears whatever battery the wall mounts. A court that only ever musters its
## published target — five regiments at peace, a handful more at war — stands
## under a Wood wall's threshold, so every march into an empty walled province
## is repelled and the land it walks stays foreign: the measured bench froze a
## court at seven provinces for the whole campaign.
##
## The gate raises the court's muster target by the smallest host that would
## cross its thinnest wall: the strongest line its techs open, read against
## [method FortRules.storm_ceiling]. The extra rides the target, so the
## muster, its labour floor and the chest it holds for the next regiment all
## ask for the same host, and the map layer keeps no second target
## ([method AiArmyReinforceHost.desired_regiments]).
##
## Pure: the map, the court's own wall reading and the registry are the only
## inputs (REQ-P2-03, REQ-P3-03). No rule changes: the muster spends through
## `ArmyTraining`, and the storm still resolves in [ArmyCombat].

## The wall plus the battery this province's holder actually mounts (issue
## #1381): the resolver prices a storm with the **defender's** emplaced line
## (`ArmyStorm`, `FortRules.storm_threshold`), so the gate that decides whether
## to march reads the same figure — a Minor Nation mounts the Royal floor, a
## Great Power its own Royal → Heavy → Siege line. The map layer notes the
## campaign's tech table on the court's config ([field AiConfig.wall_techs]);
## a caller with none keeps the top of the ladder ([method
## FortRules.storm_ceiling]), which is what every planner read before the
## table was shared. The shipped ladder never moves: the gate only stops
## pricing every minor's Wood wall as if it carried siege guns.
static func threshold(config: AiConfig, model: MapModel, province: int) -> float:
	var level: int = FortRules.level_at(model, province)
	if config == null or model == null or config.wall_techs.is_empty():
		return FortRules.storm_ceiling(level)
	var owner: int = model.province_owner(province)
	var tech: Variant = config.wall_techs.get(owner, {})
	if not (tech is Dictionary):
		return FortRules.storm_ceiling(level)
	return FortRules.storm_threshold(tech as Dictionary, level)


## True when `army` may storm `province`: the wall soaks attacking strength, and
## the defenders it leaves need the attack margin left over. An empty walled
## province still prices the battery its holder mounts, because a storm against
## an empty wall is the same storm ([method threshold]). The land march and the
## overseas landing ask this one gate, so both admit the same hosts (REQ-P2-03,
## REQ-P3-03). A caller with no config, model or host reads no storm.
static func admits(
	config: AiConfig, model: MapModel, armies: Array, army: ArmyState, province: int
) -> bool:
	if config == null or model == null or army == null:
		return false
	var roster: Array[ArmyState] = []
	roster.assign(armies)
	var defenders: Array[ArmyState] = ArmyForce.armies_of(
		roster, province, model.province_owner(province)
	)
	var level: int = FortRules.level_at(model, province)
	if defenders.is_empty():
		return level < 1 or army.strength() > threshold(config, model, province)
	var wall: float = FortRules.wall_hp(level)
	var attack: float = army.strength() - wall
	var margin: float = float(config.parameter("military.attack_margin_pct")) / 100.0
	return attack > ArmyForce.side_strength(defenders) * margin


## Regiments a host of `strength` needs to cross `threshold` with room to spare:
## the ceiling of `threshold / strength`, plus one so the host clears the wall
## rather than tie it (a storm wants strict strength above the threshold), plus
## one more so the storm does not spend every regiment past a bare crossing —
## the measured bench read a one-regiment lift as a storm that takes the
## province and leaves the court too thin to take the next. Zero for a
## threshold or a line of no strength.
static func regiments_for(threshold: float, strength: float) -> int:
	if strength <= 0.0 or threshold <= 0.0:
		return 0
	return int(ceil(threshold / strength)) + 2


## Regiments the court names on its own wall reading (see
## [method MapPlayArmyMusterAi.storm_extra]): zero when the reading is empty.
static func extra_regiments(read: Variant) -> int:
	if read == null or not (read is Dictionary) or (read as Dictionary).is_empty():
		return 0
	return maxi(int((read as Dictionary).get("extra", 0)), 0)


## The extra regiments this court musters to carry a storm over the thinnest
## wall it faces. `threshold` is the wall plus battery the court's land reads,
## 0 when it faces none; `strength` is its strongest line. `target` is the
## court's own muster target, pressure included, and `own_regiments` what it
## fields today — the extra is what stands between them and the host the wall
## wants, so a court already at (or over) that host asks for nothing.
static func extra(
	threshold: float, strength: float, target: int, own_regiments: int
) -> Dictionary:
	var want: int = regiments_for(threshold, strength)
	var held: int = maxi(maxi(target, own_regiments), 0)
	return {"want": want, "extra": maxi(want - held, 0)}
