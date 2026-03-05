class Sup < Formula
  desc "One command to update every package manager and dev tool"
  homepage "https://github.com/zaydiscold/sup"
  url "https://github.com/zaydiscold/sup/releases/download/v1.0.0/sup.sh"
  # sha256 is replaced at release time by the CI workflow
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"

  depends_on "bash" => "4.0"
  depends_on "curl"

  def install
    bin.install "sup.sh" => "sup"
  end

  test do
    assert_match "sup v#{version}", shell_output("#{bin}/sup --version")
  end
end
