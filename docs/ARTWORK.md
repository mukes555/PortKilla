# Artwork

Every picture in PortNanny is the same quokka. This page holds the prompts
that make her, what each file feeds, and the two rules that stop a good
image from breaking the app.

## The character

Paste this at the top of any prompt, together with an existing mascot file
as the reference image:

> Same character and style as the reference: a quokka with warm brown fur,
> black wayfarer sunglasses, a white ruffled maid headband, and a black
> dress with a white ruffled pinafore collar. Friendly 3D render, soft
> studio lighting, slight smile, no outline.

## Two rules

**Transparent background, or pure white.** `scripts/make_artwork.swift
mascot` keys out white by flood-filling from the edges, so a white studio
background works and interior whites (the headband, the pinafore, her
teeth) survive. Any other colour has to be keyed out by hand.

**No text anywhere.** No wordmark, no signature, no generator watermark.
The 2.1 artwork shipped with a watermark in the corner that had to be
cropped out, which is why the mascots are 393 px wide instead of square.

## What each file feeds

| File | Size | Where it shows | What constrains it |
| --- | --- | --- | --- |
| `assets/AppIcon.icns` | 1024 square | Dock, Finder, About, the colour menu bar icon | Corners get rounded off |
| `PortNanny/assets/mascot/quokka-happy.png` | 512 tall | Header avatar, menu bar glyph, tour | Load-bearing, see below |
| `PortNanny/assets/mascot/quokka-sleepy.png` | 512 tall | "All quiet: nothing is listening" | Read at 88 to 96 pt |
| `PortNanny/assets/mascot/quokka-guard.png` | 512 tall | Guard badge, tour, README | Read at **22 pt** |

The three mascot files are currently the same image, so the sleepy empty
state and the guard badge both show a waving quokka. Prompts 3 and 4 fix
that.

### Why `quokka-happy.png` is load-bearing

Three pieces of code cut it up rather than draw it whole:

- `MascotView.headBox` finds the first opaque row and calls it the top of
  her head, then measures the widest span of the next 18 percent of rows.
  So **her ear tips must be the highest thing in the image**, and nothing
  may be wider than her head up there. A raised paw beside an ear moves
  the crop and the avatar goes wrong.
- `MenuBarGlyph` traces that crop into a one-colour silhouette by keeping
  fur and dropping anything near black. So **the sunglasses have to be
  much darker than the fur**; they become the eye holes that make the
  glyph readable at 18 pt.
- `BrandAvatar` shows the crop at 40 pt in the popover header.

Everything else about her can change. Those two things cannot.

## Prompts

### 1. App icon

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, slight smile, no outline.

