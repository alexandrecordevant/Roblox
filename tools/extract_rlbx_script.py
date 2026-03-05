import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Usage:
#   python tools/extract_rbxlx_scripts.py "C:\path\to\Place.rbxlx" "C:\path\to\output\src"
#
# Extracts Script/LocalScript/ModuleScript sources from a .rbxlx (XML) place file.
# Preserves hierarchy based on "Name" properties.
#
# Notes:
# - This is best-effort. Roblox XML is verbose; we focus on scripts + names + parent/child tree.
# - Output paths are sanitized for Windows filesystem.

SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}

def sanitize_segment(s: str) -> str:
    # Replace illegal filename chars
    s = re.sub(r'[<>:"/\\|?*\x00-\x1F]', "_", s)
    s = s.strip().strip(".")
    if not s:
        s = "_"
    return s[:120]

def find_prop(props, class_name, prop_name):
    # props: <Properties> element
    for child in list(props):
        if child.tag == class_name and child.attrib.get("name") == prop_name:
            return child.text or ""
    return ""

def get_instance_name(item):
    props = item.find("Properties")
    if props is None:
        return item.attrib.get("class", "Instance")
    # Name is stored in <string name="Name">...</string>
    name = find_prop(props, "string", "Name")
    return name if name else item.attrib.get("class", "Instance")

def get_script_source(item):
    props = item.find("Properties")
    if props is None:
        return ""
    # Script source stored in <ProtectedString name="Source">...</ProtectedString>
    for child in list(props):
        if child.tag == "ProtectedString" and child.attrib.get("name") == "Source":
            return child.text or ""
    return ""

def suffix_for_class(cls):
    if cls == "Script":
        return ".server.lua"
    if cls == "LocalScript":
        return ".client.lua"
    if cls == "ModuleScript":
        return ".lua"
    return ".lua"

def walk(item, parent_path, out_root: Path, stats):
    cls = item.attrib.get("class", "Instance")
    name = sanitize_segment(get_instance_name(item))
    my_path = parent_path / name

    # If script, write file
    if cls in SCRIPT_CLASSES:
        src = get_script_source(item)
        rel_dir = my_path.parent
        rel_dir_fs = out_root / rel_dir

        rel_dir_fs.mkdir(parents=True, exist_ok=True)

        filename = sanitize_segment(name) + suffix_for_class(cls)
        file_path = rel_dir_fs / filename

        # Avoid collisions
        if file_path.exists():
            i = 2
            while True:
                alt = rel_dir_fs / f"{sanitize_segment(name)}_{i}{suffix_for_class(cls)}"
                if not alt.exists():
                    file_path = alt
                    break
                i += 1

        file_path.write_text(src, encoding="utf-8", errors="replace")
        stats["scripts"] += 1

    # Recurse children
    for child in item.findall("Item"):
        walk(child, my_path, out_root, stats)

def main():
    if len(sys.argv) != 3:
        print("Usage: python extract_rbxlx_scripts.py <place.rbxlx> <out_src_dir>")
        sys.exit(1)

    rbxlx_path = Path(sys.argv[1]).expanduser()
    out_src = Path(sys.argv[2]).expanduser()

    if not rbxlx_path.exists():
        print(f"ERROR: file not found: {rbxlx_path}")
        sys.exit(2)

    out_src.mkdir(parents=True, exist_ok=True)

    tree = ET.parse(rbxlx_path)
    root = tree.getroot()

    # Roblox place XML generally has top-level <Item class="DataModel"> ... </Item>
    top_items = root.findall("Item")
    if not top_items:
        print("ERROR: no <Item> found in rbxlx. Is this a valid .rbxlx?")
        sys.exit(3)

    stats = {"scripts": 0}

    for top in top_items:
        walk(top, Path("."), out_src, stats)

    print(f"Done. Extracted scripts: {stats['scripts']}")
    print(f"Output dir: {out_src}")

if __name__ == "__main__":
    main()