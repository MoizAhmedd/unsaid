# Unsaid

**A speaking coach for Wispr Flow.** It finds the filler words you lean on ("like", "kind of", "um", "I think") in your dictation and calls, plays them back so you hear yourself, and helps you halve one in two weeks. Wispr tidies your writing; Unsaid works on how you talk.

[moizahmedd.github.io/unsaid](https://moizahmedd.github.io/unsaid/)

## Install

```sh
brew install moizahmedd/tap/unsaid
```

No Homebrew? `curl -fsSL https://moizahmedd.github.io/unsaid/install | sh`

macOS 13 or later. It sits in the menu bar and opens at login.

## How it works

- On first launch it compares what you said (Wispr's raw transcript) with what Wispr pasted, and counts the filler words its cleanup deleted. Notetaker calls count too: only your mic, and in-person recordings are skipped. ▶ plays your messiest dictation.
- Pick one habit and halve it in two weeks. The menu bar shows today's count against a goal that grows with how much you talk, plays your worst moment of the day, and plays day 1 next to today. On day 14 you get before and after, for dictation and for calls.
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
