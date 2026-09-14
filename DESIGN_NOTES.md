# Design notes: porting the Figma reference to QML

`../reference/` (kept read-only) is a browser mockup simulating a Plasma
desktop, not a real one, so a few things couldn't be — and shouldn't be —
ported literally:

- **Glass/blur panels** (`backdrop-filter: blur(20px) saturate(1.4)`):
  QML has no equivalent for blurring "whatever's behind this popup" the
  way CSS backdrop-filter does. Rather than fake it with a grabbed-
  snapshot blur, the popup deliberately paints no background of its own
  and relies on Plasma's own tooltip/dialog chrome, which the compositor
  already blurs via KWin when enabled — more correct for a native widget
  than a fixed translucent rectangle.
- **`box-shadow` glow on the current-lesson chip**: ported with
  `Qt5Compat.GraphicalEffects.RectangularGlow`, the closest built-in Qt6
  primitive — visually close, not pixel-identical to CSS's falloff curve.
- **Neutral chip/border colors** (`rgba(255,255,255,alpha)` in the
  reference): re-derived from `Kirigami.Theme.textColor` at the same
  alphas instead of hardcoded white, so they adapt to light/dark Plasma
  themes instead of matching only the reference's dark screenshot.
- **Fonts**: the reference imports Google Fonts; the QML port uses the
  system theme font and the generic `"monospace"` family alias instead
  of pinning a specific webfont a user may not have installed.
- **Dashed borders**: not possible on a QML `Rectangle`, so substituted
  lessons get a solid colored ring plus an explicit "Substituted" label
  instead (the reference's sample data has no cancelled/substituted
  lessons at all — this whole visual language is new, not a port).
- **Hover vs. click**: the reference only supports hover-to-reveal. The
  QML port keeps hover (`PlasmaCore.ToolTipArea`) but also wires the same
  detail card as the applet's `fullRepresentation`, so clicking opens the
  same card as a normal Plasma popup — native taskbar-item behavior the
  browser mockup has no equivalent of.
- **Everything else** (paddings, heights, radii, font sizes/weights, the
  popup's 256px width, layout structure) is ported at the literal pixel
  values from `reference/src/App.tsx` / `reference/src/index.css`.
