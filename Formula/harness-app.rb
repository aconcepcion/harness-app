class HarnessApp < Formula
  desc "Native macOS launcher for DeepSeek Harness (dsh) — no Electron, no bundled dsh"
  homepage "https://github.com/aconcepcion/harness-app"
  url "https://github.com/aconcepcion/harness-app/archive/refs/tags/v3.0.0.tar.gz"
  sha256 "15565d74cfb13db675d021c997a13db89fc70b1d162efef471b791b863fa0604"
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
    assert_match "Harness.app", shell_output("#{opt_prefix}/Harness.app/Contents/MacOS/Harness --check-env", 1)
  end
end
