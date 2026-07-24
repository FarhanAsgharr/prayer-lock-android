# Branding assets

## What goes here

| File | Size | Purpose |
| ---- | ---- | ------- |
| `app_icon.png` | 1024×1024 | Legacy launcher icon. The circular badge, no wordmark. |
| `app_icon_foreground.png` | 1024×1024 | Adaptive icon foreground. Badge centred at ~60% scale, transparent around it. |
| `app_icon_monochrome.png` | 1024×1024 | Android 13+ themed icon. Solid white silhouette on transparent. |

## Why the wordmark is excluded

The full logo — badge plus "PRAYER LOCK / Lock distractions. Unlock rewards." —
is the right thing for the Play Store listing, the splash screen and the
onboarding header. It is the wrong thing for a launcher icon: at 48dp the
strapline is a grey smear, and Play's icon guidelines discourage text in the
icon because it cannot be localised and duplicates the app name shown beneath.

So the launcher icon is the **badge only**, cropped square.

## Why the foreground needs padding

Android adaptive icons are cropped by the launcher into whatever mask the device
uses — circle, squircle, rounded square, teardrop. Only the centre **66%** of
the foreground layer is guaranteed to survive. Art that fills the full canvas
loses its outer ring, which on this logo means the minarets and the outer
gradient circle.

Rule of thumb: draw the badge at about 60% of the canvas width, centred, with
the rest transparent.

## Regenerating

```bash
cd mobile
flutter pub run flutter_launcher_icons
```

That writes every `mipmap-*` bucket, the adaptive `ic_launcher.xml`, and the
monochrome layer. Do not hand-edit anything under `android/app/src/main/res/mipmap-*`.
