class_name DialogueMood
extends RefCounted
## Portrait moods (wiki: dialogue-and-mood § Design intent, § Mood machine).
## Presentation only: no rule reads a mood back, and the machine takes its
## inputs from the offer it sits on, so the same court, offer and seed always
## wears the same face (REQ-P2-03, REQ-P3-03).

const CONSIDERING: String = "considering"
const PLEASED: String = "pleased"
const GRACIOUS: String = "gracious"
const CALCULATING: String = "calculating"
const SKEPTICAL: String = "skeptical"
const IMPATIENT: String = "impatient"
const IRRITATED: String = "irritated"
const DISMISSIVE: String = "dismissive"

## Every mood a portrait may wear, in wiki order.
const MOODS: Array[String] = [
	CONSIDERING,
	PLEASED,
	GRACIOUS,
	CALCULATING,
	SKEPTICAL,
	IMPATIENT,
	IRRITATED,
	DISMISSIVE,
]

## A fresh, unremarkable proposal opens on the documented default.
const OPEN_MOOD: String = CONSIDERING
## Turns a court will wait for an answer before its envoy turns impatient.
const STALL_LIMIT: int = 3
## Relation points that make a full step of offer quality, so ±40 is a band.
const QUALITY_SPAN: float = 40.0
## A quality this far from none is a strong offer, good or bad.
const STRONG_QUALITY: float = 0.5


## The envoy's face, in the reader's tongue: the caption a proposal banner and
## the court panel both print (the words answer to [ConsentCopy]).
static func label(mood: String) -> String:
	return ConsentCopy.mood_word(mood)


## The envoy's face for a waiting offer: stalls tire a court first, then the
## offer's own generosity, and the seed breaks the tie inside each band.
static func for_offer(stall: int, quality: float, salt: int) -> String:
	var waited: int = maxi(stall, 0)
	if waited <= 0 and is_zero_approx(quality):
		return OPEN_MOOD
	if waited >= STALL_LIMIT:
		return _tie(IMPATIENT, SKEPTICAL, salt)
	if quality >= STRONG_QUALITY:
		return _tie(PLEASED, GRACIOUS, salt)
	if quality <= -STRONG_QUALITY:
		return _tie(IRRITATED, DISMISSIVE, salt)
	return _tie(CALCULATING, CONSIDERING, salt)


## How generous an offer is: the relation surplus over what it requires,
## normalised so the whole band fits −1…1. A court at the threshold is
## calculating; a court far above it is warm.
static func quality(score: float, required: float) -> float:
	return clampf((score - required) / QUALITY_SPAN, -1.0, 1.0)


## Turns an offer has waited unanswered; an offer queued this turn waits none.
static func stall(queued_turn: int, turn: int) -> int:
	return maxi(turn - queued_turn, 0)


static func _tie(first: String, second: String, salt: int) -> String:
	return first if absi(salt) % 2 == 0 else second
