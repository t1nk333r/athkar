#!/usr/bin/env python3
"""Which of Athkar's checks a change needs, lane by lane.

  tools/affected-tests.py plan [--all | --base REF] [--json]   what each lane would run, and why
  tools/affected-tests.py select LANE [--all | --base REF]     one lane's selection, as shell assignments
  tools/affected-tests.py check                                the rules below still match the repository

Lanes (tools/test.sh runs them; the native runners select for themselves too):
  selector   Linux   this selection's own tests (tools/affected-tests-test.py)
  content    Linux   the Node checks in NODE_CHECKS
  core       Linux   AthkarCore Swift Testing suites (tools/test-native-core.sh)
  models     Linux   portable production-model XCTest classes (tools/test-native-models.sh)
  ios-build  Linux   the app compiled for iOS (tools/ios-linux-compile.sh); compiling AthkarTests
                     is listed: its bundle cannot be packaged on Linux yet
  app-unit   device  hosted AthkarTests classes              } listed: Linux cannot run them.
  ui         Mac     AthkarUITests classes                    } tools/ios-mac-run.sh test selects both

The changes are the diff from the merge base of HEAD and the base branch to the working tree,
untracked files included. The base branch is --base REF, else $ATHKAR_TEST_BASE, else origin/main.
--all selects everything.

How a change reaches tests:
  - Swift: a file depends on another when it names something the other declares at the top level,
    or uses a member the other's extensions add: as `.member`, or naming both the member and the
    extended type (or a type conforming to it). An init or subscript with a label (`init(hex:)`,
    `subscript(safe index:)`) counts wherever its label appears or the type is named, since
    `Type.init` drops the label. A conformance, an unlabelled init, subscript or operator counts
    wherever the type is named, or, on a type the repository doesn't declare (Array, View), in every
    file. A test runs when it depends on a changed file, directly or through other files compiled
    into the same target. A name a changed file no longer declares counts too, so a removal reaches
    the files still using it. AthkarCore can't see the app, and production code can't see tests, so
    neither depends on them. A test suite or class counts every file that declares or extends it.
  - A file a Swift file reads counts as a change to that Swift file: a repository path or directory
    in one of its string literals, the bare name of a repository file, or its READS entry.
  - UI tests drive the built app, which no code links them to: UI_BLACK_BOX names the app files and
    resources each one checks, and a UI test also checks every app file that spells an accessibility
    identifier it uses (`deck.card.counter`, or `tab.` for "tab.\\(id)"), in its own file or in a
    UITestSupport.swift helper it calls. An identifier a changed app file spelled before the change
    counts too, so renaming or removing one reaches the UI tests using it. App files reached through
    the app's own code count, but the walk stops at the composition roots in UI_ROOTS, which use
    nearly every app file: a root selects UI tests only when it changes itself, or uses a name the
    change removed. An app resource no UI_BLACK_BOX entry names runs every UI test.
  - The Node checks run when one of their inputs, or a script they load, changes.
  - SHARED build and toolchain inputs, a file no rule knows and any selector error run every lane
    in full. Documentation (NO_TESTS) runs nothing, and nothing tests the UNTESTED files.
"""

import json
import os
import re
import shlex
import subprocess
import sys
from collections import deque
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LANES = ["selector", "content", "core", "models", "ios-build", "app-unit", "ui"]
LISTED = ("app-unit", "ui")
DEFAULT_BASE = "origin/main"

CORE_SOURCES = "ios/AthkarCore/Sources/AthkarCore/"
CORE_TESTS = "ios/AthkarCore/Tests/AthkarCoreTests/"
APP = "ios/Athkar/"
PORTABLE_TESTS = "ios/AthkarPortableTests/"
APP_TESTS = "ios/AthkarTests/"
UI_TESTS = "ios/AthkarUITests/"

# Patterns: * stays within one path segment, ** crosses segments, **/ also matches no directory.
# Nothing to run: documentation, plans and ignore files. A file another rule also matches
# (spec/schema.md, content/REVIEW.md) runs what that rule says.
NO_TESTS = ["**/*.md", "docs/**", "plans/**", "**/.gitignore", ".nojekyll", "vendor/LICENSE-*"]
# Known files no test covers: PWA assets, generators and packaging. `plan` names them.
UNTESTED = ["sw.js", "manifest.webmanifest", "icons/*", "vendor/*.js", "tools/cities-build.mjs",
            "tools/content-reference-refresh.mjs", "tools/ios-linux-ipa.sh", "tools/ios-linux-ipa.py"]
# Every lane in full: package manifests and pins, the Xcode project and the runners that build every suite.
SHARED = ["ios/Package.swift", "ios/Package.resolved", "ios/AthkarCore/Package.swift",
          "ios/AthkarCore/Package.resolved", "ios/project.yml", "ios/Athkar.xcodeproj/**", "ios/Athkar/Info.plist",
          "tools/test-native-core.sh", "tools/test-native-models.sh", "tools/ios-linux-compile.sh"]
# The selection and the driver: their own tests.
SELECTOR = ["tools/affected-tests.py", "tools/affected-tests-test.py", "tools/test.sh"]
# The Mac runner: every app-unit and UI test.
MAC_RUNNER = ["tools/ios-mac-run.sh"]
# Copied into the app bundle. tools/test-native-core.sh stages these for the SDK build, and
# ios/project.yml bundles them; `check` compares all three.
APP_RESOURCES = ["content/manifest.json", "content/adhkar.v1.json", "content/ruqyah.v1.json",
                 "fonts/kfgqpc-uthman-taha-naskh.ttf", "fonts/kfgqpc-hafs-v30.ttf", "data/cities.tsv"]
# The manifest and the packs it lists, which the app bundles and the bundle tests read.
BUNDLED_PACKS = ["content/manifest.json", "content/adhkar.v1.json", "content/ruqyah.v1.json"]
# What the iOS build compiles or bundles.
APP_INPUTS = [APP + "**", CORE_SOURCES + "**", *APP_RESOURCES]

