import QtTest
import "../../logic/state.js" as StateLogic

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
}
