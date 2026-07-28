# Homebrew formula for nzbfast (brew install nzbfast/tap/nzbfast).
#
# THIS FILE IS THE SOURCE OF TRUTH. packaging/homebrew/bump-tap.sh rewrites
# the version and the three sha256 lines at release time and pushes a copy to
# the public tap repo (nzbfast/homebrew-tap). Edit here, never in the tap.
#
# It points at the same archives a person downloads by hand from the release
# page, on purpose. The per-target-triple tarballs on the same release come
# from a manually dispatched CI workflow, so they are not guaranteed to exist
# for every tag, and their Linux builds link glibc 2.39, which will not start
# on Debian 12 or Ubuntu 22.04. The release archives below are static musl on
# Linux and a universal binary on macOS, so they run everywhere.
class Nzbfast < Formula
  desc "Fast Usenet (NZB) downloader with one-pass verify, repair and extract"
  homepage "https://github.com/nzbfast/nzbfast"
  version "1.0.10"
  license "GPL-3.0-or-later"

  livecheck do
    url :stable
    strategy :github_latest
  end

  # `version` above is load-bearing and not redundant: Homebrew scans a
  # version out of the URL when one is not declared, and these filenames make
  # it read "64" out of "-x64"/"-arm64" and install to Cellar/nzbfast/64.
  #
  # macOS ships one universal binary rather than a per-architecture build, so
  # both arches point at the same archive. It has to be spelled out per arch
  # because `on_macos` itself may not contain a `url`.
  on_macos do
    on_arm do
      url "https://github.com/nzbfast/nzbfast/releases/download/v#{version}/nzbfast-#{version}-macos-universal.zip"
      sha256 "8734b4373c0844d3d6b3279868a9e26dacb20b4af82dbb2b7e7760c417ceb197"
    end
    on_intel do
      url "https://github.com/nzbfast/nzbfast/releases/download/v#{version}/nzbfast-#{version}-macos-universal.zip"
      sha256 "8734b4373c0844d3d6b3279868a9e26dacb20b4af82dbb2b7e7760c417ceb197"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/nzbfast/nzbfast/releases/download/v#{version}/nzbfast-#{version}-linux-x64.tar.gz"
      sha256 "25b69dfff10585fa678cde876013361626e9a6ce5791776d68e6f99595cc23dd"
    end
    on_arm do
      url "https://github.com/nzbfast/nzbfast/releases/download/v#{version}/nzbfast-#{version}-linux-arm64.tar.gz"
      sha256 "e36fc60a2ba41a7602a18a708c0eb162e2d6857382d51bfba92abb200f6d4e0d"
    end
  end

  # No runtime dependencies on purpose: PAR2 repair and RAR extraction are
  # native to the binary. A par2 or unrar already on PATH is still honoured
  # as a fallback, but nothing here requires one.

  def install
    bin.install "nzbfast"
    doc.install "MANUAL.html"
  end

  # Nothing creates directories here because nothing needs to: the daemon
  # creates its config directory and its download directory on demand, and
  # `brew services` creates working_dir and the log parent before it starts
  # anything. A watch folder that does not exist yet is polled without error
  # and picked up as soon as it appears.
  #
  # etc/nzbfast and var/nzbfast mirror the /etc/nzbfast + /var/lib/nzbfast
  # split of packaging/systemd/nzbfast.service. The daemon keeps its API key,
  # settings and job spool beside the config file, and its index database in
  # the working directory.
  service do
    run [opt_bin/"nzbfast", "serve",
         "--config", etc/"nzbfast/config.json",
         "--out", var/"nzbfast/downloads",
         "--watch", var/"nzbfast/watch"]
    keep_alive true
    working_dir var/"nzbfast"
    log_path var/"log/nzbfast.log"
    error_log_path var/"log/nzbfast.log"
  end

  def caveats
    <<~EOS
      There is no config file to edit. Start the daemon, then add your
      Usenet server through the web UI:

        brew services start nzbfast
        open http://localhost:6789

      Settings, API key and job state live in #{etc}/nzbfast; downloads and
      the watch folder in #{var}/nzbfast. Both survive upgrade and uninstall.

      Prefer the terminal? "nzbfast setup" does the same thing.
      Sonarr and Radarr connect to http://localhost:6789/api as a SABnzbd or
      NZBGet download client; the API key is on the Settings page.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/nzbfast --version")

    # Parse a hand-written NZB end to end. Exercises the real XML parser and
    # the segment accounting offline, with no network and no config.
    (testpath/"demo.nzb").write <<~XML
      <?xml version="1.0" encoding="iso-8859-1" ?>
      <nzb xmlns="http://www.newzbin.com/DTD/2003/nzb">
      <file poster="p@example.com" date="1700000000" subject="&quot;demo.rar&quot; yEnc (1/1)">
      <groups><group>alt.binaries.test</group></groups>
      <segments><segment bytes="100" number="1">abc@example</segment></segments>
      </file>
      </nzb>
    XML

    assert_match "demo.rar", shell_output("#{bin}/nzbfast inspect #{testpath}/demo.nzb")
  end
end
