# Template. The release workflow fills in the version and sha256 and pushes the result to
# MoizAhmedd/homebrew-tap as Casks/unsaid.rb.
cask "unsaid" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/MoizAhmedd/unsaid/releases/download/v#{version}/Unsaid.zip"
  name "Unsaid"
  desc "Hear the filler words Wispr Flow cleans out of your speech, and cut them in two weeks."
  homepage "https://moizahmedd.github.io/unsaid/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Unsaid.app"

  # Signed with the project's own certificate, not an Apple Developer ID, so it isn't notarized.
  # Removing the quarantine flag is what lets it open without a Gatekeeper dialog.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Unsaid.app"], must_succeed: false
  end

  uninstall quit: "dev.unsaid.app"

  zap trash: [
    "~/Library/Caches/dev.unsaid.app",
    "~/Library/Preferences/dev.unsaid.app.plist",
  ]

  caveats <<~EOS
    Unsaid is signed with its own certificate rather than an Apple Developer ID, so
    Homebrew's quarantine flag is removed after install. Source: https://github.com/MoizAhmedd/unsaid

    Open it once to start it:
      open "#{appdir}/Unsaid.app"
  EOS
end