# Swift files that build repository paths their literals don't spell out. Each entry replaces the
# paths found in the file's literals.
READS = {
    APP + "Content/BundledContent.swift": BUNDLED_PACKS,
    APP + "Prayer/CityDirectory.swift": ["data/cities.tsv"],
    PORTABLE_TESTS + "PortableTestSupport.swift": BUNDLED_PACKS,
    PORTABLE_TESTS + "BundledIntegrityTests.swift": ["content/manifest.json", "content/*.v1.json"],
    UI_TESTS + "UITestSupport.swift": BUNDLED_PACKS,
}

# Written by tools/fixtures-generate.mjs from index.html.
GENERATED_FIXTURES = ["spec/sessions/fixtures/*.json", "spec/reminders/fixtures/*.json",
                      "spec/prayer-times/vectors.json", "spec/transfer/fixtures/*.json"]
# Node checks: the script and what it reads. The local modules a script imports count as inputs.
NODE_CHECKS = {
    "content-validate": ("tools/content-validate.mjs", ["content/**"]),
    # Runs the validator over copies of content/ and tools/.
    "content-review-test": ("tools/content-review-test.mjs", ["content/**", "tools/content-validate.mjs"]),
    "content-export-pwa": ("tools/content-export-pwa.mjs",
                           ["index.html", "content/adhkar.v1.json", "content/suwar.v1.json", "content/ruqyah.v1.json"]),
    "fixtures": ("tools/fixtures-generate.mjs",
                 ["index.html", "content/suwar.v1.json", "spec/backup/examples/*", *GENERATED_FIXTURES]),
    "backup-validate": ("tools/backup-validate.mjs", ["spec/backup/examples/*", "spec/backup/envelope-v1.schema.json"]),
}

# XCUITest drives the built app, so no code links these tests to what they check. "*" is every UI
# test: each launches the app onto the home screen's morning deck with the bundled packs.
PRAYER = [APP + "Prayer/*.swift", APP + "DeviceLocation.swift", APP + "OneShotLocationRequest.swift",
          "data/cities.tsv"]
UI_BLACK_BOX = {
    "*": [APP + "AthkarApp.swift", APP + "App/*.swift", APP + "Content/BundledContent.swift", APP + "Design/*.swift",
          APP + "Screens/HomeView.swift", APP + "Deck/DeckView.swift", APP + "Deck/DeckCardView.swift",
          APP + "Deck/DeckModel.swift", APP + "Deck/AdhkarDeckModel.swift", *BUNDLED_PACKS],
    "AutoFitUITests": [APP + "Deck/RuqyahDeckModel.swift", APP + "Screens/SettingsView.swift", "fonts/*.ttf"],
    "DeckIndexUITests": [APP + "Deck/DeckIndexView.swift", APP + "Deck/RuqyahDeckModel.swift",
                         APP + "Screens/DeckDialogs.swift"],
    "DeckRegressionUITests": [APP + "Screens/DeckDialogs.swift", APP + "Platform/Haptics.swift", "fonts/*.ttf"],
    "DeckUITests": [APP + "Screens/DeckDialogs.swift", APP + "Platform/Haptics.swift"],
    "HomePrayerRowUITests": [APP + "Screens/HomePrayerRow.swift", *PRAYER],
    "LaunchTests": [APP + "Screens/HomePrayerRow.swift", APP + "Prayer/PrayerTimesModel.swift"],
    "PrayerTimesUITests": [APP + "Screens/OtherSectionsView.swift", *PRAYER],
    "QiblaUITests": [APP + "Screens/OtherSectionsView.swift", APP + "Qibla/*.swift", *PRAYER],
    "ReminderUITests": [APP + "Screens/OtherSectionsView.swift", APP + "Reminders/*.swift", *PRAYER],
    "ScreenshotUITests": [APP + "Deck/RuqyahDeckModel.swift", APP + "Screens/*.swift", "fonts/*.ttf"],
}

# The views and model that assemble the whole app. Every app file reaches one of them, so reaching one
# says nothing about which screens a change moved.
UI_ROOTS = [APP + "AthkarApp.swift", APP + "App/AppModel.swift", APP + "Screens/HomeView.swift",
            APP + "Deck/DeckView.swift"]

TEST_MODULE = {"core": "AthkarCoreTests", "models": "AthkarPortableTests", "app-unit": "AthkarTests",
               "ui": "AthkarUITests"}
LINUX_TEST_DIRS = (CORE_TESTS, PORTABLE_TESTS)

MODIFIER = (r"(?:@[\w.]+(?:\([^)]*\))?\s+)*((?:(?:public|internal|private|fileprivate|open|package|final"
            r"|nonisolated|indirect|static|class|override|mutating|nonmutating|lazy|weak|unowned|convenience"
            r"|required|dynamic|optional|distributed|(?:public|internal|package|private|fileprivate)\(set\))\s+)*)")
DECL = re.compile(r"\s*" + MODIFIER + r"(class|struct|enum|protocol|actor|typealias|extension|func|var|let)\s+"
                  r"([A-Za-z_]\w*)(.*)")
WHOLE_TYPE = re.compile(r"\s*" + MODIFIER + r"(?:init\b|subscript\b|(?:static\s+)?func\s+[^\w\s(])")
IDENT = re.compile(r"[A-Za-z_]\w*")
DOTTED = re.compile(r"\.\s*([A-Za-z_]\w*)")
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
PLATFORM_IF = re.compile(r"^\s*#(?:if|elseif)\b.*\b(?:os|canImport|targetEnvironment|arch)\(", re.M)
PRIVATE = re.compile(r"\b(?:private|fileprivate)\s")
XCTEST_METHOD = re.compile(r"\bfunc\s+test\w*\s*\(")
# An accessibility identifier's spelling: `deck.card.counter`, or the fixed start of "tab.\(id)".
IDENTIFIER = re.compile(r"[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9_-]+)+\Z")
IDENTIFIER_START = re.compile(r"[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9_-]+)*\.?\Z")


