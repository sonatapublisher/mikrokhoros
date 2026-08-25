# Product Hunt gallery drafts

This folder owns the HTML source and review PNGs for the `mikrokhoros` Product Hunt gallery. The surface is a product-launch gallery: it explains the implemented runtime and does not represent a hosted application or a stable release.

## Canvas and source authority

- Canvas: `1270×760`, Product Hunt's recommended gallery ratio.
- Gallery count: six still frames.
- Product facts: [`../../docs/public-facts.json`](../../docs/public-facts.json).
- Product behavior: [`../../README.md`](../../README.md) and [`../../docs/design.md`](../../docs/design.md).
- Approved brand asset: the checksum-pinned product icon in the public fact sheet.
- Product imagery: two checksum-pinned captures from the running native `khoros` product and one checksum-pinned conceptual world-model visualization.
- Current implementation branch baseline: `bdf247be974ded9e97c3380dbfb2eb646503d960`.

Every frame is local-only HTML/CSS. It has no remote font, remote image, analytics, form, cookie, or network dependency.

## Narrative order

1. **Actions become consequences.** A standalone product promise with the initialized `default-khoros` World view.
2. **Agents act. Worlds answer.** The observation-to-consequence loop.
3. **A place an agent can understand.** A purpose-built world-model visualization shows locality, bounded perception, connected facilities, contained resources, object identity, and a replayable trajectory.
4. **Objects are first-class.** Object SDK → package → Inventory → world-object lifecycle.
5. **Full CLI. Local Web.** The command surface sits beside a captured World object interaction from the same native runtime.
6. **Open source. Free to use.** Apache-2.0, supported platforms, repository, and first local commands.

Frames 1 and 5 identify their imagery as captured pre-release product output. Frame 3 identifies its image as a conceptual visualization reviewed against the implemented persistent-world model. The frame 5 command block is explicitly scoped to macOS and Linux; Windows installation remains the documented PowerShell path.

## Runtime capture provenance

- Runtime source: public `main` revision `bdf247be974ded9e97c3380dbfb2eb646503d960`.
- Executable: release `khoros` built from the checked-out Swift package.
- State: a new isolated `MIKROKHOROS_HOME` initialized with `khoros init`.
- Interface: the native loopback `mikrokhoros Web` surface opened from the one-time launch URL printed by `khoros web`.
- Capture canvas: `1270×760` CSS pixels at 1× device scale.
- External model configuration: none.
- Provider calls: none.

The captured state contains one unprofiled local agent, five canonical Inventory sources, and the `default-khoros` world template. The launch token, filesystem path, and generated runtime identifiers are not part of the gallery copy.

## Concept-visual provenance

- Purpose: communicate the implemented persistent-world structure at gallery scale.
- Source authority: the canonical public fact sheet, product README, runtime design, and `default-khoros` facility layout.
- Method: AI-assisted conceptual visualization with no third-party source artwork.
- Review boundary: the image is illustrative evidence of product concepts, not a product screenshot, hosted world, stable release, or runtime output.

## Render

Serve the repository root locally so asset paths remain same-origin, then append this path to the local origin:

```text
marketing/product-hunt/index.html?frame=1
```

Set the browser viewport to exactly `1270×760` CSS pixels and capture the viewport at 1× device scale. Repeat for `frame=1` through `frame=6`.

The review files belong in [`drafts/`](./drafts/), named in narrative order. Each PNG must remain under Product Hunt's 3 MB limit.
[`drafts/manifest.json`](./drafts/manifest.json) binds each review export to its dimensions, byte size, SHA-256 digest, baseline revision, approved brand source, and runtime-capture inputs.

## Review boundary

These files are publication drafts. Human review is required before Product Hunt submission or social publishing. No Product Hunt submission, social post, account change, or runtime deployment is performed by this gallery change.

## External research

The sequence applies general communication principles from the current [Product Hunt launch guide](https://www.producthunt.com/launch/preparing-for-launch) and [posting guide](https://help.producthunt.com/en/articles/479557-how-to-post-a-product). External launches informed narrative structure only; no external layout, copy, trademark, or proprietary artwork is included.
