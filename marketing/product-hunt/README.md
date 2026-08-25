# Product Hunt gallery drafts

This folder owns the HTML source and review PNGs for the `mikrokhoros` Product Hunt gallery. The surface is a product-launch gallery: it explains the implemented runtime and does not represent a hosted application or a stable release.

## Canvas and source authority

- Canvas: `1270×760`, Product Hunt's recommended gallery ratio.
- Gallery count: six still frames.
- Product facts: [`../../docs/public-facts.json`](../../docs/public-facts.json).
- Product behavior: [`../../README.md`](../../README.md) and [`../../docs/design.md`](../../docs/design.md).
- Approved assets: three checksum-pinned gallery inputs selected from the four approved images in the public fact sheet.
- Current implementation branch baseline: `bdf247be974ded9e97c3380dbfb2eb646503d960`.

Every frame is local-only HTML/CSS. It has no remote font, remote image, analytics, form, cookie, or network dependency.

## Narrative order

1. **Actions become consequences.** A standalone product promise with the persistent-world illustration.
2. **Agents act. Worlds answer.** The observation-to-consequence loop.
3. **A place an agent can understand.** Locality, facilities, paths, resources, objects, and records.
4. **Objects are first-class.** Object SDK → package → Inventory → world-object lifecycle.
5. **Full CLI. Local Web.** The two human surfaces owned by the native `khoros` runtime.
6. **Open source. Free to use.** Apache-2.0, supported platforms, repository, and first local commands.

The illustrations in frames 1 and 3 are labelled as concept illustrations. The interface image in frame 5 is labelled as a pre-release product-interface reference. Its command block is explicitly scoped to macOS and Linux; Windows installation remains the documented PowerShell path.

## Render

Serve the repository root locally so asset paths remain same-origin, then append this path to the local origin:

```text
marketing/product-hunt/index.html?frame=1
```

Set the browser viewport to exactly `1270×760` CSS pixels and capture the viewport at 1× device scale. Repeat for `frame=1` through `frame=6`.

The review files belong in [`drafts/`](./drafts/), named in narrative order. Each PNG must remain under Product Hunt's 3 MB limit.
[`drafts/manifest.json`](./drafts/manifest.json) binds each review export to its dimensions, byte size, SHA-256 digest, baseline revision, and approved source assets.

## Review boundary

These files are publication drafts. Human review is required before Product Hunt submission or social publishing. No Product Hunt submission, social post, account change, or runtime deployment is performed by this gallery change.

## External research

The sequence applies general communication principles from the current [Product Hunt launch guide](https://www.producthunt.com/launch/preparing-for-launch) and [posting guide](https://help.producthunt.com/en/articles/479557-how-to-post-a-product). External launches informed narrative structure only; no external layout, copy, trademark, or proprietary artwork is included.