class SelectorError(Exception):
    pass


def git(*args):
    result = subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise SelectorError(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


_GLOBS = {}


def glob_regex(pattern):
    if pattern not in _GLOBS:
        out, i = [], 0
        while i < len(pattern):
            if pattern.startswith("**/", i):
                out.append("(?:.*/)?")
                i += 3
            elif pattern.startswith("**", i):
                out.append(".*")
                i += 2
            elif pattern[i] == "*":
                out.append("[^/]*")
                i += 1
            elif pattern[i] == "?":
                out.append("[^/]")
                i += 1
            else:
                out.append(re.escape(pattern[i]))
                i += 1
        _GLOBS[pattern] = re.compile("".join(out) + r"\Z")
    return _GLOBS[pattern]


def matches(path, patterns):
    return any(glob_regex(p).match(path) for p in patterns)


def strip_swift(src):
    """Swift with comments and string contents removed; interpolations stay."""
    out, i, n = [], 0, len(src)
    holes = []  # strings we're inside an interpolation of: [hashes, triple, open parens]
    opener = re.compile(r'(#*)("""|")')

    def string_body(i, hashes, triple):
        close = ('"""' if triple else '"') + "#" * hashes
        escape = "\\" + "#" * hashes
        while i < n:
            if src.startswith(escape, i):
                j = i + len(escape)
                if j < n and src[j] == "(":
                    holes.append([hashes, triple, 0])
                    return j + 1
                i = j + 1
            elif src.startswith(close, i):
                return i + len(close)
            elif src[i] == "\n" and not triple:
                return i
            else:
                i += 1
        return i

    while i < n:
        c = src[i]
        if src.startswith("//", i):
            end = src.find("\n", i)
            i = n if end < 0 else end
            continue
        if src.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif src.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    out.append("\n" if src[i] == "\n" else "")
                    i += 1
            continue
        if c in '#"':
            m = opener.match(src, i)
            if m and (c == '"' or m.group(1)):
                body = string_body(m.end(), len(m.group(1)), m.group(2) == '"""')
                out.append('""' + "\n" * src.count("\n", i, body))
                i = body
                continue
        if holes and c == "(":
            holes[-1][2] += 1
        elif holes and c == ")":
            if holes[-1][2] == 0:
                hashes, triple, _ = holes.pop()
                body = string_body(i + 1, hashes, triple)
                out.append(" " + "\n" * src.count("\n", i, body))
                i = body
                continue
            holes[-1][2] -= 1
        out.append(c)
        i += 1
    return "".join(out)


class SwiftFile:
    """What one Swift file declares, extends, names and reads, and the tests it declares."""

    def __init__(self, path, text):
        self.path = path
        code = strip_swift(text)
        self.refs = set(IDENT.findall(code))
        self.dotted = set(DOTTED.findall(code))  # names used as `.name`: members, cases, key paths
        self.names = set()       # top-level declarations other files can use
        self.members = set()     # (extended type and its enclosing types, member, kind) its extensions add
        self.inherits = {}       # declared or extended type -> the types it conforms to or inherits
        self.literals = set(LITERAL.findall(text))
        self.suites = {}         # Swift Testing suite type or "function()" -> its @Test count
        self.classes = {}        # class -> superclass name
        self.test_methods = {}   # class -> its `func test...` count
        self.platform_if = bool(PLATFORM_IF.search(code))
        self.uses_file_path = "URL(fileURLWithPath: #filePath)" in code
        depth, current, extended, test_attribute, suite_attribute = 0, None, (), False, False
        for line in code.split("\n"):
            decl = DECL.match(line)
            if depth == 0:
                if decl:
                    modifiers, kind, name, rest = decl.groups()
                    head = rest.split("{")[0].split(" where ")[0]
                    nested = re.findall(r"\.([A-Za-z_]\w*)", head.split(":")[0]) if head.startswith(".") else []
                    qualified = (name, *nested)
                    supers = re.findall(r"(?:^|,)\s*(?:@\w+\s+)?([A-Za-z_]\w*)", head.split(":", 1)[1]) if ":" in head else []
                    if kind in ("class", "struct", "enum", "protocol", "actor", "extension") and supers:
                        self.inherits.setdefault(qualified[-1], set()).update(supers)
                    if kind == "extension":
                        extended = qualified
                        if supers:
                            self.members.add((extended, qualified[-1], "type"))  # a conformance
                    elif not PRIVATE.search(modifiers + " "):
                        self.names.add(name)
                    if kind == "class":
                        base = re.match(r"\s*:\s*([A-Za-z_]\w*)", rest)
                        self.classes[name] = base.group(1) if base else None
                    if kind == "func" and (test_attribute or "@Test" in line):
                        self.suites[name + "()"] = 1
                    elif kind != "func" and (suite_attribute or "@Suite" in line):
                        self.suites.setdefault(name, 0)
                    current = (kind, name)
                    test_attribute = suite_attribute = False
                else:
                    test_attribute = test_attribute or "@Test" in line
                    suite_attribute = suite_attribute or "@Suite" in line
            elif current and current[0] not in ("func", "var", "let", "typealias"):
                kind, name = current
                tests = line.count("@Test")
                if tests:
                    self.suites[name] = self.suites.get(name, 0) + tests
                if depth == 1 and XCTEST_METHOD.search(line):
                    self.test_methods[name] = self.test_methods.get(name, 0) + 1
                if kind == "extension" and depth == 1:
                    if decl and decl.group(2) != "extension" and not PRIVATE.search(decl.group(1) + " "):
                        self.members.add((extended, decl.group(3), "member"))
                    elif WHOLE_TYPE.match(line):
                        # An init's first parameter name is its label; a subscript has one only when
                        # it spells two names (`subscript(safe index:)`).
                        label = (re.search(r"\binit\s*[?!]?\s*\(\s*([A-Za-z_]\w*)\b", line)
                                 or re.search(r"\bsubscript\s*\(\s*([A-Za-z_]\w*)\s+[A-Za-z_]\w*\s*:", line))
                        if label and label.group(1) != "_":
                            self.members.add((extended, label.group(1), "label"))  # init(hex:), subscript(safe i:)
                        else:
                            self.members.add((extended, extended[-1], "type"))  # init(_:), subscript, operators
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                depth, current = 0, None


class Tree:
    """The Swift files compiled into one target set, with a name and conformance index."""

    def __init__(self, files):
        self.files = files  # path -> SwiftFile
        self.users = {}     # identifier -> files naming it
        self.dotted = {}    # identifier -> files using it as `.name`
        for path, f in files.items():
            for name in f.refs:
                self.users.setdefault(name, set()).add(path)
            for name in f.dotted:
                self.dotted.setdefault(name, set()).add(path)
        self.declared = set().union(*(f.names for f in files.values())) if files else set()
        children = {}
        for f in files.values():
            for child, supers in f.inherits.items():
                for parent in supers:
                    children.setdefault(parent, set()).add(child)
        self.conformers = {}  # type -> it and every type conforming to or inheriting it
        for parent in children:
            seen, queue = {parent}, [parent]
            while queue:
                for child in children.get(queue.pop(), ()):
                    if child not in seen:
                        seen.add(child)
                        queue.append(child)
            self.conformers[parent] = seen

    def dependents(self, f, skip, names=None, members=None):
        """Files that use what `f` declares, or the given subset of it: path -> the name."""
        found = {}
        for name in sorted(f.names if names is None else names):
            for path in self.users.get(name, ()):
                found.setdefault(path, name)
        for types, member, kind in sorted(f.members if members is None else members):
            known = [t for t in types if t in self.declared]
            anchors = set().union(*(self.conformers.get(t, {t}) for t in known))
            named = set().union(*(self.users.get(a, set()) for a in anchors))  # name the type or a conformer
            if kind == "label":  # or Type.init, a trailing closure, defaulted arguments: the type named
                users = set(self.users.get(member, ())) | (named if known else set(self.users.get(types[-1], ())))
            elif kind == "type":  # View, Array: an operator or subscript on a type declared elsewhere
                users = named if known else set(self.files)
            else:
                users = set(self.dotted.get(member, ())) | (self.users.get(member, set()) & named)
            for path in users:
                found.setdefault(path, types[-1] if kind == "type" else f"{types[-1]}.{member}")
        found.pop(skip, None)
        return {path: name for path, name in found.items() if layer(path) >= layer(f.path)}

    def closure(self, seeds, stop=()):
        """seeds: path -> (parent, how); every file reached, with how. Files matching `stop` are
        reached but not followed, unless they are seeds."""
        reached, queue = dict(seeds), deque(sorted(seeds))
        while queue:
            path = queue.popleft()
            f = self.files.get(path)
            if not f or (path not in seeds and matches(path, stop)):
                continue
            for user, name in sorted(self.dependents(f, path).items()):
                if user not in reached:
                    reached[user] = (path, f"uses {name}")
                    queue.append(user)
        return reached


def identifier_keys(literals):
    """The accessibility identifiers string literals spell: (text, whether only its start is fixed)."""
    keys = set()
    for literal in literals:
        if "\\(" in literal:
            start = literal.split("\\(")[0]
            if "." in start and IDENTIFIER_START.match(start):
                keys.add((start, True))
        elif IDENTIFIER.match(literal):
            keys.add((literal, False))
    return keys


def support_members(text):
    """A UI support file's members: name -> (literals, names used), and the literals outside them."""
    members, outside = {}, set()
    depth, current, opened, parens, body, kind = 0, None, 0, 0, False, None
    for code, raw in zip(strip_swift(text).split("\n"), text.split("\n")):
        decl = DECL.match(code)
        if current is None and decl and decl.group(2) in ("func", "var", "let") and depth <= 1:
            current, opened, parens, body, kind = decl.group(3), depth, 0, False, decl.group(2)
            members.setdefault(current, (set(), set()))
        literals = set(LITERAL.findall(raw))
        if current:
            members[current][0].update(literals)
            members[current][1].update(IDENT.findall(code))
        else:
            outside.update(literals)
        depth += code.count("{") - code.count("}")
        parens += code.count("(") - code.count(")")
        body = body or "{" in code
        # A member ends with its body; a signature may span lines before the body opens.
        if current and depth <= opened and parens <= 0 and (body or kind != "func"):
            current = None
    return members, outside


def same_identifier(a, b):
    """Whether two spellings can name the same identifier: "tab.\\(id)" and "tab.other" can."""
    (text_a, open_a), (text_b, open_b) = a, b
    if open_a and open_b:
        return text_a.startswith(text_b) or text_b.startswith(text_a)
    if open_a or open_b:
        whole, start = (text_b, text_a) if open_a else (text_a, text_b)
        return whole.startswith(start)
    return text_a == text_b


def layer(path):
    """0 AthkarCore, 1 app sources, 2 tests: a file sees its own layer and those below it."""
    if path.startswith(CORE_SOURCES):
        return 0
    if path.startswith(APP):
        return 1
    return 2


def models_sources(package_text):
    """The app files ios/Package.swift compiles into AthkarModels."""
    target = re.search(r'name:\s*"AthkarModels".*?sources:\s*\[(.*?)\]', package_text, re.S)
    if not target:
        raise SelectorError("ios/Package.swift: no AthkarModels sources list")
    return [APP + s for s in re.findall(r'"([^"]+\.swift)"', target.group(1))]


def local_imports(script, read):
    """The repository modules a Node script loads, itself included."""
    seen, queue = [], [script]
    while queue:
        path = queue.pop()
        if path in seen:
            continue
        seen.append(path)
        text = read(path)
        for spec in re.findall(r'''(?:from|import)\s*\(?\s*["'](\.{1,2}/[^"']+)["']''', text or ""):
            queue.append(os.path.normpath(os.path.join(os.path.dirname(path), spec)))
    return seen


class Index:
    """The repository at the working tree: files, Swift targets, tests and what reads what."""

    def __init__(self, files, read):
        self.files = files
        self.read = read
        self.dirs = set()
        for p in files:
            while "/" in p:
                p = p.rsplit("/", 1)[0]
                self.dirs.add(p)
        self.basenames = {}
        for p in files:
            self.basenames.setdefault(p.rsplit("/", 1)[-1], []).append(p)
        self.swift = {p: SwiftFile(p, read(p)) for p in files if p.startswith("ios/") and p.endswith(".swift")}
        self.models = models_sources(read("ios/Package.swift"))
        core = [p for p in self.swift if p.startswith(CORE_SOURCES)]
        scopes = {
            "core": core + [p for p in self.swift if p.startswith(CORE_TESTS)],
            "models": core + [p for p in self.models if p in self.swift]
            + [p for p in self.swift if p.startswith(PORTABLE_TESTS)],
            "app": core + [p for p in self.swift if p.startswith((APP, APP_TESTS))],
            "ui": [p for p in self.swift if p.startswith(UI_TESTS)],
        }
        self.trees = {name: Tree({p: self.swift[p] for p in paths}) for name, paths in scopes.items()}
        self.test_dirs = {"core": CORE_TESTS, "models": PORTABLE_TESTS, "app-unit": APP_TESTS, "ui": UI_TESTS}
        self.units = {lane: self._units(lane) for lane in self.test_dirs}  # lane -> unit -> (files, count)
        self.reads = {p: self._reads(f) for p, f in self.swift.items()}
        self.ui_spelled = {}  # UI class or "*" -> the identifier spellings it uses
        self.ui_identifiers = self._ui_identifiers()  # UI class or "*" -> app file -> identifier
        self.node_inputs = {name: local_imports(script, read) + reads
                            for name, (script, reads) in NODE_CHECKS.items()}
        self.node_inputs["content-review-test"] += local_imports("tools/content-validate.mjs", read)

    def _units(self, lane):
        files = {p: f for p, f in self.swift.items() if p.startswith(self.test_dirs[lane])}
        units = {}
        if lane == "core":  # a suite's tests may sit in extensions in other files
            for p, f in files.items():
                for u, n in f.suites.items():
                    paths, count = units.get(u, ((), 0))
                    units[u] = (paths + (p,), count + n)
            return units
        bases = {c: b for f in files.values() for c, b in f.classes.items()}
        methods, owners = {}, {}
        for p, f in files.items():
            for c, n in f.test_methods.items():
                methods[c] = methods.get(c, 0) + n
                owners.setdefault(c, set()).add(p)
        for p, f in files.items():
            for cls in f.classes:
                ancestor, chain, count = cls, set(), 0
                while ancestor in bases and ancestor not in chain:
                    chain.add(ancestor)
                    count += methods.get(ancestor, 0)
                    ancestor = bases[ancestor]
                if ancestor == "XCTestCase" and count:
                    units[cls] = (tuple(sorted({p, *owners.get(cls, ())})), count)
        return units

    def _ui_identifiers(self):
        """The app files that spell an accessibility identifier a UI test uses: in its own file, or in
        a member of the shared support (UI test files with no test class) it uses. "*", every UI test:
        the support's set-up, and what its files spell outside any member."""
        app = {p: identifier_keys(f.literals) for p, f in self.swift.items() if p.startswith(APP)}
        files = {p: f for p, f in self.swift.items() if p.startswith(UI_TESTS)}
        owned = {p for paths, _ in self.units["ui"].values() for p in paths}
        support, everywhere = {}, set()  # member -> (identifiers, names it uses)
        for path in sorted(set(files) - owned):
            members, outside = support_members(self.read(path))
            everywhere |= identifier_keys(outside)
            for name, (literals, refs) in members.items():
                keys, uses = support.setdefault(name, (set(), set()))
                keys |= identifier_keys(literals)
                uses |= refs

        def through_support(refs):
            seen, queue = set(), [n for n in refs if n in support]
            while queue:
                name = queue.pop()
                if name not in seen:
                    seen.add(name)
                    queue.extend(n for n in support[name][1] if n in support)
            return set().union(*(support[n][0] for n in seen))

        spelled = {"*": everywhere | through_support({"setUp", "setUpWithError", "tearDown", "tearDownWithError"})}
        for cls, (paths, _) in self.units["ui"].items():
            spelled[cls] = set().union(*(identifier_keys(files[p].literals) | through_support(files[p].refs)
                                         for p in paths))
        self.ui_spelled = spelled
        found = {}
        for cls, keys in spelled.items():
            for key in sorted(keys):
                for app_path, app_keys in sorted(app.items()):
                    if any(same_identifier(key, k) for k in app_keys):
                        found.setdefault(cls, {}).setdefault(app_path, key[0] + ("…" if key[1] else ""))
        return found

    def _reads(self, f):
        if f.path in READS:
            return list(READS[f.path])
        found = []
        for lit in sorted(f.literals):
            if "\\(" in lit:
                static = lit.split("\\(")[0]
                if "/" in static and static.rsplit("/", 1)[0] in self.dirs:
                    found.append(re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "*", lit))
            elif lit in self.files:
                found.append(lit)
            elif "/" in lit and lit.strip("/") in self.dirs:
                found.append(lit.strip("/") + "/**")
            elif "/" not in lit and "." in lit:
                found.extend(self.basenames.get(lit, []))
        return found

    def readers(self, path):
        return sorted(p for p, reads in self.reads.items() if matches(path, reads))

    def unit_lane_of(self, path):
        for lane, prefix in self.test_dirs.items():
            if path.startswith(prefix):
                return lane
        return None


