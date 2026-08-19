# App icon — the one asset that has to be made by hand

`Contents.json` expects a single file here:

    AppIcon-1024.png     1024 × 1024, PNG, no alpha channel, no rounded corners

That single size is all Xcode 14+ needs; it generates every other size at build
time. **The build will fail until that file exists** — this is deliberate, so the
icon can't be forgotten and shipped as a white square.

Alpha is the common mistake. A PNG with a transparency channel is rejected at
App Store Connect upload, not at build, which wastes a round trip. Flatten onto
an opaque background before exporting.

## What it should look like

`DesignSystem/AppMark.swift` already draws the mark used inside the app — the
category spine motif. Rendering that at 1024 and flattening it onto Theme's
`paper` white is the cheapest route to something coherent, and it means the icon
and the in-app mark can't drift apart.

The palette to stay inside, from `Theme.Palette`:

| Token | Hex | Use |
|-------|-----|-----|
| ink | `#16283D` | the mark |
| paper | `#FFFFFF` | background |
| canvas | `#F2F3F5` | secondary background |

Resist adding a saturated color. Category color is the only saturated color in
the app, and an icon in one arbitrary category color would imply something the
app doesn't mean.