App icon, 1024x1024, no text. Quokka bust centred on a rich blue circle
(#4085F7) that fills about 80 percent of the canvas, on a slightly darker
blue backdrop. She is waving one paw and holding a black coffee mug in
the other. Keep her head and both paws well inside the circle: the corners
of this square are rounded off when the icon is built.
```

### 2. Mascot, happy

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, slight smile, no outline.

Transparent background, portrait 800x1024, no text. Full body, standing,
facing the camera, one paw raised in a friendly stop gesture at chest
height, a silver laptop held under the other arm.

Framing is strict: her ear tips must be the topmost part of the image with
a small margin above them, and nothing may be wider than her head in the
top fifth of the frame. Keep the raised paw below her chin. Her head
should fill the upper third. Sunglasses solid near-black for contrast
against the fur.
```

### 3. Mascot, sleepy

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, no outline.

Transparent background, portrait 800x1024, no text. Asleep in an office
chair, slumped comfortably, sunglasses pushed up onto her forehead so her
closed eyes show, a closed silver laptop on her lap, a black mug on the
armrest. A small "zzz" curl above her head, drawn as shapes rather than
letters. Peaceful, nothing to do.
```

### 4. Mascot, on guard

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, no outline.

Transparent background, square 1024x1024, no text. Bust only, head and
shoulders, facing the camera, alert and serious with a slight smile. One
paw raised flat in a firm stop gesture beside her head, level with her
chin. Bold simple shapes and strong contrast: this is shown as a badge
22 pixels tall, so anything fine is lost. No laptop, no mug.
```

### 5. Refused

Not wired up yet. It belongs on the refusal notification and in the
Workbench's Agents view, where one agent has been stopped from killing
another's server.

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, no outline.

Transparent background, square 1024x1024, no text. Standing between the
camera and a glowing server rack behind her, one paw held out flat to hold
someone back, the other resting protectively on the rack. Calm and
matter-of-fact rather than angry: she is not telling anyone off, she is
keeping two things apart.
```

### 6. Busy

Not wired up yet. For the Workbench when many ports are listening.

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, no outline.

Transparent background, landscape 1400x1024, no text. At a desk in front
of several glowing monitors full of scrolling code and port numbers, one
paw on a trackpad, the black mug beside the keyboard, sunglasses reflecting
the screens. Focused and cheerful, on top of it rather than swamped.
```

### 7. Nothing found

Not wired up yet. For a search that matches no port.

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, no outline.

Transparent background, square 1024x1024, no text. Holding a magnifying
glass up in one paw and peering through it at the viewer, one eyebrow
raised above the sunglasses, the black mug in the other paw. Curious and
a little amused, not disappointed.
```

### 8. README banner

The banner is generated from the happy mascot by
`swift scripts/make_logo.swift`, which sets the wordmark and tagline in the
app's own typeface. Use this only to replace that with a drawn one.

```
Same character and style as the reference: a quokka with warm brown fur,
black wayfarer sunglasses, a white ruffled maid headband, and a black
dress with a white ruffled pinafore collar. Friendly 3D render, soft
studio lighting, no outline.

Wide banner 2400x560 on a near-black background (#171A1F) with a soft blue
glow (#4085F7) behind the character. Quokka bust inside a blue circle on
the left third, waving, a silver laptop under her arm. On the right, the
wordmark "PortNanny" with "Port" in white and "Nanny" in blue, and under
it in smaller grey text: "The macOS port manager that knows whose server
it is."
```

## Wiring them up

The mascots are keyed and scaled to 512 tall:

```bash
cd PortNanny
swift scripts/make_artwork.swift mascot ~/Downloads/happy.png assets/mascot/quokka-happy.png
swift scripts/make_artwork.swift mascot ~/Downloads/sleepy.png assets/mascot/quokka-sleepy.png
swift scripts/make_artwork.swift mascot ~/Downloads/guard.png assets/mascot/quokka-guard.png
```

The icon is masked to the macOS rounded square and written as an `.icns`,
with a 256 px copy for the README:

```bash
swift scripts/make_artwork.swift icon ~/Downloads/icon-1024.png assets/AppIcon.icns ../assets/icon.png
```

Then the banner, and a look at the results:

```bash
swift scripts/make_logo.swift
PORTNANNY_SNAPSHOT_DATA=demo PORTNANNY_MASCOT_DIR=assets/mascot PORTNANNY_SNAPSHOT=/tmp/avatar.png PORTNANNY_SNAPSHOT_VIEW=avatar .build/debug/PortNanny
PORTNANNY_SNAPSHOT_DATA=demo PORTNANNY_MASCOT_DIR=assets/mascot PORTNANNY_SNAPSHOT=/tmp/glyphs.png PORTNANNY_SNAPSHOT_VIEW=menubar .build/debug/PortNanny
```

The avatar sheet draws the head crop large with its box outlined, so you
can see at once whether the ears survived. The menu bar sheet shows the
traced glyph at four sizes on both a light and a dark bar. If the ears are
clipped or the glyph is a blob, the framing rule in prompt 2 was not met.

`swift test --disable-sandbox --filter BrandingAndSizeTests` checks the
same things: that the crop is taller than it is wide, that it stops above
the waist, and that the glyph is neither empty nor solid.

Finally, regenerate the README screenshots so they show the new art:
the commands are in [CONTRIBUTING.md](../CONTRIBUTING.md) under
"Regenerate the README assets". Always with `PORTNANNY_SNAPSHOT_DATA=demo`.