class Selection:
    """What each lane runs for a set of changes."""

    def __init__(self, index, changes, old_text=lambda path: None, everything=None):
        self.index = index
        self.changes = changes
        self.units = {lane: {} for lane in LANES}   # lane -> unit -> why
        self.full = {}                               # lane -> why the whole lane runs
        self.docs, self.untested, self.unmapped = [], [], []
        if everything:
            self._everything(everything)
            return
        seeds = {}  # Swift file -> (None, why)
        old = {}    # changed Swift path -> its version at the base
        for status, path in changes:
            hit = False
            if matches(path, SHARED):
                self._everything(f"{path} is a shared build input")
                hit = True
            if matches(path, SELECTOR):
                self.units["selector"].setdefault("self-test", f"{path} changed")
                hit = True
            if matches(path, MAC_RUNNER):
                for lane in LISTED:
                    self.full.setdefault(lane, f"{path} runs them")
                hit = True
            for name, inputs in index.node_inputs.items():
                if matches(path, inputs):
                    self.units["content"].setdefault(name, f"it reads {path}")
                    hit = True
            if path.endswith(".swift") and path.startswith("ios/"):
                if path in index.swift or status in ("M", "D"):
                    in_scope = any(path in t.files for t in index.trees.values()) or (
                        status == "D" and path.startswith((CORE_SOURCES, CORE_TESTS, APP, PORTABLE_TESTS,
                                                           APP_TESTS, UI_TESTS)))
                    if in_scope:
                        hit = True
                        if path in index.swift:
                            seeds.setdefault(path, (None, "changed"))
                        if status in ("M", "D"):
                            text = old_text(path)
                            if text is not None:
                                old[path] = SwiftFile(path, text)
            for reader in index.readers(path):
                if reader != path:
                    seeds.setdefault(reader, (None, f"reads {path}"))
                hit = True
            if matches(path, APP_INPUTS):
                self.units["ios-build"].setdefault("app", f"{path} goes into the app")
                hit = True
            if path.startswith(APP_TESTS):
                self.units["ios-build"].setdefault("tests", f"{path} is an app-unit test")
            for cls, patterns in UI_BLACK_BOX.items():
                if not path.startswith(APP) and matches(path, patterns):
                    self._ui(cls, f"it checks {path}")
                    hit = True
            if path.startswith(APP) and not path.endswith(".swift"):
                # A resource the app bundles: the UI tests that name it, else every UI test.
                classes = [c for c, patterns in UI_BLACK_BOX.items() if matches(path, patterns)]
                for cls in classes or ["*"]:
                    self._ui(cls, f"it checks {path}" if classes else f"the app bundles {path}")
                hit = True
            if not hit:
                if matches(path, NO_TESTS):
                    self.docs.append(path)
                elif matches(path, UNTESTED):
                    self.untested.append(path)
                else:
                    self.unmapped.append(path)
        if self.unmapped:
            self._everything(f"{self.unmapped[0]} matches no rule")
            return
        if "app" in self.units["ios-build"]:
            self.units["ios-build"].setdefault("tests", self.units["ios-build"]["app"])
        self._swift("core", "core", seeds, old)
        self._swift("models", "models", seeds, old)
        start = self._swift("app", "app-unit", seeds, old)
        reached = self.index.trees["app"].closure(start, stop=UI_ROOTS)
        identifiers = self.index.ui_identifiers
        for path in reached:
            if path.startswith(APP) and (path in start or not matches(path, UI_ROOTS)):
                for cls in sorted(set(UI_BLACK_BOX) | set(identifiers)):
                    if matches(path, UI_BLACK_BOX.get(cls, ())):
                        self._ui(cls, f"it checks {chain(reached, path)}")
                    elif path in identifiers.get(cls, {}):
                        self._ui(cls, f"it uses {identifiers[cls][path]}, which {chain(reached, path)}")
        for path, f in sorted(old.items()):  # an identifier the change renamed or removed
            if path.startswith(APP):
                before = identifier_keys(f.literals)
                for cls, keys in sorted(self.index.ui_spelled.items()):
                    used = [k for k in sorted(keys) if any(same_identifier(k, b) for b in before)]
                    if used:
                        self._ui(cls, f"it uses {used[0][0]}{'…' if used[0][1] else ''}, "
                                      f"which {Path(path).name} spelled before the change")
        self._swift("ui", "ui", seeds, old)

    def _swift(self, scope, lane, seeds, old):
        """Selects lane's units the changes reach in scope; returns where the walk started."""
        tree = self.index.trees[scope]
        start = {p: v for p, v in seeds.items() if p in tree.files}
        for path, f in old.items():
            new = self.index.swift.get(path)
            gone_names = f.names - new.names if new else f.names
            gone_members = f.members - new.members if new else f.members
            for user, name in tree.dependents(f, path, gone_names, gone_members).items():
                start.setdefault(user, (path, f"used {name}, which the change removed"))
        reached = tree.closure(start)
        for path in reached:
            for unit, (files, _) in self.index.units[lane].items():
                if path in files:
                    self.units[lane].setdefault(unit, chain(reached, path))
        return start

    def _ui(self, cls, why):
        for unit in (self.index.units["ui"] if cls == "*" else [cls]):
            self.units["ui"].setdefault(unit, why)

    def _everything(self, why):
        for lane in LANES:
            self.full.setdefault(lane, why)

    def runs(self, lane):
        return lane in self.full or bool(self.units[lane])

    def picked(self, lane):
        """lane's units, all of them when it runs in full: unit -> why."""
        if lane in self.full:
            return {u: self.full[lane] for u in self.all_units(lane)}
        return dict(sorted(self.units[lane].items()))

    def all_units(self, lane):
        if lane == "selector":
            return ["self-test"]
        if lane == "content":
            return list(NODE_CHECKS)
        if lane == "ios-build":
            return ["app", "tests"]
        return sorted(self.index.units[lane])


