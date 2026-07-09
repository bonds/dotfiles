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
