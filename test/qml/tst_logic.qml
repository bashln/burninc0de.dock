import QtTest
import "../../logic/state.js" as StateLogic
import "../../logic/settings.js" as SettingsLogic
import "../../logic/matching.js" as MatchingLogic
import "../../logic/icons.js" as IconsLogic
import "../../logic/model.js" as ModelLogic
import "../../logic/indicator.js" as IndicatorLogic
import "../../logic/transparency.js" as TransparencyLogic

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
}