def chain(reached, path):
    """How a file was reached: the changed file last."""
    hops = []
    seen = set()
    while path in reached and path not in seen:
        seen.add(path)
        parent, how = reached[path]
        hops.append(f"{Path(path).name} {how}")
        if parent is None:
            break
        path = parent
    return " ← ".join(hops)


def worktree_files():
    out = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
    return sorted({p for p in out.split("\0") if p and (REPO / p).is_file()})


def read_worktree(path):
    try:
        return (REPO / path).read_text(errors="replace")
    except OSError:
        return ""


def resolve_base(base):
    ref = base or os.environ.get("ATHKAR_TEST_BASE") or DEFAULT_BASE
    try:
        commit = git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}").strip()
    except SelectorError:
        raise SelectorError(f"the base {ref} is not a branch or commit here") from None
    merge_base = git("merge-base", commit, "HEAD").strip()
    return merge_base, f"{ref} (merge base {merge_base[:7]})"


def changes_since(merge_base):
    out = git("diff", "--name-status", "--no-renames", "-z", merge_base, "--").split("\0")
    found = {out[i + 1]: out[i] for i in range(0, len(out) - 1, 2)}
    for path in git("ls-files", "-z", "--others", "--exclude-standard").split("\0"):
        if path:
            found.setdefault(path, "A")
    return sorted((status, path) for path, status in found.items())


