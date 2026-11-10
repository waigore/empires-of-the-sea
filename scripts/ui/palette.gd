class_name Palette
extends RefCounted
## Shared colour language: antique atlas parchment, iron-gall ink, heraldic accents.
## Kept in one place so map, HUD and icons read as a single artefact (REQ-P1-02).

const PAPER := Color(0.937, 0.886, 0.776)
const PAPER_DEEP := Color(0.878, 0.808, 0.663)
const PAPER_SHADE := Color(0.792, 0.714, 0.565)

const INK := Color(0.129, 0.102, 0.075)
const INK_SOFT := Color(0.196, 0.157, 0.114)
const INK_LINE := Color(0.235, 0.184, 0.129)
const INK_FAINT := Color(0.235, 0.184, 0.129, 0.35)

const GOLD := Color(0.831, 0.686, 0.216)
const GOLD_DIM := Color(0.541, 0.427, 0.122)
const GOLD_PALE := Color(0.925, 0.827, 0.478)

const CRIMSON := Color(0.639, 0.169, 0.169)
const NAVY := Color(0.176, 0.267, 0.435)
const VIOLET := Color(0.435, 0.325, 0.502)
const MOSS := Color(0.243, 0.376, 0.267)

const SEA_DEEP := Color(0.302, 0.443, 0.475)
const SEA_MID := Color(0.471, 0.604, 0.604)
const SEA_PALE := Color(0.663, 0.769, 0.749)

const TEXT := Color(0.941, 0.894, 0.784)
const TEXT_DIM := Color(0.741, 0.678, 0.553)

## Survey lens status inks. Kept beside the atlas palette so plaques on the map
## and the HUD key speak the same colour language (REQ-P1-02).
const SURVEY_YIELDING := Color(0.322, 0.573, 0.322)
const SURVEY_BUILDING := Color(0.914, 0.647, 0.157)
const SURVEY_VACANT := Color(0.839, 0.361, 0.176)
const SURVEY_PROSPECT := Color(0.290, 0.529, 0.690)
const SURVEY_OFFLINE := Color(0.596, 0.502, 0.392)
const SURVEY_FOREIGN := Color(0.427, 0.416, 0.392)

## Diplomatic lens bands: blue for the crown's own land, green for friendly or
## allied courts, grey for neutral and red for crowns at war. The map wash and
## the key read this one table (REQ-P1-02).
const DIPLO_SELF := Color(0.176, 0.353, 0.663)
const DIPLO_FRIENDLY := Color(0.243, 0.478, 0.286)
const DIPLO_NEUTRAL := Color(0.478, 0.463, 0.427)
const DIPLO_WAR := Color(0.702, 0.196, 0.196)

## Terrain wash colours, indexed by MapModel.Terrain.
## Ocean is transparent so the animated sea shader shows through.
const TERRAIN_COLORS: Array[Color] = [
	Color(0.0, 0.0, 0.0, 0.0),
	Color(0.78, 0.87, 0.84, 0.55),
	Color(0.878, 0.804, 0.62),
	Color(0.702, 0.741, 0.541),
	Color(0.804, 0.694, 0.514),
	Color(0.69, 0.604, 0.49),
	Color(0.91, 0.839, 0.651),
	Color(0.663, 0.71, 0.549),
	Color(0.72, 0.78, 0.52),
]

static func terrain_color(terrain: int) -> Color:
	if terrain < 0 or terrain >= TERRAIN_COLORS.size():
		return Color(0.5, 0.5, 0.5)
	return TERRAIN_COLORS[terrain]


static func faction_color(owner: int) -> Color:
	return FactionCatalog.color_of(owner)


## Ink for a survey status; unknown statuses fall back to the offline brown.
static func survey_color(status: String) -> Color:
	match status:
		"producing", "maxed":
			return SURVEY_YIELDING
		"building":
			return SURVEY_BUILDING
		"vacant":
			return SURVEY_VACANT
		"unprospected":
			return SURVEY_PROSPECT
		"disconnected":
			return SURVEY_OFFLINE
	return SURVEY_OFFLINE


## Wash ink for one diplomatic band (DiplomacySurvey.BANDS).
static func diplo_color(band: String) -> Color:
	match band:
		DiplomacySurvey.BAND_SELF:
			return DIPLO_SELF
		DiplomacySurvey.BAND_FRIENDLY:
			return DIPLO_FRIENDLY
		DiplomacySurvey.BAND_WAR:
			return DIPLO_WAR
	return DIPLO_NEUTRAL
