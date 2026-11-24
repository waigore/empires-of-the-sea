class_name AiCivilianTargets
extends RefCounted
## How many of each crew a region's own work asks for — the standing reading
## every hire order prices (wiki: civilian-build-planner; civilian-work-planner).
##
## Targets are the region's asks, not the court's choice: one base per craft (or
## the published Explorer and Engineer floor) plus the region's own work queue
## over its per-crew share, one Explorer kept free while a voyage musters, and
## the one Merchant a priced deed opens. The court's own archetype crew sits on
## top of this reading (AiStaffTaste); the hire that reads it — the published
## order, the footing's gates and the purses — stands in `ai_civilian_hire.gd`
## (AiCivilianHire), so the two halves of the staffing question stay one module
## each (REQ-P3-01). Pure rules: state in, targets out.

## The per-region reading the hire order prices: the region's own asks, the
## court's own crew on top of them (AiStaffTaste), and the Merchant's door — one
## Merchant while a priced deed is openable. The embassy waits on the merchant,
## so the hire cannot wait on the embassy, and a deed the purse cannot cover
## this turn is still the deed the merchant will walk to (issue #724, #841;
## wiki: civilian-units § Merchant).
static func training_context(
	config: AiConfig,
	model: MapModel,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	context: Dictionary
) -> Dictionary:
	var train_context: Dictionary = context.duplicate()
	# The region's own survey rides the copied context, so the deed the college
	# hires a Merchant for is one the court has already priced (issue #1383).
	train_context["land_works"] = works
	var deed_tiles: int = AiMerchantWork.buyable_tiles(
		model, config.faction, works, context
	).size()
	train_context["merchant_targets"] = (
		deed_tiles if deed_tiles > 0
		else (
			1 if not AiMerchantWork.openable_deed(
				model, config.faction, train_context
			).is_empty() else 0
		)
	)
	var own_targets: Dictionary = region_targets(
		config, model, works, units, stockpile, tech_caps, train_context
	)
	train_context["own_targets"] = own_targets
	train_context["staff_targets"] = AiStaffTaste.raises(config, own_targets)
	return train_context


## The staff the court wants in this region: the region's owns plus its taste.
static func staff_targets(
	config: AiConfig,
	model: MapModel,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	context: Dictionary
) -> Dictionary:
	return AiStaffTaste.raises(
		config,
		region_targets(config, model, works, units, stockpile, tech_caps, context)
	)


## Per-type staff the region's own work asks for (the court's taste is the extra
## crew [method staff_targets] adds): one base — or the published explorer and
## engineer floor — plus the region's own work queue / work_per_staff, and one
## Explorer kept free while a colonisation voyage is mustering.
static func region_targets(
	config: AiConfig,
	model: MapModel,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	context: Dictionary
) -> Dictionary:
	var per: int = maxi(config.parameter("civilian.work_per_staff"), 1)
	var prospect_work: int = 0
	var uncharted: int = 0
	var provinces: int = 0
	var estate_work: int = 0
	var view: VisibilityModel = context.get("visibility", null)
	if model != null and works != null:
		for province: ProvinceState in model.provinces:
			if model.province_owner(province.id) != config.faction:
				continue
			provinces += 1
			if (
				view != null
				and view.is_province_known(province.id)
				and not view.is_province_fully_visible(province.id)
			):
				uncharted += 1
			prospect_work += MineralSurvey.unsurveyed_in_province(
				model, works, config.faction, province.id, view
			).size()
		for row: Dictionary in AiBuilderWork.estate_rows(
			model, works, units, stockpile, config.faction, tech_caps, context
		):
			if AiBuilderWork.paid_gain(row) > 0:
				estate_work += 1
	var explorers: int = maxi(
		config.parameter("civilian.explorer_target"),
		1 + (prospect_work + uncharted * 3) / per
	)
	# One Explorer kept free while a colonisation voyage is mustering — and one
	# taken first when the court's last Explorer would sail with it, so the
	# colony leaves a prospector on the home hills (issue #894). A claim voyage
	# carries a Merchant (#1127), so only an Explorer voyage asks for the crew.
	var muster: Vector2i = context.get("muster_port", Vector2i(-1, -1))
	var crew: String = String(context.get("voyage_crew_kind", "explorer"))
	if (muster.x >= 0 and crew == "explorer") or bool(context.get("voyage_crew", false)):
		explorers += 1
	var merchants: int = 0
	if int(context.get("merchant_targets", 0)) > 0:
		merchants = 1
	# The claim crew: a court whose Explorer is already ashore sends a Merchant
	# whose deeds found the colony, so that voyage asks for one even when its
	# own chart offers no deed yet (#1127).
	if merchants < 1 and String(context.get("voyage_crew_kind", "")) == "merchant":
		merchants = 1
	return {
		"builder": maxi(2, 1 + estate_work / per),
		"engineer": maxi(
			config.parameter("civilian.engineer_target"),
			1 + provinces / per
		),
		"explorer": explorers,
		"spy": 1,
		"merchant": merchants,
	}
