# Unsaid

**A speaking coach for your Mac.** It finds the filler words you lean on ("like", "kind of", "um", "I think") in how you talk every day, plays them back so you hear yourself, and helps you halve one in two weeks. It listens through [Wispr Flow](https://wisprflow.ai) (what you say to it, and calls its Notetaker records), so you need Wispr Flow installed.

[moizahmedd.github.io/unsaid](https://moizahmedd.github.io/unsaid/)

## Install

```sh
brew install moizahmedd/tap/unsaid
```

No Homebrew? `curl -fsSL https://moizahmedd.github.io/unsaid/install | sh`

macOS 13 or later. It sits in the menu bar and opens at login.

## How it works

- On first launch it compares what you actually said with what Wispr typed out, and counts the filler words Wispr quietly deleted. Notetaker calls count too: only your mic, and in-person recordings are skipped. ▶ plays your messiest moment.
- Pick one habit and halve it in two weeks. The menu bar shows today's count against a goal that grows with how much you talk, plays your worst moment of the day, and plays day 1 next to today. On day 14 you get before and after, for messages and for calls.
- It opens Wispr's database read-only and stores counts, not your words. A few short clips of your own voice are kept, because Wispr deletes old recordings. Nothing leaves your Mac and there are no permission prompts. Needs [Wispr Flow](https://wisprflow.ai); call clips need macOS 15.

Signed with the project's own certificate rather than an Apple Developer ID, so it isn't notarized.
Both install paths leave it unquarantined, so there's no Gatekeeper dialog.

## Build from source

Needs Xcode 16 or the Command Line Tools.

```sh
git clone https://github.com/MoizAhmedd/unsaid.git && cd unsaid
scripts/make-app.sh && open .build/app/Unsaid.app
```

`swift test` runs the tests. Releases: push a `v*` tag ([release.yml](.github/workflows/release.yml)).

## License

MIT