def old_text_at(commit):
    def read(path):
        result = subprocess.run(["git", "-C", str(REPO), "show", f"{commit}:{path}"],
                                capture_output=True, text=True)
        return result.stdout if result.returncode == 0 else None
    return read


def load(base, select_all):
    """(index, selection, base label); a selector error selects everything and says why."""
    index = Index(worktree_files(), read_worktree)
    if select_all:
        return index, Selection(index, [], everything="--all"), "--all"
    try:
        merge_base, label = resolve_base(base)
        changes = changes_since(merge_base)
        return index, Selection(index, changes, old_text_at(merge_base)), label
    except Exception as error:  # Fail safe: anything unexpected runs everything.
        return index, Selection(index, [], everything=f"selector error: {error}"), "unknown"


def unit_filter(lane, units):
    # A free @Test function's identifier carries its argument labels: name() or name(_:).
    names = "|".join(re.escape(u[:-2]) + r"\([^/]*\)" if u.endswith("()") else re.escape(u) for u in units)
    return rf"{TEST_MODULE[lane]}[./]({names})(/|$)"


def lane_values(sel, lane):
    """(runs, what, shell assignments) for one lane."""
    index = sel.index
    picked = sel.picked(lane)
    runs = sel.runs(lane)
    full = lane in sel.full
    values = {"ATHKAR_TEST_FULL": "1" if full else "0", "ATHKAR_TEST_UNITS": " ".join(picked)}
    if lane in ("core", "models", "app-unit", "ui"):
        every = index.units[lane]
        count = sum(every[u][1] for u in picked if u in every)
        total = sum(n for _, n in every.values())
        kind = "suites" if lane == "core" else "classes"
        what = f"{len(picked)} of {len(every)} {kind} ({count} of {total} tests)"
        values["ATHKAR_TEST_COUNT"] = str(count)
        if lane in ("core", "models"):
            values["ATHKAR_TEST_FILTER"] = "" if full or not picked else unit_filter(lane, picked)
        else:
            module = TEST_MODULE[lane]
            values["ATHKAR_TEST_ONLY_TESTING"] = (f"-only-testing:{module}" if full or set(picked) == set(every)
                                                  else " ".join(f"-only-testing:{module}/{u}" for u in picked))
    elif lane == "content":
        values["ATHKAR_TEST_CHECKS"] = " ".join(picked)
        what = " ".join(picked)
    elif lane == "ios-build":
        values["ATHKAR_TEST_BUILD_APP"] = "1" if "app" in picked else "0"
        values["ATHKAR_TEST_BUILD_TESTS"] = "1" if "tests" in picked else "0"
        what = {("app", "tests"): "compile the app; AthkarTests listed", ("app",): "compile the app",
                ("tests",): "AthkarTests listed", (): ""}[tuple(sorted(picked))]
    else:
        what = "tools/affected-tests-test.py"
    return runs, what, values


