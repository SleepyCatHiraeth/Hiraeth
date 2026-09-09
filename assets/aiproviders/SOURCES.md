# AI provider marks

The SVGs in this directory are provider logomarks rendered monochrome: they are
tinted to the active theme at runtime rather than drawn in vendor colors, so the
`fill` in the source file does not matter (`claude.svg` carries a brand hex,
most of the others carry `currentColor`, which QtSvg renders black — both come
out the same once colorized).

Source: [Lobe Icons](https://github.com/lobehub/lobe-icons)
(`@lobehub/icons-static-svg`), MIT — see `LICENSE.lobe-icons`. The upstream slug
is the stored filename.

Product names and logos remain trademarks of their respective owners.
