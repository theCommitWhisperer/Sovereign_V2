#!/usr/bin/env python3
"""
check_luau.py -- structural sanity checks for the Sovereign source tree.

There is no Luau toolchain in every environment this repo gets edited from, and
"open it in Studio and see" is a slow feedback loop. This catches the classes of
breakage that actually happen during refactors, using only the standard library.

DELIBERATELY NOT A PARSER. An earlier version tried to balance
function/if/for/do ... end and produced false positives on perfectly good files,
because Luau's `if a then b else c` *expression* takes no `end`, and type
annotations like `(a) -> b` contain block-looking keywords. A checker that cries
wolf is worse than no checker, so this only reports things it can be certain of:

  1. encoding      -- non-UTF-8 bytes (this repo was bitten by cp1252 mojibake)
  2. merge markers -- stray <<<<<<< / ======= / >>>>>>>
  3. requires      -- require() targets that resolve to nothing in the tree
  4. collisions    -- two modules Rojo would expose under the same name
  5. orphans       -- modules nothing references (informational)

A clean run does not prove correctness. It proves the tree is wired up.

Usage:  python3 tools/check_luau.py [src_dir] [--orphans]
Exit 1 if any ERROR is found. Warnings and orphans do not fail the run.
"""

import os
import re
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
SHOW_ORPHANS = "--orphans" in sys.argv
SRC = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
SRC = os.path.abspath(SRC)

errors, warnings, notes = [], [], []

# Names that are Roblox services, Rojo roots or local aliases rather than modules.
IGNORE_TARGETS = {
    "Packages", "script", "Parent", "ReplicatedStorage", "ServerScriptService",
    "StarterPlayer", "StarterPlayerScripts", "Shared", "Server", "Client", "UI",
    "WaitForChild", "FindFirstChild",
}


def strip_comments_and_strings(text):
    """Good enough to stop require()-scanning from reading commented-out code."""
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", " ", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    return text


def build_module_index(root):
    """Map every module name Rojo exposes -> list of paths providing it."""
    index = {}
    for r, _, fs in os.walk(root):
        if "assets" in r:
            continue
        for f in fs:
            if not f.endswith((".luau", ".lua")):
                continue
            p = os.path.join(r, f)
            if f in ("init.luau", "init.lua"):
                name = os.path.basename(r)
            else:
                name = os.path.splitext(f)[0]
                # Rojo strips the .client/.server suffix from script names
                for suffix in (".client", ".server"):
                    if name.endswith(suffix):
                        name = name[: -len(suffix)]
            index.setdefault(name, []).append(os.path.relpath(p, root))
    return index


REQUIRE_RE = re.compile(r"require\s*\(([^)]*)\)")


def build_package_names(src_root):
    """Wally packages live outside src/; index their names so requires resolve."""
    pkg_dir = os.path.join(os.path.dirname(src_root), "Packages")
    names = set()
    if os.path.isdir(pkg_dir):
        for f in os.listdir(pkg_dir):
            if f.endswith((".lua", ".luau")):
                names.add(os.path.splitext(f)[0])
    return names


def main():
    index = build_module_index(SRC)
    IGNORE_TARGETS.update(build_package_names(SRC))
    referenced = set()
    files = 0

    for r, _, fs in os.walk(SRC):
        if "assets" in r:
            continue
        for f in sorted(fs):
            if not f.endswith((".luau", ".lua")):
                continue
            p = os.path.join(r, f)
            rel = os.path.relpath(p, SRC)
            raw = open(p, "rb").read()

            if b"<<<<<<<" in raw or b">>>>>>>" in raw:
                errors.append(f"{rel}: unresolved merge conflict markers")
                continue
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError as e:
                errors.append(
                    f"{rel}: not valid UTF-8 at byte {e.start} "
                    f"(likely cp1252 smart quotes -- see .gitattributes)"
                )
                continue

            files += 1
            code = strip_comments_and_strings(text)

            for m in REQUIRE_RE.finditer(code):
                expr = m.group(1)
                if "[" in expr:      # dynamic index, can't resolve statically
                    continue
                parts = re.findall(r"[A-Za-z_]\w*", expr)
                if not parts:
                    continue
                target = parts[-1]
                if target in IGNORE_TARGETS:
                    continue
                if target in index:
                    referenced.add(target)
                else:
                    warnings.append(
                        f"{rel}: require target `{target}` not found in src "
                        f"(Wally package, or a broken path)"
                    )

            # Identifier references, for orphan detection
            for name in index:
                if name not in referenced and re.search(r"\b" + re.escape(name) + r"\b", code):
                    owners = index[name]
                    if rel not in owners:
                        referenced.add(name)

    # Rojo name collisions: two SIBLING files that would land on the same name.
    # An init.luau names its own folder, so GameData/init.luau and
    # GameData/GameData.luau are NOT siblings in the DataModel -- they become
    # GameData and GameData.GameData. Compare parent scopes, not raw dirnames.
    for name, paths in sorted(index.items()):
        if len(paths) < 2:
            continue
        scopes = []
        for p in paths:
            d = os.path.dirname(p)
            if os.path.basename(p) in ("init.luau", "init.lua"):
                d = os.path.dirname(d)  # init names the folder, so it sits one level up
            scopes.append(d)
        if len(set(scopes)) < len(scopes):
            errors.append(f"Rojo name collision for `{name}`: {paths}")
        else:
            notes.append(f"`{name}` defined in {len(paths)} places: {paths}")

    # Entry scripts and specs are *supposed* to have no requirers: Rojo runs
    # .client/.server scripts directly, and TestRunner discovers specs by name.
    def expected_orphan(name):
        path = index[name][0]
        return path.endswith((".client.luau", ".server.luau")) or ".spec" in path

    orphans = sorted(n for n in set(index) - referenced if not expected_orphan(n))

    print(f"checked {files} Luau files under {SRC}")
    for w in warnings:
        print(f"  warn   {w}")
    for n in notes:
        print(f"  note   {n}")
    if SHOW_ORPHANS and orphans:
        print(f"\n  {len(orphans)} module(s) with no external reference:")
        for o in orphans:
            print(f"  orphan {o}  ({index[o][0]})")

    if errors:
        print(f"\n{len(errors)} ERROR(S):")
        for e in errors:
            print(f"  ERROR  {e}")
        return 1
    print(f"\nOK -- no errors ({len(warnings)} warning(s), {len(orphans)} orphan(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
