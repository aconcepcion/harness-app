class HarnessApp < Formula
  desc "Native macOS launcher for DeepSeek Harness (dsh) — no Electron, no bundled dsh"
  homepage "https://github.com/aconcepcion/harness-app"
  url "https://github.com/aconcepcion/harness-app/archive/refs/tags/v3.1.0.tar.gz"
  sha256 "18e989cc344a1df36d21106ea64971d9f3a0dfa0767dce9bc7eccc8204c1e727"
  license "MIT"
  head "https://github.com/aconcepcion/harness-app.git", branch: "main"

  depends_on :macos => :ventura

  def install
    system "make", "app", "ARCHS="
    prefix.install "build/Harness.app"
    (bin/"harness-app").write <<~EOS
      #!/bin/bash
      exec open -a "#{opt_prefix}/Harness.app" "$@"
    EOS
  end

  def caveats
    <<~EOS
      Harness.app was built locally and installed to:
        #{opt_prefix}/Harness.app
      To put it in /Applications (Dock, Spotlight):
        cp -R "#{opt_prefix}/Harness.app" /Applications/
      Or launch from the terminal: harness-app [workspace-folder]
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{opt_prefix}/Harness.app/Contents/MacOS/Harness --version")
  end
end
