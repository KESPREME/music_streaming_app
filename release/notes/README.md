# Hand-written release notes

Create `<version>.md` here (the **name** from `pubspec.yaml` or the tag, e.g. `1.1.0.md`) and the
next release uses it instead of the commit list:

```markdown
# Glass that behaves

A calmer bottom bar, a real equalizer, and an app that remembers where you were.

## New
- Equalizer with 23 presets, pre-amp, bass boost and per-output profiles
- Software update screen with release notes

## Improved
- Pure black mode draws the bottom bar as dark frosted glass

## Fixed
- The app no longer forgets your queue when Android closes it
```

`# Title` and the first free paragraph become the headline and summary; each `##` heading becomes a
section card in the app (the words *new*, *improved*, *fix*, *performance*, *design* pick its icon).
