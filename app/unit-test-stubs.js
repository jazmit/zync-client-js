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
  "onError": _.identity
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

var SO = SOFactory(function() { return 1; }, fakeWSRouter);
var doNormalize = SO.fnsForUnitTests.normalizeJsonOp;

function apply(targetJson, opString) {
  var target = JSON.parse(targetJson);
  var op = JSON.parse(opString);
  var result = SO.fnsForUnitTests.apply(target, 'JsonOp', op);
  return JSON.stringify(result)
};
function transpose(aString, bString) {
  var a = JSON.parse(aString);
  var b = JSON.parse(bString);
  var result = SO.fnsForUnitTests.transpose('JsonOp', a, 'JsonOp', b);
  return JSON.stringify([doNormalize(result[1]), doNormalize(result[3])])
};
function compose(aString, bString) {
  var a = JSON.parse(aString);
  var b = JSON.parse(bString);
  var result = SO.fnsForUnitTests.compose('JsonOp', a, 'JsonOp', b);
  return JSON.stringify(doNormalize(result[1]))
};
function normalize(opString) {
    var op = JSON.parse(opString);
    var result = SO.fnsForUnitTests.normalizeJsonOp(op);
    return JSON.stringify(result);
}