def plan_report(sel, label):
    report = {"base": label, "changed": [f"{s} {p}" for s, p in sel.changes], "lanes": {},
              "docs": sel.docs, "untested": sel.untested, "unmapped": sel.unmapped}
    for lane in LANES:
        runs, what, values = lane_values(sel, lane)
        report["lanes"][lane] = {"runs": runs, "full": lane in sel.full, "what": what if runs else None,
                                 "units": sorted(sel.picked(lane)) if runs else [],
                                 "why": [f"{u}: {w}" for u, w in sel.picked(lane).items()] if runs else [],
                                 "values": values}
    return report


def parse_mode(args):
    base, select_all, rest, i = None, False, [], 0
    while i < len(args):
        if args[i] == "--all":
            select_all = True
        elif args[i] == "--base":
            if i + 1 >= len(args):
                usage("--base needs a branch or commit")
            base = args[i + 1]
            i += 1
        else:
            rest.append(args[i])
        i += 1
    if base and select_all:
        usage("--all and --base don't go together")
    return base, select_all, rest


def usage(message):
    print(f"affected-tests: {message}", file=sys.stderr)
    sys.exit(2)


def cmd_plan(args):
    base, select_all, rest = parse_mode(args)
    if set(rest) - {"--json"}:
        usage(f"unknown arguments: {' '.join(rest)}")
    _, sel, label = load(base, select_all)
    report = plan_report(sel, label)
    if "--json" in rest:
        print(json.dumps(report, indent=2))
        return
    print(f"{len(sel.changes)} changed since {label}")
    if not sel.changes and not sel.full:
        print(f"No changes since {label}, so nothing runs. --all runs every lane.")
    for status, path in sel.changes:
        print(f"  {status} {path}")
    for lane, entry in report["lanes"].items():
        title = lane + "*" if lane in LISTED else lane
        scope = ("everything: " if entry["full"] else "") + (entry["what"] or "") if entry["runs"] else "nothing to run"
        print(f"{title:<10} {scope}")
        if entry["full"]:
            print(f"{'':<11}{sel.full[lane]}")
            continue
        for line in entry["why"]:
            print(f"{'':<11}{line}")
    print("* listed, not run on Linux: app-unit needs an iOS device; ui runs on the Mac (tools/ios-mac-run.sh test)")
    if sel.docs:
        print("Documentation only, no tests: " + ", ".join(sel.docs))
    if sel.untested:
        print("No test covers: " + ", ".join(sel.untested))


