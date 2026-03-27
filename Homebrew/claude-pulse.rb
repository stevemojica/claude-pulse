cask "claude-pulse" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/stevemojica/claude-pulse/releases/download/v#{version}/ClaudePulse-#{version}.dmg"
  name "Claude Pulse"
  desc "macOS menubar app for monitoring Claude API usage limits"
  homepage "https://github.com/stevemojica/claude-pulse"

  depends_on macos: ">= :sonoma"

  app "Claude Pulse.app"

  postflight do
    # Install LaunchAgent for background polling
    system_command "#{appdir}/Claude Pulse.app/Contents/Resources/install.sh",
                   print_stdout: true
  end

  uninstall launchctl: "com.claudepulse.agent",
            quit:      "com.claudepulse.app"

  zap trash: [
    "~/Library/Application Support/ClaudePulse",
    "~/Library/Preferences/com.claudepulse.app.plist",
    "~/Library/LaunchAgents/com.claudepulse.agent.plist",
  ]
end
