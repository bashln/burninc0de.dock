import QtTest
import "../../logic/state.js" as StateLogic
import "../../logic/settings.js" as SettingsLogic
import "../../logic/matching.js" as MatchingLogic
import "../../logic/icons.js" as IconsLogic
import "../../logic/model.js" as ModelLogic
import "../../logic/indicator.js" as IndicatorLogic
import "../../logic/transparency.js" as TransparencyLogic
import "../../logic/actions.js" as ActionsLogic
import "../../logic/intellihide.js" as IntellihideLogic
import "../../logic/edge.js" as EdgeLogic

// Cross-runtime check: the logic modules must load and run under QJSEngine,
// which is the runtime QML uses. The node suite cannot catch that.
TestCase {
  name: "LogicQJSEngine"

  function test_state_array() {
    compare(StateLogic.parseJsonArray('["a","b"]', 4096).length, 2);
    compare(StateLogic.parseJsonArray("bad", 4096).length, 0);
  }

  function test_state_object() {
    compare(StateLogic.parseJsonObject('{"a":1}', 4096).a, 1);
    compare(JSON.stringify(StateLogic.parseJsonObject("[1]", 4096)), "{}");
  }

  function test_settings_defaults() {
    compare(SettingsLogic.normalize({}).iconSize, SettingsLogic.DEFAULTS.iconSize);
  }

  function test_settings_clamp() {
    compare(SettingsLogic.normalize({ iconSize: 1000 }).iconSize, 96);
    compare(SettingsLogic.normalize({ spacing: -5 }).spacing, 0);
  }

  function test_settings_mode_migration() {
    compare(SettingsLogic.normalize({ hideOnEmpty: true }).mode, "autohide");
    compare(SettingsLogic.normalize({ mode: "autohide", hideOnEmpty: false }).mode, "autohide");
  }

  function test_settings_s1_fields() {
    const n = SettingsLogic.normalize({});
    compare(n.position, "bottom");
    compare(n.hideDelay, 500);
    compare(n.indicatorStyle, "dot");
    compare(SettingsLogic.normalize({ position: "diagonal" }).position, "bottom");
    compare(SettingsLogic.normalize({ showDelay: 5000 }).showDelay, 1000);
  }

  function test_matching() {
    verify(MatchingLogic.matchesApp({ appId: "foot" }, { appId: "foot" }));
    verify(!MatchingLogic.matchesApp({ appId: "foot-nvim" }, { appId: "foot" }));
    compare(MatchingLogic.binaryName("foot --app-id=foot-nvim -e nvim"), "foot");
    verify(MatchingLogic.isHiddenApp({ name: "Terminal", entryId: "" }, ["Terminal"]));
  }

  function test_icons() {
    compare(IconsLogic.hostFromClass("chrome-web.whatsapp.com__-Default"), "web.whatsapp.com");
    compare(IconsLogic.resolveLabel("foo", "T", { foo: { name: "Foo" } }), "Foo");
    compare(IconsLogic.resolveIcon("foo", { foo: { icon: "bar" } }), "bar");
  }

  function test_model() {
    const merged = ModelLogic.mergeApps([{ name: "Terminal" }], [{ name: "Firefox" }], ["Terminal"], MatchingLogic.isHiddenApp);
    compare(merged.length, 1);
    compare(merged[0].name, "Firefox");
    const ordered = ModelLogic.applyOrder([{ name: "A" }, { name: "B" }], ["B"]);
    compare(ordered[0].name, "B");
  }

  function test_indicator() {
    compare(IndicatorLogic.spec("dots", 3).segments, 3);
    compare(IndicatorLogic.spec("count", 1).showCount, true);
    compare(IndicatorLogic.spec("dots", 10).segments, IndicatorLogic.LIMIT);
  }

  function test_transparency() {
    const dock = { x: 0, y: 1000, w: 1920, h: 78 };
    compare(TransparencyLogic.alphaFor("fixed", 1, 0.35, 0.75, 0.6), 0.6);
    compare(TransparencyLogic.alphaFor("dynamic", 0.5, 0.35, 0.75, 0), 0.55);
    compare(TransparencyLogic.nearness([], dock, 100), 0);
    compare(TransparencyLogic.nearness([{ x: 0, y: 950, w: 1920, h: 130 }], dock, 100), 1);
  }

  function test_actions() {
    compare(ActionsLogic.routeClick("minimize", true), "minimize");
    compare(ActionsLogic.routeClick("cycle", false), "launch");
    compare(ActionsLogic.cycleIndex([0, 5, 9], -1), 2);
    compare(ActionsLogic.cycleIndex([], 1), -1);
    compare(ActionsLogic.mostRecentIndex([5, 0, 9]), 1);
    verify(ActionsLogic.scrollStep(0, 120).fire);
    compare(ActionsLogic.routeScroll("bogus"), "nothing");
  }

  function test_intellihide() {
    const dock = { x: 0, y: 900, w: 1920, h: 78 };
    const over = { x: 100, y: 850, w: 400, h: 200, focused: false, maximized: false, onTop: false };
    compare(IntellihideLogic.shouldHide(false, "all", [over], dock), false);
    compare(IntellihideLogic.shouldHide(true, "all", [over], dock), true);
    compare(IntellihideLogic.shouldHide(true, "focused", [over], dock), false);
    compare(IntellihideLogic.shouldHide(true, "focused", [{ x: over.x, y: over.y, w: over.w, h: over.h, focused: true }], dock), true);
    const touching = { x: 0, y: 800, w: 100, h: 100 };
    compare(IntellihideLogic.overlaps(touching, dock), false);
  }

  function test_edge() {
    compare(EdgeLogic.info("diagonal").edge, "bottom");
    compare(EdgeLogic.info("left").horizontal, false);
    compare(EdgeLogic.info("top").horizontal, true);
    const bar = { x: 800, y: 239, w: 400, h: 78 };
    const win = { w: 1920, h: 320 };
    const p = EdgeLogic.placeMenu("bottom", bar, 140, { w: 230, h: 400 }, win, 2);
    compare(p.x, Math.max(0, Math.min(bar.x + 140 - 230 / 2, win.w - 230)));
    compare(p.y, bar.y - 2 - 400);
    compare(EdgeLogic.menuSpace("bottom", bar, win), 239);
    const rect = EdgeLogic.barRect({ x: 0, y: 0, w: 1920, h: 1080 }, "bottom", 320, bar);
    compare(rect.y, 1080 - 320 + 239);
    compare(EdgeLogic.magnifyScale(-10000, 500, 140, 1.6), 1);
  }
}