def cmd_select(args):
    base, select_all, rest = parse_mode(args)
    if len(rest) != 1 or rest[0] not in LANES:
        usage(f"select needs one lane: {', '.join(LANES)}")
    lane = rest[0]
    _, sel, label = load(base, select_all)
    runs, what, values = lane_values(sel, lane)
    full = lane in sel.full
    print(f"{lane}: {len(sel.changes)} changed since {label}", file=sys.stderr)
    if not runs:
        print(f"{lane}: nothing to run", file=sys.stderr)
    elif full:
        print(f"{lane}: everything ({what}): {sel.full[lane]}", file=sys.stderr)
    else:
        print(f"{lane}: {what}", file=sys.stderr)
        for unit, why in sel.picked(lane).items():
            print(f"  {unit}: {why}", file=sys.stderr)
    values.update({"ATHKAR_TEST_LANE": lane, "ATHKAR_TEST_BASE_LABEL": label, "ATHKAR_TEST_RUN": "1" if runs else "0",
                   "ATHKAR_TEST_WHAT": (("everything: " if full else "") + what) if runs else "nothing to run",
                   "ATHKAR_TEST_REASON": sel.full.get(lane, "the changes reach these" if runs else "no change reaches it")})
    for key, value in values.items():
        print(f"{key}={shlex.quote(value)}")


def check_problems(index):
    problems = []
    files = index.files
    lists = {"NO_TESTS": NO_TESTS, "UNTESTED": UNTESTED, "SHARED": SHARED, "SELECTOR": SELECTOR,
             "MAC_RUNNER": MAC_RUNNER, "APP_RESOURCES": APP_RESOURCES, "GENERATED_FIXTURES": GENERATED_FIXTURES,
             "UI_ROOTS": UI_ROOTS,
             **{f"READS[{p}]": r for p, r in READS.items()}, **{f"NODE_CHECKS[{n}]": r for n, r in index.node_inputs.items()},
             **{f"UI_BLACK_BOX[{c}]": r for c, r in UI_BLACK_BOX.items()}}
    for name, patterns in lists.items():
        for pattern in patterns:
            if not any(matches(p, [pattern]) for p in files):
                problems.append(f"{name}: {pattern} matches no file")
    for path in READS:
        if path not in index.swift:
            problems.append(f"READS names {path}, which is not a Swift file")
    ui = index.units["ui"]
    for cls in sorted(set(UI_BLACK_BOX) - {"*"} - set(ui)):
        problems.append(f"UI_BLACK_BOX names {cls}, which no UI test file declares")
    for cls in sorted(set(ui) - set(UI_BLACK_BOX)):
        problems.append(f"{cls} is not in UI_BLACK_BOX: say which app files it checks")
    covered = [p for patterns in UI_BLACK_BOX.values() for p in patterns]
    spelled = {p for files in index.ui_identifiers.values() for p in files}
    for path in sorted(index.swift):
        if path.startswith(APP) and not matches(path, covered) and path not in spelled:
            problems.append(f"{path} is in no UI_BLACK_BOX entry, so no UI test runs for it")
    for path in index.models:
        if path not in index.swift:
            problems.append(f"ios/Package.swift compiles {path}, which does not exist")
    for path, f in sorted(index.swift.items()):
        if path.startswith(LINUX_TEST_DIRS) and f.platform_if:
            problems.append(f"{path} has a platform #if; the Linux selection can't tell which tests exist")
        if f.uses_file_path and not index.reads[path]:
            problems.append(f"{path} reads repository files it doesn't name: add a READS entry")
        if (f.suites or f.test_methods) and index.unit_lane_of(path) is None:
            problems.append(f"{path} declares tests outside the test targets")
    staged = re.search(r"for path in ([^;]*content/manifest\.json[^;]*); do", read_worktree("tools/test-native-core.sh"))
    staged = staged.group(1).replace("\\\n", " ").split() if staged else []
    if staged != APP_RESOURCES:
        problems.append(f"tools/test-native-core.sh stages {staged}, not APP_RESOURCES")
    bundled = re.findall(r"- path: \.\./(\S+)\n\s+buildPhase: resources", read_worktree("ios/project.yml"))
    if bundled != APP_RESOURCES:
        problems.append(f"ios/project.yml bundles {bundled}, not APP_RESOURCES")
    manifest = json.loads(read_worktree("content/manifest.json") or "{}")
    packs = ["content/manifest.json"] + sorted(f"content/{p['file']}" for p in manifest.get("packs", {}).values())
    if sorted(packs) != sorted(BUNDLED_PACKS):
        problems.append(f"content/manifest.json lists {packs}, not BUNDLED_PACKS")
    for lane in ("core", "models", "app-unit", "ui"):
        if not index.units[lane]:
            problems.append(f"no {lane} tests found")
    for path in files:
        sel = Selection(index, [("A", path)])
        if sel.unmapped:
            problems.append(f"{path} matches no rule, so changing it runs every lane")
    return problems


def cmd_check(args):
    if args:
        usage("check takes no arguments")
    index = Index(worktree_files(), read_worktree)
    problems = check_problems(index)
    for line in problems:
        print(f"check: {line}")
    if problems:
        sys.exit(1)
    counts = ", ".join(f"{len(index.units[lane])} {lane}" for lane in ("core", "models", "app-unit", "ui"))
    print(f"check: {len(index.files)} files, every one mapped; test units: {counts}")


def main():
    if len(sys.argv) < 2:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        sys.exit(2)
    command, args = sys.argv[1], sys.argv[2:]
    commands = {"plan": cmd_plan, "select": cmd_select, "check": cmd_check}
    if command not in commands:
        usage(f"unknown command {command}; one of {', '.join(commands)}")
    try:
        commands[command](args)
    except SelectorError as error:
        print(f"affected-tests: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
