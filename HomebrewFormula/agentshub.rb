class Agentshub < Formula
  desc "macOS menu bar app for monitoring Claude Code sessions"
  homepage "https://github.com/ericermerimen/agentshub"
  url "https://github.com/ericermerimen/agentshub/releases/latest/download/AgentsHub-latest-macos.tar.gz"
  version "0.1.0"
  # sha256 will be filled in by the release workflow
  # sha256 ""

  depends_on :macos
  depends_on macos: :sonoma

  def install
    prefix.install "AgentsHub.app"
    bin.install_symlink prefix/"AgentsHub.app/Contents/MacOS/agentshub"
  end

  def caveats
    <<~EOS
      AgentsHub.app has been installed to:
        #{prefix}/AgentsHub.app

      To start the menu bar app:
        open #{prefix}/AgentsHub.app

      To set up Claude Code hooks, open AgentsHub preferences
      and click "Copy Hook Config to Clipboard", then paste
      into ~/.claude/settings.json

      You may need to grant Accessibility access in:
        System Settings > Privacy & Security > Accessibility
    EOS
  end

  service do
    run "#{prefix}/AgentsHub.app/Contents/MacOS/AgentsHub"
    keep_alive true
    log_path var/"log/agentshub.log"
    error_log_path var/"log/agentshub-error.log"
  end
end
