# imessagememesfx — MemeFX

Meme sound effects for iMessage. Open MemeFX in any chat, tap a pad (or type a slash command
like `/fah`), hit return, and the sound lands in the thread for everyone.

## How it works

- **MemeFXMessages** is an iMessage app extension: a drawer with a board of sound pads and a
  Slack-style command bar. Type `/fa` and it suggests `/fah`, `/faaah`, `/fart`, `/fail`…;
  return sends the first one.
- A sound goes out as an **audio message** (`Vine Boom.m4a`), so everyone in the chat can play it,
  even friends without the app or on Android. A debug-only A/B switch sends it as a **MemeFX card**
  instead (a big colored image; tapping it opens MemeFX and plays the sound).
- When Messages won't let the extension send by itself (no iMessage account, SMS chats), the
  sound is staged in the compose box so one tap on ↑ sends it.
- **MemeFX** is the home-screen app that carries the extension and previews the board.

iMessage does not let third-party apps auto-play a sound on everyone's phone or read what you
type in the Messages text box, so the commands live in MemeFX's own bar.

## Sounds

| Folder | Where they come from | In git? |
|---|---|---|
| `Shared/Sounds/` | Synthesized from scratch by `scripts/make-sounds.py` (stdlib only) | Yes, ours to ship |
| `Shared/Instants/` | Trending clips from myinstants.com, fetched by `scripts/fetch-instants.py` | **No.** Other people's uploads, mostly copyrighted: personal builds only. Replace them with licensed sounds before an App Store release |

## Build

```sh
python3 scripts/make-sounds.py      # regenerate the originals (optional, they're committed)
python3 scripts/fetch-instants.py   # pull the myinstants clips (not committed)
xcodegen generate
open MemeFX.xcodeproj               # run the MemeFX scheme, then open Messages → + → MemeFX
```

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen). iOS 17+.

`MemeFXUITests/MessagesShots` drives the real Messages app in the Simulator, sends a sound both
ways and types `/fa`, and saves screenshots to `$SHOTS_DIR`:

```sh
TEST_RUNNER_SHOTS_DIR=$PWD/build/shots xcodebuild -project MemeFX.xcodeproj -scheme MemeFX \
  -destination 'platform=iOS Simulator,name=iPhone 17e' test
```
