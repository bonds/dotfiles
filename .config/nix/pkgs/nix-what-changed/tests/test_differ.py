from what_changed.differ import PackageChange


def test_package_change_fields():
    pc = PackageChange(name="test-pkg", old_version="1.0", new_version="2.0")
    assert pc.name == "test-pkg"
    assert pc.old_version == "1.0"
    assert pc.new_version == "2.0"


def test_package_change_repr():
    pc = PackageChange("pkg", "1.0", "2.0")
    r = repr(pc)
    assert "pkg" in r


def test_package_change_equality():
    a = PackageChange("pkg", "1.0", "2.0")
    b = PackageChange("pkg", "1.0", "2.0")
    assert a.name == b.name
    assert a.old_version == b.old_version
    assert a.new_version == b.new_version
