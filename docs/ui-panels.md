# Panel chrome

Every dismissible panel looks and behaves the same way.

## The close seal

- **One close control.** A dismissible panel carries one close door: the shared
  `CloseSeal` medallion, top-right of its header.
- **No text door.** No panel prints its own "Close" text or a bare `×` glyph.
  A new sheet inherits the seal from `SheetFrame`, `LedgerFrame`,
  `DossierHeader` or `ProvinceSheetHead`; a one-off panel builds it with
  `CloseSeal.make()`.
- **Same medallion.** The seal draws `assets/art/icons/close.png` from the
  `ChromeIcons` set, so it matches every other antique medallion.
- **Thumb-sized.** The target is at least 44 points, desktop or phone.
- **Escape and Back still close.** The seal adds a door; it never removes the
  keyboard or the back gesture (REQ-P1-07, REQ-P5-07).

## Tests

`tests/test_panel_parts_rules.gd` mounts every known dismissible panel and
fails when one lacks the seal, when a seal is not in the header's right-hand
slot, when a press does not close, or when a panel prints a one-off Close
door instead.

## Why

A player who opens a sheet should know where to dismiss it, on any screen and
with any input. Per-panel copies drift, so the door lives in shared chrome
(REQ-P1-05, REQ-P3-01).
