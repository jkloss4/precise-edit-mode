# Precise Edit Mode

Exact values for Blizzard's Edit Mode, in a panel that sits against the side of the Edit Mode settings dialog and
matches its look.

Made for WoW: Forever (Interface 16001); also lists retail (Interface 120100), which uses the same Edit Mode code.

## Features

- **X / Y:** type the exact position of a point on the selected element's blue Edit Mode outline (what Blizzard
  snaps by), measured from the center of the screen. **Point** picks which one: any corner, the middle of any edge,
  or the center (the default). With Center, `0` centers the element; for mirrored layouts, use Top Left on the left
  side and Top Right on the right side with opposite X values. The values update live while you drag or nudge with
  the arrow keys. A typed position goes through the same steps as Blizzard's own arrow-key nudge, so it's saved with
  Edit Mode's **Save** button like any other move.
- **Icon Size (action bars):** any size from 50% to 200%, like 65%, instead of only the slider's 10% steps.
  Blizzard's layouts can only store the slider steps, so the nearest step is saved in the layout (and shown on the
  slider), and the exact size is saved by this addon for that layout and bar and applied on top. Moving Blizzard's
  Icon Size slider goes back to its steps.
- The panel appears to the right of the settings dialog, or to its left when there's no room, follows it when it's
  dragged, and closes with it.

Type a value and press Enter (or click away) to apply it, Escape to undo the edit, Tab to move to the next box.

## Install

Download `PreciseEditMode-<version>.zip` from the [latest release](../../releases/latest) and extract the
`PreciseEditMode` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\` (retail: `_retail_`).

An addon manager that installs from GitHub releases (e.g. WowUp: *Install from URL* with this repo's URL) can also
install and update it.

## Developing / releasing

- Test local changes: `.\scripts\install-local.ps1` copies the addon folder into the Forever `AddOns`, then `/reload`.
- After a WoW patch: bump `## Interface:` in `PreciseEditMode/PreciseEditMode.toc`.
- Release: `git tag v1.0.1 && git push --tags`. The [Release workflow](.github/workflows/release.yml) stamps the
  version into the TOC, builds the zip (with a `release.json` for addon managers), and publishes the GitHub release.

## License

MIT ([`LICENSE`](LICENSE), also included in the addon folder).
