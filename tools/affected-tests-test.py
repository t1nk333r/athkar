#!/usr/bin/env python3
"""Tests for tools/affected-tests.py: changes mapped to the selection they must produce.

  python3 tools/affected-tests-test.py [-v]

RepositoryTests select for changes to this repository's own files. SyntheticRepositoryTests run
the command line in small Git repositories, for the rules this repository doesn't exercise today:
removed names, deleted files, extension members, module layers, split test suites and classes, UI
identifiers and support helpers, untracked files, the merge base, the base variable and selector errors.
"""

import importlib.util
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("affected_tests", HERE / "affected-tests.py")
at = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(at)

CORE = "ios/AthkarCore/Sources/AthkarCore/"
CORE_TESTS = "ios/AthkarCore/Tests/AthkarCoreTests/"


def picked(sel):
    """lane -> the units it runs, for the lanes that run."""
    return {lane: set(sel.picked(lane)) for lane in at.LANES if sel.runs(lane)}


class RepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index = at.Index(at.worktree_files(), at.read_worktree)

    def select(self, *paths, status="M"):
        # An edit that keeps every name: the old version is the current one.
        return at.Selection(self.index, [(status, p) for p in paths], at.read_worktree)

    def all_units(self, lane):
        return set(self.index.units[lane])

    def test_documentation_runs_nothing(self):
        sel = self.select("README.md", "docs/agents/ios-linux.md", "NATIVE_APP_PLAN.md")
        self.assertEqual(picked(sel), {})
        self.assertEqual(sel.docs, ["README.md", "docs/agents/ios-linux.md", "NATIVE_APP_PLAN.md"])

    def test_review_record_runs_the_checks_that_read_it(self):
        self.assertEqual(picked(self.select("content/REVIEW.md")),
                         {"content": {"content-validate", "content-review-test"}})

    def test_pack_the_app_does_not_bundle(self):
        # Every pack in content/ is bundled today, so a new one stands in: only the checks that read every pack.
        self.assertEqual(picked(self.select("content/tasbih.v1.json", status="A")), {
            "content": {"content-validate", "content-review-test"},
            "models": {"BundledIntegrityTests"},
        })

    def test_bundled_pack_runs_its_readers_and_the_app(self):
        sel = self.select("content/suwar.v1.json")
        self.assertEqual(picked(sel)["content"],
                         {"content-validate", "content-review-test", "content-export-pwa", "fixtures"})
        self.assertEqual(picked(sel)["models"], {
            "AdhkarPersistenceTests", "BundledIntegrityTests", "DayRolloverTests", "DeckIndexReachabilityTests",
            "PortableModelTests", "ReminderReplanTests", "RuqyahPersistenceTests", "SettingsPersistenceTests",
            "SuwarDeckModelTests", "SuwarPersistenceTests",
        })
        self.assertEqual(picked(sel)["ios-build"], {"app", "tests"})
        self.assertIn("TestInfrastructureTests", picked(sel)["app-unit"])
        self.assertEqual(picked(sel)["ui"], self.all_units("ui"))
        self.assertNotIn("core", picked(sel))

    def test_fixture_runs_the_generator_check_and_the_suites_that_read_it(self):
        self.assertEqual(picked(self.select("spec/reminders/fixtures/next-reminder-time.json")), {
            "content": {"fixtures"},
            "core": {"ReminderFixtureTests", "ReminderPlannerTests"},
        })

    def test_pwa_page_runs_the_export_and_fixture_checks(self):
        self.assertEqual(picked(self.select("index.html")), {"content": {"content-export-pwa", "fixtures"}})

    def test_shared_node_module_runs_each_check_that_loads_it(self):
        self.assertEqual(picked(self.select("tools/content-lib.mjs")), {
            "content": {"content-validate", "content-review-test", "content-export-pwa", "backup-validate"},
        })

    def test_core_source_runs_the_tests_that_depend_on_it(self):
        sel = self.select(CORE + "PrayerTimes/Qibla.swift")
        lanes = picked(sel)
        self.assertEqual(lanes["core"], {"QiblaTests"})
        self.assertEqual(lanes["models"], {"QiblaHeadingTests"})
        self.assertEqual(lanes["ios-build"], {"app", "tests"})
        self.assertIn("QiblaUITests", lanes["ui"])
        # OtherSectionsView.swift uses Qibla, and the deck UI tests open its ruqyah row; the home screen
        # tests never leave the morning deck.
        self.assertIn("DeckIndexUITests", lanes["ui"])
        self.assertNotIn("LaunchTests", lanes["ui"])
        self.assertNotIn("HomePrayerRowUITests", lanes["ui"])
        self.assertEqual(sel.full, {})

    def test_test_support_runs_the_suites_that_use_it(self):
        core = picked(self.select(CORE_TESTS + "Storage/StorageTestSupport.swift"))["core"]
        self.assertIn("StorageSchemaTests", core)
        self.assertNotIn("QiblaTests", core)

    def test_test_file_runs_itself(self):
        self.assertEqual(picked(self.select(CORE_TESTS + "PrayerTimes/QiblaTests.swift")), {"core": {"QiblaTests"}})
        self.assertEqual(picked(self.select("ios/AthkarUITests/QiblaUITests.swift")), {"ui": {"QiblaUITests"}})

    def test_ui_walk_stops_at_the_composition_roots(self):
        self.assertEqual(picked(self.select("ios/Athkar/Deck/DeckIndexView.swift"))["ui"], {"DeckIndexUITests"})

    def test_identifier_a_ui_test_uses_runs_it(self):
        # Settings: DeckUITests toggles manual completion through UITestSupport's
        # markMorningCompleteManually(); HomePrayerRowUITests toggles `settings.homePrayerRow` itself.
        settings = picked(self.select("ios/Athkar/Screens/SettingsView.swift"))["ui"]
        self.assertLessEqual({"DeckUITests", "HomePrayerRowUITests", "DeckRegressionUITests", "DeckIndexUITests",
                              "ReminderUITests"}, settings)
        self.assertNotIn("LaunchTests", settings)
        # The ruqyah deck opens from «أخرى»: UITestSupport's selectTab("ruqyah") taps `other.ruqyah`.
        other = picked(self.select("ios/Athkar/Screens/OtherSectionsView.swift"))["ui"]
        self.assertLessEqual({"DeckUITests", "DeckRegressionUITests", "DeckIndexUITests", "AutoFitUITests"}, other)
        self.assertNotIn("HomePrayerRowUITests", other)

    def test_section_chips_run_the_ui_tests_that_pick_a_sura(self):
        # The chips the ruqyah UI tests tap (`deck.section.<id>`) to reach each sura's segments.
        chips = picked(self.select("ios/Athkar/Deck/SectionChips.swift"))["ui"]
        self.assertLessEqual({"AutoFitUITests", "DeckIndexUITests", "DeckRegressionUITests", "DeckUITests",
                              "ScreenshotUITests"}, chips)

    def test_identifier_spellings(self):
        keys = at.identifier_keys(["deck.card.counter", "tab.\\(id)", "settings.", "مرة", "\\(id).x"])
        self.assertEqual(keys, {("deck.card.counter", False), ("tab.", True)})
        self.assertTrue(at.same_identifier(("tab.", True), ("tab.other", False)))
        self.assertTrue(at.same_identifier(("deck.card.", True), ("deck.", True)))
        self.assertFalse(at.same_identifier(("tab.other", False), ("tab.others", False)))
        self.assertFalse(at.same_identifier(("tab.", True), ("other.ruqyah", False)))

    def test_app_resource_no_entry_names_runs_every_ui_test(self):
        sel = self.select("ios/Athkar/Assets.xcassets/Contents.json")
        self.assertEqual(picked(sel)["ui"], self.all_units("ui"))
        self.assertIn("app", picked(sel)["ios-build"])

    def test_composition_root_runs_every_ui_test(self):
        self.assertEqual(picked(self.select("ios/Athkar/Screens/HomeView.swift"))["ui"], self.all_units("ui"))

    def test_shared_build_input_runs_everything(self):
        for path in ("ios/Package.swift", "ios/project.yml", "ios/Package.resolved", "tools/test-native-core.sh"):
            with self.subTest(path=path):
                sel = self.select(path)
                self.assertEqual(set(sel.full), set(at.LANES))
                self.assertEqual(picked(sel)["core"], self.all_units("core"))

    def test_unknown_file_runs_everything(self):
        sel = self.select("tools/new-check.rb", status="A")
        self.assertEqual(sel.unmapped, ["tools/new-check.rb"])
        self.assertEqual(set(sel.full), set(at.LANES))
        self.assertIn("matches no rule", sel.full["core"])

    def test_untested_file_runs_nothing(self):
        sel = self.select("sw.js", "icons/icon.svg")
        self.assertEqual(picked(sel), {})
        self.assertEqual(sel.untested, ["sw.js", "icons/icon.svg"])

    def test_mac_runner_runs_every_app_unit_and_ui_test(self):
        sel = self.select("tools/ios-mac-run.sh")
        self.assertEqual(set(sel.full), {"app-unit", "ui"})
        self.assertEqual(set(picked(sel)), {"app-unit", "ui"})

    def test_selector_runs_its_own_tests(self):
        for path in ("tools/affected-tests.py", "tools/affected-tests-test.py", "tools/test.sh"):
            with self.subTest(path=path):
                self.assertEqual(picked(self.select(path)), {"selector": {"self-test"}})

    def test_all_runs_everything(self):
        sel = at.Selection(self.index, [], everything="--all")
        self.assertEqual(set(sel.full), set(at.LANES))
        for lane in ("core", "models", "app-unit", "ui"):
            self.assertEqual(set(sel.picked(lane)), self.all_units(lane))

    def test_lane_values(self):
        sel = self.select(CORE + "PrayerTimes/Qibla.swift")
        _, _, core = at.lane_values(sel, "core")
        self.assertEqual(core["ATHKAR_TEST_FULL"], "0")
        self.assertEqual(core["ATHKAR_TEST_FILTER"], r"AthkarCoreTests[./](QiblaTests)(/|$)")
        self.assertEqual(core["ATHKAR_TEST_COUNT"], str(self.index.units["core"]["QiblaTests"][1]))
        _, _, ui = at.lane_values(sel, "ui")
        self.assertIn("-only-testing:AthkarUITests/QiblaUITests", ui["ATHKAR_TEST_ONLY_TESTING"].split())
        _, _, build = at.lane_values(sel, "ios-build")
        self.assertEqual((build["ATHKAR_TEST_BUILD_APP"], build["ATHKAR_TEST_BUILD_TESTS"]), ("1", "1"))
        _, _, full = at.lane_values(at.Selection(self.index, [], everything="--all"), "core")
        self.assertEqual((full["ATHKAR_TEST_FULL"], full["ATHKAR_TEST_FILTER"]), ("1", ""))

    def test_filter_matches_whole_test_identifiers(self):
        import re
        core = re.compile(at.unit_filter("core", ["QiblaTests", "periodRawValuesMatchPWA()"]))
        self.assertTrue(core.search("AthkarCoreTests.QiblaTests/bearingFromRiyadh()"))
        self.assertTrue(core.search("AthkarCoreTests.periodRawValuesMatchPWA()"))
        self.assertFalse(core.search("AthkarCoreTests.QiblaTestsSlow/bearingFromRiyadh()"))
        self.assertFalse(core.search("AthkarCoreTests.NextPrayerTests/qiblaTests()"))
        models = re.compile(at.unit_filter("models", ["QiblaHeadingTests"]))
        self.assertTrue(models.search("AthkarPortableTests.QiblaHeadingTests/testStaleHeading"))
        self.assertFalse(models.search("AthkarPortableTests.QiblaHeadingTestsExtra/testStaleHeading"))
        free = re.compile(at.unit_filter("core", ["legacyNow()"]))
        self.assertTrue(free.search("AthkarCoreTests.legacyNow()"))
        self.assertTrue(free.search("AthkarCoreTests.legacyNow(_:)"))  # parameterized
        self.assertFalse(free.search("AthkarCoreTests.legacyNowIsZero()"))


