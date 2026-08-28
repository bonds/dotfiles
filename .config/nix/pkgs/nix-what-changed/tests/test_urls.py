from what_changed import urls
from what_changed.config import Config


def test_qemu_url():
    url = urls._make_qemu_url("11.0.0")
    assert url == "https://wiki.qemu.org/ChangeLog/11.0"


def test_qemu_url_major_only():
    url = urls._make_qemu_url("11")
    assert url is None


def test_qemu_url_three_parts():
    url = urls._make_qemu_url("9.2.0")
    assert url == "https://wiki.qemu.org/ChangeLog/9.2"


def test_gcc_url():
    url = urls._make_gcc_url("15.2.0")
    assert url == "https://gcc.gnu.org/gcc-15/changes.html"


def test_github_blob():
    f = urls._make_github_blob("rust-lang", "cargo", "CHANGELOG.md")
    url = f("1.0.0")
    assert url == "https://github.com/rust-lang/cargo/blob/master/CHANGELOG.md"


def test_github_blob_custom_ref():
    f = urls._make_github_blob("owner", "repo", "NEWS", "main")
    url = f("1.0.0")
    assert url == "https://github.com/owner/repo/blob/main/NEWS"


def test_known_urls_present():
    assert "qemu" in urls.KNOWN_URLS
    assert "gcc" in urls.KNOWN_URLS
    assert "cargo" in urls.KNOWN_URLS
    assert "rustc" in urls.KNOWN_URLS
    assert "coreutils" in urls.KNOWN_URLS
    assert "msmtp" in urls.KNOWN_URLS
    assert "rsync" in urls.KNOWN_URLS
    assert "gimp" in urls.KNOWN_URLS
    assert "obsidian" in urls.KNOWN_URLS
    assert "discord" in urls.KNOWN_URLS
    assert "dwarf-fortress" in urls.KNOWN_URLS
    assert "neocode" in urls.KNOWN_URLS
    assert "opencode" in urls.KNOWN_URLS
    assert "opencode-desktop" in urls.KNOWN_URLS
    assert "osaurus" in urls.KNOWN_URLS
    assert "oxillama" in urls.KNOWN_URLS
    assert "zen-browser" in urls.KNOWN_URLS
    assert "clamav" in urls.KNOWN_URLS
    assert "gdk-pixbuf" in urls.KNOWN_URLS
    assert "glib" in urls.KNOWN_URLS
    assert "libssh" in urls.KNOWN_URLS
    assert "libmpg123" in urls.KNOWN_URLS
    assert "docker" in urls.KNOWN_URLS
    assert "hermes-agent" in urls.KNOWN_URLS


def test_known_url_tag_formats():
    assert urls.KNOWN_URLS["osaurus"]("0.22.22") == "https://github.com/osaurus-ai/osaurus/releases/tag/0.22.22"
    assert urls.KNOWN_URLS["oxillama"]("0.1.4") == "https://github.com/cool-japan/oxillama/releases/tag/v0.1.4"
    assert urls.KNOWN_URLS["zen-browser"]("1.21.14b") == "https://github.com/zen-browser/desktop/releases/tag/1.21.14b"
    assert urls.KNOWN_URLS["clamav"]("1.4.6") == "https://github.com/Cisco-Talos/clamav/releases/tag/clamav-1.4.6"
    assert urls.KNOWN_URLS["gdk-pixbuf"]("2.44.7") == "https://gitlab.gnome.org/GNOME/gdk-pixbuf/-/raw/master/NEWS"
    assert urls.KNOWN_URLS["glib"]("2.88.3") == "https://gitlab.gnome.org/GNOME/glib/-/raw/main/NEWS"
    assert urls.KNOWN_URLS["libssh"]("0.12.2") == "https://github.com/libssh/libssh-mirror/blob/master/CHANGELOG"
    assert urls.KNOWN_URLS["libmpg123"]("1.33.7") == "https://github.com/libsdl-org/mpg123/blob/master/NEWS"
    assert urls.KNOWN_URLS["docker"]("29.7.2") == "https://github.com/moby/moby/releases/tag/docker-v29.7.2"
    assert urls.KNOWN_URLS["docker"]("26.1.4") == "https://github.com/moby/moby/releases/tag/docker-v26.1.4"
    assert (
        urls.KNOWN_URLS["hermes-agent"]("0.20.6")
        == "https://api.github.com/repos/NousResearch/hermes-agent/releases?per_page=50&resolve_version=0.20.6"
    )


def test_known_url_precedence():
    assert "discord" in urls.KNOWN_URLS
    assert "obsidian" in urls.KNOWN_URLS
    assert urls.KNOWN_URLS["discord"]("1.0.0") == "https://discord.com/tags/changelog"
    assert urls.KNOWN_URLS["obsidian"]("1.0.0") == "https://obsidian.md/changelog/"


def test_github_release_url():
    url = urls._make_github_release_url("bonds", "NeoCode")("0.8.1-202607090932-b0b091f")
    assert url == "https://github.com/bonds/NeoCode/releases/tag/v0.8.1-202607090932-b0b091f"

    url = urls._make_github_release_url("anomalyco", "opencode")("1.17.14")
    assert url == "https://github.com/anomalyco/opencode/releases/tag/v1.17.14"


def test_custom_package_urls():
    assert urls.KNOWN_URLS["neocode"]("0.8.1") == "https://github.com/bonds/NeoCode/releases/tag/v0.8.1"
    assert urls.KNOWN_URLS["opencode"]("1.17.14") == "https://github.com/anomalyco/opencode/releases/tag/v1.17.14"
    assert urls.KNOWN_URLS["opencode-desktop"]("1.17.14") == "https://github.com/anomalyco/opencode/releases/tag/v1.17.14"
