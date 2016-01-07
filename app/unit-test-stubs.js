var WebSocket = {
  "OPEN": 0,
  "CLOSED": 1
};
var fakeWSRouter = {
  "addRoute": function(key, callback) {
    return {
      "isOpen": function() { return true; },
      "send": _.identity,
      "close": _.identity
    };
  },
  "onOpen": _.identity,
  "onError": _.identity,
  "onClose": _.identity
};
var Logger = {
  "get": function() {
    return {
      "debug":   print,
      "info":    print,
      "warning": print
    };
  }
};

var schema = { // For unit testing purposes
  "name" : "data",
  "vs" : "0.0.1",
  "schema": {
      "name": "dict",
      "subtype": {
          "name": "any"
      }
  }
}
var Zync = ZyncFactory(fakeWSRouter, [ schema ]);
var doNormalize = Zync.fnsForUnitTests.normalizeJsonOp;

function apply(targetJson, opString) {
  var target = JSON.parse(targetJson);
  var op = JSON.parse(opString);
  var result = Zync.fnsForUnitTests.apply(target, 'JsonOp', op, schema.schema);
  return JSON.stringify(result)
};
function transpose(aString, bString) {
  var a = JSON.parse(aString);
  var b = JSON.parse(bString);
  var result = Zync.fnsForUnitTests.transpose('JsonOp', a, 'JsonOp', b, schema.schema);
  return JSON.stringify([doNormalize(result[1]), doNormalize(result[3])])
};
function compose(aString, bString) {
  var a = JSON.parse(aString);
  var b = JSON.parse(bString);
  var result = Zync.fnsForUnitTests.compose('JsonOp', a, 'JsonOp', b, schema.schema);
  return JSON.stringify(doNormalize(result[1]))
};
function normalize(opString) {
    var op = JSON.parse(opString);
    var result = Zync.fnsForUnitTests.normalizeJsonOp(op);
    return JSON.stringify(result);
}