# A minimal repository with the same layout: AthkarCore, app files compiled into AthkarModels
# (one adds a conformance to a core type), core suites and portable test classes.
SYNTHETIC = {
    "README.md": "# Fixture\n",
    "data/cities.tsv": "Riyadh\n",
    "ios/Package.swift": """\
        let package = Package(name: "Athkar", targets: [
            .target(name: "AthkarModels", path: "Athkar",
                    sources: ["Deck/DeckModel.swift", "Qibla/QiblaDescription.swift"]),
            .testTarget(name: "AthkarPortableTests", dependencies: ["AthkarModels"], path: "AthkarPortableTests"),
        ])
        """,
    CORE + "Qibla.swift": """\
        public enum Qibla {
            public static func bearing() -> Double { 0 }
        }
        """,
    CORE + "Clock.swift": """\
        public struct Clock {
            public var now = 0
            public init() {}
        }

        public func legacyNow() -> Int { 0 }
        """,
    CORE + "Clock+Days.swift": """\
        extension Clock {
            public var tomorrow: Int { now + 1 }
        }
        """,
    CORE + "Ledger.swift": """\
        public struct Ledger {
            public var tomorrow = 0
            public var bearing = Qibla.bearing()
            public init() {}
        }
        """,
    CORE + "Angles.swift": """\
        extension Double {
            public var degrees: Double { self }
        }
        """,
    CORE + "Widget.swift": """\
        public struct Widget {
            public init() {}
        }

        public func makeWidget() -> Widget { Widget() }
        """,
    CORE + "Widget+Probe.swift": """\
        extension Widget {
            public func quuxify() -> Int { 1 }
        }
        """,
    CORE + "String+Probe.swift": """\
        extension String {
            public init<Count: BinaryInteger>(
                probeRepeating count: Count
            ) { self = String(repeating: "x", count: Int(count)) }
        }
        """,
    CORE + "Bool+Plus.swift": """\
        extension Bool {
            public static func + (
                lhs: Int,
                rhs: Bool
            ) -> Int { rhs ? lhs + 1 : (Int.init(radix: 2) ?? lhs) }
        }
        """,
    CORE + "Widget+Named.swift": """\
        extension Widget {
            public init<S: StringProtocol>(
                named: S
            ) { self.init() }
        }
        """,
    CORE + "Widget+Index.swift": """\
        extension Widget {
            public subscript(index: Int) -> Int { index }
        }
        """,
    CORE + "Array+Position.swift": """\
        extension Array {
            public subscript(_ position: Int) -> Element? { indices.contains(position) ? self[position] : nil }
        }
        """,
    CORE + "Dictionary+Slot.swift": """\
        extension Dictionary {
            public subscript(slot: Int) -> Value? { nil }
        }
        """,
    CORE_TESTS + "WidgetNameTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct WidgetNameTests {
            @Test func names() { #expect(["a"].map(Widget.init).count == 1) }
        }
        """,
    CORE_TESTS + "ArrayPositionTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct ArrayPositionTests {
            @Test func outOfRange() { #expect([1, 2, 3][7] == nil) }
        }
        """,
    CORE_TESTS + "WidgetIndexTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct WidgetIndexTests {
            @Test func subscripts() { #expect(makeWidget()[2] == 2) }
        }
        """,
    CORE_TESTS + "WidgetTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct WidgetTests {
            @Test func quuxify() { #expect(makeWidget().quuxify() == 1) }
        }
        """,
    CORE_TESTS + "ProbeStringTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct ProbeStringTests {
            @Test func repeats() { #expect(String(probeRepeating: 2) == "xx") }
        }
        """,
    CORE_TESTS + "SplitTests.swift": """\
        import Testing

        struct SplitTests {
            @Test func one() {}
        }
        """,
    CORE_TESTS + "SplitTests+More.swift": """\
        import Testing

        extension SplitTests {
            @Test func two() { #expect(1 + true == 2) }
        }
        """,
    CORE_TESTS + "QiblaTests.swift": """\
        import Testing
        @testable import AthkarCore

        @Suite struct QiblaTests {
            @Test func bearing() {
                let degrees = Qibla.bearing()
                #expect(degrees == 0)
            }
        }
        """,
    CORE_TESTS + "AngleTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct AngleTests {
            @Test func degrees() { #expect(1.0.degrees == 1) }
        }
        """,
    CORE_TESTS + "ClockTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct ClockTests {
            @Test func tomorrow() { #expect(Clock().tomorrow == 1) }
        }
        """,
    CORE_TESTS + "LedgerTests.swift": """\
        import Testing
        @testable import AthkarCore

        struct LedgerTests {
            @Test func tomorrow() { #expect(Ledger().tomorrow == 0) }
        }
        """,
    CORE_TESTS + "LegacyTests.swift": """\
        import Testing
        @testable import AthkarCore

        @Test func legacyNowIsZero() { #expect(legacyNow() == 0) }
        """,
    CORE_TESTS + "CityTests.swift": """\
        import Testing

        struct CityTests {
            @Test func loads() throws { _ = try String(contentsOfFile: "data/cities.tsv", encoding: .utf8) }
        }
        """,
    "ios/Athkar/Deck/DeckModel.swift": """\
        import AthkarCore

        final class DeckModel {
            let clock = Clock()
        }
        """,
    "ios/Athkar/Qibla/QiblaDescription.swift": """\
        import AthkarCore

        extension Qibla: CustomStringConvertible {
            public var description: String { "qibla" }
        }
        """,
    "ios/AthkarPortableTests/SplitPortableTests.swift": """\
        import XCTest

        final class SplitPortableTests: XCTestCase {
            func testOne() {}
        }
        """,
    "ios/AthkarPortableTests/SplitPortableTests+More.swift": """\
        import XCTest

        extension SplitPortableTests {
            func testTwo() {}
            func testThree() {}
        }
        """,
    # UI tests: app screens spelling accessibility identifiers, a support file and two UI classes.
    "ios/Athkar/Probe/Home.swift": 'struct Home {\n    let id = "home.ready"\n}\n',
    "ios/Athkar/Probe/Deck.swift": 'struct Deck {\n    let next = "deck.next"\n}\n',
    "ios/Athkar/Probe/Settings.swift": 'struct Settings {\n    let close = "settings.close"\n}\n',
    "ios/Athkar/Probe/Prayer.swift": 'struct Prayer {\n    let city = "prayer.\\(1)"\n}\n',
    "ios/Athkar/Probe/Leave.swift": 'struct Leave {\n    let now = "leave.now"\n}\n',
    "ios/AthkarUITests/Support.swift": """\
        import XCTest

        protocol Probing {
            func probe()
        }

        func leaveNow() { XCUIApplication().buttons["leave.now"].tap() }

        enum Screen: String {
            case home = "home.ready"
        }

        class ProbeCase: XCTestCase {
            var app = XCUIApplication()

            override func setUp() {
                app.buttons["deck.next"].tap()
            }

            func closeSettings() { app.buttons["settings.close"].tap() }

            func leaveSettings(
                pause: Double,
                done: () -> Void = {}
            ) {
                closeSettings()
            }
        }
        """,
    "ios/AthkarUITests/PrayerUITests.swift": """\
        import XCTest

        final class PrayerUITests: ProbeCase {
            func testCity() {
                leaveSettings(pause: 1)
                app.buttons["prayer.city"].tap()
            }
        }
        """,
    "ios/AthkarUITests/PlainUITests.swift": """\
        import XCTest

        final class PlainUITests: ProbeCase {
            func testLaunch() { leaveNow() }
        }
        """,
    "ios/AthkarPortableTests/DeckModelTests.swift": """\
        import XCTest
        @testable import AthkarModels

        final class DeckModelTests: XCTestCase {
            func testClock() { XCTAssertEqual(DeckModel().clock.now, 0) }
        }
        """,
    "ios/AthkarPortableTests/LedgerPortableTests.swift": """\
        import XCTest
        @testable import AthkarModels

        final class LedgerPortableTests: XCTestCase {
            func testLedger() { XCTAssertEqual(Ledger().tomorrow, 0) }
        }
        """,
}


class SyntheticRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp(prefix="athkar-affected-"))
        self.addCleanup(shutil.rmtree, self.repo)
        self.env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                    "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
                    "PYTHONDONTWRITEBYTECODE": "1"}
        self.env.pop("ATHKAR_TEST_BASE", None)
        for path, text in SYNTHETIC.items():
            self.write(path, textwrap.dedent(text))
        (self.repo / "tools").mkdir()
        shutil.copy(HERE / "affected-tests.py", self.repo / "tools/affected-tests.py")
        self.git("init", "-q", "-b", "main")
        self.base = self.commit("base")

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "--no-verify", "-m", message)
        return self.git("rev-parse", "HEAD")

    def select(self, lane, *mode):
        """The lane's shell assignments, as a dict."""
        mode = mode or ("--base", self.base)
        result = subprocess.run([sys.executable, str(self.repo / "tools/affected-tests.py"), "select", lane, *mode],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        values = {}
        for line in result.stdout.splitlines():
            key, value = line.split("=", 1)
            values[key] = shlex.split(value)[0] if value else ""
        return values

    def units(self, lane, *mode):
        values = self.select(lane, *mode)
        return set(values["ATHKAR_TEST_UNITS"].split()) if values["ATHKAR_TEST_RUN"] == "1" else set()

    def test_member_edit_runs_the_users_of_that_member(self):
        self.write(CORE + "Clock+Days.swift", "extension Clock {\n    public var tomorrow: Int { now + 2 }\n}\n")
        # `.tomorrow` could be Clock's: LedgerTests' and LedgerPortableTests' run too, but not
        # DeckModelTests, which uses Clock and not `tomorrow`.
        self.assertEqual(self.units("core"), {"ClockTests", "LedgerTests"})
        self.assertEqual(self.units("models"), {"LedgerPortableTests"})

    def test_member_used_on_a_value_whose_type_is_not_named(self):
        self.write(CORE + "Widget+Probe.swift", "extension Widget {\n    public func quuxify() -> Int { 2 }\n}\n")
        self.assertEqual(self.units("core"), {"WidgetTests"})

    def test_labelled_init_of_an_outside_type_runs_its_users(self):
        self.write(CORE + "String+Probe.swift", textwrap.dedent(SYNTHETIC[CORE + "String+Probe.swift"]).replace('"x"', '"y"'))
        # The init is generic and its label is on the next line. CityTests names String, so a
        # String.init without the label could be this one.
        self.assertEqual(self.units("core"), {"ProbeStringTests", "CityTests"})

    def test_operator_on_an_outside_type_runs_every_test_that_sees_it(self):
        # Its body spells `Int.init(radix:)`, which is no label of the operator.
        self.write(CORE + "Bool+Plus.swift", textwrap.dedent(SYNTHETIC[CORE + "Bool+Plus.swift"]).replace("+ 1", "+ 2"))
        self.assertEqual(self.units("core"), self.units("core", "--all"))
        self.assertEqual(self.units("models"), self.units("models", "--all"))

    def test_labelled_init_counts_where_the_type_is_named(self):
        self.write(CORE + "Widget+Named.swift", "extension Widget {\n    public init(named: String) { self.init(); _ = 1 }\n}\n")
        self.assertIn("WidgetNameTests", self.units("core"))  # `Widget.init`, with no label

    def test_subscript_parameter_name_is_not_a_label(self):
        self.write(CORE + "Widget+Index.swift", "extension Widget {\n    public subscript(index: Int) -> Int { index + 0 }\n}\n")
        self.assertIn("WidgetIndexTests", self.units("core"))  # `makeWidget()[2]`
        for subscript in ("subscript(position: Int)", "subscript(_ position: Int)"):
            with self.subTest(subscript=subscript):
                self.write(CORE + "Array+Position.swift",
                           f"extension Array {{\n    public {subscript} -> Element? {{ nil }}\n}}\n")
                self.assertEqual(self.units("core"), self.units("core", "--all"))
        self.git("checkout", "--", ".")
        self.write(CORE + "Dictionary+Slot.swift", "extension Dictionary {\n    public subscript(slot: Int) -> Value? { nil ?? nil }\n}\n")
        self.assertEqual(self.units("core"), self.units("core", "--all"))

    def test_class_extended_in_another_file_runs_from_either(self):
        self.write("ios/AthkarPortableTests/SplitPortableTests+More.swift",
                   "import XCTest\n\nextension SplitPortableTests {\n    func testTwo() {}\n}\n")
        self.assertEqual(self.units("models"), {"SplitPortableTests"})
        self.assertEqual(self.select("models")["ATHKAR_TEST_COUNT"], "2")
        self.git("checkout", "--", ".")
        self.assertEqual(self.select("models", "--all")["ATHKAR_TEST_COUNT"],
                         str(len(self.git("grep", "-h", "func test", "--", "ios/AthkarPortableTests").splitlines())))

    def test_ui_test_runs_for_the_identifiers_it_uses(self):
        # Its own `prayer.city` (the screen spells `prayer.\(…)`), and `settings.close` through
        # leaveSettings, whose signature spans lines and opens a default closure, and closeSettings.
        self.write("ios/Athkar/Probe/Prayer.swift", 'struct Prayer {\n    let city = "prayer.\\(2)"\n}\n')
        self.assertEqual(self.units("ui"), {"PrayerUITests"})
        self.write("ios/Athkar/Probe/Prayer.swift", textwrap.dedent(SYNTHETIC["ios/Athkar/Probe/Prayer.swift"]))
        self.write("ios/Athkar/Probe/Settings.swift", 'struct Settings {\n    let close = "settings.close"; let x = 1\n}\n')
        self.assertEqual(self.units("ui"), {"PrayerUITests"})

    def test_helper_after_a_protocol_requirement_keeps_its_identifiers(self):
        self.write("ios/Athkar/Probe/Leave.swift", 'struct Leave {\n    let now = "leave.now"; let x = 1\n}\n')
        self.assertEqual(self.units("ui"), {"PlainUITests"})

    def test_support_setup_and_loose_identifiers_run_every_ui_test(self):
        for path in ("ios/Athkar/Probe/Deck.swift", "ios/Athkar/Probe/Home.swift"):  # setUp(); an enum case
            with self.subTest(path=path):
                self.write(path, (self.repo / path).read_text() + "// edited\n")
                self.assertEqual(self.units("ui"), {"PrayerUITests", "PlainUITests"})
                self.git("checkout", "--", path)

    def test_renamed_identifier_runs_the_ui_tests_using_the_old_one(self):
        self.write("ios/Athkar/Probe/Settings.swift", 'struct Settings {\n    let close = "settings.done"\n}\n')
        self.assertEqual(self.units("ui"), {"PrayerUITests"})

    def test_suite_extended_in_another_file_runs_from_either(self):
        self.write(CORE_TESTS + "SplitTests+More.swift", "import Testing\n\nextension SplitTests {\n"
                   "    @Test func two() {}\n}\n")
        self.assertEqual(self.units("core"), {"SplitTests"})
        self.assertEqual(self.select("core")["ATHKAR_TEST_COUNT"], "2")

    def test_removed_name_reaches_the_files_still_using_it(self):
        self.write(CORE + "Clock.swift", "public struct Clock {\n    public var now = 0\n    public init() {}\n}\n")
        # Clock+Days.swift extends Clock with `tomorrow`, which LedgerTests also spells as `.tomorrow`.
        self.assertEqual(self.units("core"), {"ClockTests", "LedgerTests", "legacyNowIsZero()"})

    def test_renamed_member_reaches_the_files_still_using_it(self):
        self.write(CORE + "Widget+Probe.swift", "extension Widget {\n    public func frobnicate() -> Int { 1 }\n}\n")
        self.assertEqual(self.units("core"), {"WidgetTests"})  # `.quuxify()`

    def test_member_of_an_outside_type_runs_its_dotted_users(self):
        self.write(CORE + "Angles.swift", "extension Double {\n    public var degrees: Double { self * 1 }\n}\n")
        self.assertEqual(self.units("core"), {"AngleTests"})  # QiblaTests names a local `degrees`

    def test_deleted_file_reaches_its_users(self):
        (self.repo / CORE / "Qibla.swift").unlink()
        self.assertEqual(self.units("core"), {"QiblaTests", "LedgerTests"})
        self.assertEqual(self.select("ios-build")["ATHKAR_TEST_BUILD_APP"], "1")

    def test_app_extension_does_not_reach_core(self):
        # Ledger.swift uses Qibla, but AthkarCore can't see the app's conformance.
        self.write("ios/Athkar/Qibla/QiblaDescription.swift",
                   "import AthkarCore\n\nextension Qibla: CustomStringConvertible {\n"
                   "    public var description: String { \"Qibla\" }\n}\n")
        self.assertEqual(self.units("core"), set())
        self.assertEqual(self.units("models"), set())
        self.assertEqual(self.select("ios-build")["ATHKAR_TEST_RUN"], "1")

    def test_core_change_reaches_portable_tests_through_the_app(self):
        self.write(CORE + "Clock.swift", textwrap.dedent(SYNTHETIC[CORE + "Clock.swift"]).replace("now = 0", "now = 1"))
        self.assertEqual(self.units("models"), {"DeckModelTests", "LedgerPortableTests"})  # `.tomorrow`, as above

    def test_data_file_runs_its_readers(self):
        self.write("data/cities.tsv", "Riyadh\nMakkah\n")
        self.assertEqual(self.units("core"), {"CityTests"})

    def test_untracked_test_file_runs(self):
        self.write(CORE_TESTS + "NewTests.swift", "import Testing\n\nstruct NewTests {\n    @Test func runs() {}\n}\n")
        self.assertEqual(self.units("core"), {"NewTests"})

    def test_untracked_unknown_file_runs_everything(self):
        self.write("notes.xyz", "?\n")
        values = self.select("core")
        self.assertEqual((values["ATHKAR_TEST_FULL"], values["ATHKAR_TEST_FILTER"]), ("1", ""))
        self.assertIn("notes.xyz matches no rule", values["ATHKAR_TEST_REASON"])

    def test_documentation_runs_nothing(self):
        self.write("README.md", "# Fixture, edited\n")
        for lane in at.LANES:
            with self.subTest(lane=lane):
                self.assertEqual(self.select(lane)["ATHKAR_TEST_RUN"], "0")

    def test_changes_count_from_the_merge_base(self):
        self.git("checkout", "-q", "-b", "feature")
        self.write(CORE + "Qibla.swift", "public enum Qibla {\n    public static func bearing() -> Double { 1 }\n}\n")
        self.commit("feature")
        self.git("checkout", "-q", "main")
        self.write("data/cities.tsv", "Riyadh\nMakkah\n")
        self.commit("main moves on")
        self.git("checkout", "-q", "feature")
        # main's cities.tsv change is not on this branch, so CityTests doesn't run.
        self.assertEqual(self.units("core", "--base", "main"), {"QiblaTests", "LedgerTests"})

    def test_selector_error_runs_everything(self):
        values = self.select("core", "--base", "no-such-branch")
        self.assertEqual((values["ATHKAR_TEST_RUN"], values["ATHKAR_TEST_FULL"]), ("1", "1"))
        self.assertIn("selector error: the base no-such-branch is not", values["ATHKAR_TEST_REASON"])

    def test_base_variable_survives_each_lane(self):
        # The runners eval one lane's selection before asking for the next, with ATHKAR_TEST_BASE set.
        self.write(CORE + "Qibla.swift", "public enum Qibla {\n    public static func bearing() -> Double { 1 }\n}\n")
        script = ('for lane in core models; do eval "$("$PYTHON" tools/affected-tests.py select $lane)"; '
                  'echo "$lane $ATHKAR_TEST_FULL $ATHKAR_TEST_UNITS"; done')
        result = subprocess.run(["bash", "-c", script], cwd=self.repo, capture_output=True, text=True,
                                env={**self.env, "ATHKAR_TEST_BASE": self.base, "PYTHON": sys.executable})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["core 0 LedgerTests QiblaTests", "models 0 LedgerPortableTests"])

    def test_all_runs_everything(self):
        values = self.select("core", "--all")
        self.assertEqual((values["ATHKAR_TEST_FULL"], values["ATHKAR_TEST_FILTER"]), ("1", ""))
        self.assertEqual(set(values["ATHKAR_TEST_UNITS"].split()),
                         {"QiblaTests", "AngleTests", "ClockTests", "LedgerTests", "legacyNowIsZero()", "CityTests",
                          "WidgetTests", "ProbeStringTests", "SplitTests", "WidgetNameTests", "WidgetIndexTests",
                          "ArrayPositionTests"})


if __name__ == "__main__":
    unittest.main()
