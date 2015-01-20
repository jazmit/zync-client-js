var SOFactory,
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; },
  __slice = [].slice;

SOFactory = function(getUser, wsrouter) {
  var Op, Path, SOState, addOpToObject, apply, applyArrayOp, applyJsonOp, clone, commitToString, compose, composeJsonOps, composeSplice, composeSplices, createOp, generateUuid, isChange, isKeep, isModify, isOp, listenerIdGen, log, normalizeJsonOp, opOf, opPostSplit, opSplit, opToString, parseModify, postLen, preLen, routes, spliceOpToString, state, transpose, transposeJsonOp, transposePath, transposeSplice, transposeSpliceOp, updateImage, updateListeners;
  log = Logger.get("so");
  generateUuid = function() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r;
      r = Math.random() * 16 | 0;
      return (c === 'x' ? r : r & 0x3 | 0x8).toString(16);
    });
  };
  clone = function(obj) {
    if (obj == null) {
      throw new Error('Cannot clone undefined');
    } else {
      return JSON.parse(JSON.stringify(obj));
    }
  };
  updateImage = function(ops, target) {
    var op, opType, _i, _len;
    for (_i = 0, _len = ops.length; _i < _len; _i++) {
      op = ops[_i];
      opType = op == null ? void 0 : 'JsonOp';
      target = apply(target, opType, op);
    }
    return target;
  };
  updateListeners = function(commits, target, listeners, isInitialState) {
    var id, listener, op, ops, _i, _len, _ref, _results;
    ops = _.pluck(commits, 'op');
    op = ops.length > 0 ? new Op('JsonOp', _.foldl(ops, composeJsonOps)) : isInitialState ? new Op('Update', target) : void 0;
    _results = [];
    for (_i = 0, _len = listeners.length; _i < _len; _i++) {
      _ref = listeners[_i], id = _ref[0], listener = _ref[1];
      _results.push(listener(target, op));
    }
    return _results;
  };
  createOp = function(opType, op, el, image) {
    var getSuperOp, newArr, rem;
    getSuperOp = function(opType, op, el) {
      var newObj, opIndex;
      newObj = {};
      opIndex = opType === 'JsonOp' ? el : opType + '$$' + el;
      newObj[opIndex] = op;
      return newObj;
    };
    if (_.isNumber(el) && _.isArray(image)) {
      newArr = [];
      if (el > 0) {
        newArr.push(el);
      }
      newArr.push(getSuperOp(opType, op, 'm'));
      rem = image.length - el - 1;
      if (rem > 0) {
        newArr.push(rem);
      }
      return newArr;
    } else if (_.isString(el) && _.isObject(image)) {
      return getSuperOp(opType, op, el);
    } else {
      throw new Error("Illegal path element " + el + " against image " + image);
    }
  };
  addOpToObject = function(target, key, opType, opValue) {
    var prefix;
    prefix = opType === 'JsonOp' ? '' : opType + '$$';
    target[prefix + key] = opValue;
    return target;
  };
  isOp = function(key) {
    return key.indexOf('$$') > 0;
  };
  opOf = function(key) {
    var z;
    z = key.split('$$');
    if (z.length === 2) {
      return z;
    } else {
      return ['JsonOp', key];
    }
  };
  isChange = function(op) {
    return (_.isArray(op.i) || _.isString(op.i)) && _.isNumber(op.d);
  };
  isKeep = function(op) {
    return _.isNumber(op);
  };
  isModify = function(op) {
    var _this = this;
    return _.isObject(op.m) || _.find(_.keys(op), function(key) {
      return key.indexOf("$$") > 0;
    });
  };
  parseModify = function(op) {
    var key;
    key = _.keys(op)[0];
    return [opOf(key)[0], op[key]];
  };
  preLen = function(op) {
    if (_.isNumber(op)) {
      return op;
    } else if (isChange(op)) {
      return op.d;
    } else if (isModify(op)) {
      return 1;
    } else {
      throw new Error("Unknown array op " + (spliceOpToString(op)));
    }
  };
  postLen = function(op) {
    if (_.isNumber(op)) {
      return op;
    } else if (isChange(op)) {
      return op.i.length;
    } else if (isModify(op)) {
      return 1;
    } else {
      throw new Error("Unknown array op " + (spliceOpToString(op)));
    }
  };
  opSplit = function(op, n) {
    if (n > preLen(op)) {
      throw new Error('Illegal split');
    }
    if (_.isNumber(op)) {
      return [n, op - n];
    } else {
      if (isChange(op)) {
        return [
          {
            i: op.i,
            d: n
          }, {
            i: (_.isString(op.i) ? "" : []),
            d: op.d - n
          }
        ];
      } else if (isModify(op)) {
        throw new Error('Cannot split modify operation');
      } else {
        throw new Error('Unknown op');
      }
    }
  };
  opPostSplit = function(op, n) {
    if (n > postLen(op) || n < 1) {
      throw new Error("Illegal split " + n);
    }
    if (_.isNumber(op)) {
      return [n, op - n];
    } else {
      if (isChange(op)) {
        return [
          {
            i: op.i.slice(0, n),
            d: op.d
          }, {
            i: op.i.slice(n),
            d: 0
          }
        ];
      } else if (isModify(op)) {
        throw new Error('Cannot split modify');
      } else {
        throw new Error('Unknown op');
      }
    }
  };
  spliceOpToString = function(spliceOp) {
    var keys, modifyOp, opName, opType, _ref;
    if (_.isNumber(spliceOp)) {
      return spliceOp.toString();
    } else if (_.isObject(spliceOp)) {
      if ((spliceOp.d != null) && (spliceOp.i == null)) {
        return "-" + spliceOp.d;
      } else if ((spliceOp.i != null) && (spliceOp.d == null)) {
        return "+" + (JSON.stringify(spliceOp.i));
      } else if ((spliceOp.i != null) && (spliceOp.d != null)) {
        return "-" + spliceOp.d + "/+" + (JSON.stringify(spliceOp.i));
      } else {
        keys = _.keys(spliceOp);
        modifyOp = keys[0];
        _ref = opOf(keys[0]), opType = _ref[0], opName = _ref[1];
        if (opName !== 'm') {
          throw new Error("Cannot convert " + (JSON.stringify(spliceOp)) + " to string");
        }
        return opToString(opType, spliceOp[keys[0]]);
      }
    } else {
      throw new Error("Cannot convert " + (JSON.stringify(spliceOp)) + " to string");
    }
  };
  opToString = function(opType, op) {
    var k, kvs, subOp, subOpName, subOpType;
    if (opType == null) {
      return 'Id';
    } else {
      switch (opType) {
        case 'Splice':
          return "<" + (_.map(op, spliceOpToString).join(' ')) + ">";
        case 'JsonOp':
          if (!_.isObject(op)) {
            throw new Error("JsonOp " + (JSON.stringify(op)) + " should be object ");
          }
          kvs = (function() {
            var _ref, _results;
            _results = [];
            for (k in op) {
              subOp = op[k];
              _ref = opOf(k), subOpType = _ref[0], subOpName = _ref[1];
              _results.push("" + subOpName + (opToString(subOpType, subOp)));
            }
            return _results;
          })();
          return "{" + (kvs.join(", ")) + "}";
        case 'Update':
          return "=" + (JSON.stringify(op));
        case 'Replace':
          return "==" + (JSON.stringify(op));
        default:
          throw new Error("Cannot convert " + (JSON.stringify(op)) + " to string");
      }
    }
  };
  commitToString = function(commit) {
    return "|" + commit.vs + ": " + (opToString('JsonOp', commit.op)) + "|";
  };
  applyArrayOp = function(opList, spliceTarget) {
    var arrOp, l, n, newSlice, opType, opValue, result, slice, _i, _len, _ref,
      _this = this;
    result = (function() {
      if (_.isString(spliceTarget)) {
        return '';
      } else if (_.isArray(spliceTarget)) {
        return [];
      } else {
        throw new Error("Illegal splice operation " + ("" + (JSON.stringify(opList)) + " in " + (JSON.stringify(spliceTarget))));
      }
    })();
    n = 0;
    for (_i = 0, _len = opList.length; _i < _len; _i++) {
      arrOp = opList[_i];
      l = preLen(arrOp);
      slice = spliceTarget.slice(n, n + l);
      newSlice = _.isNumber(arrOp) ? slice : isChange(arrOp) ? arrOp.i : isModify(arrOp) ? ((_ref = parseModify(arrOp), opType = _ref[0], opValue = _ref[1], _ref), slice.map(function(el) {
        return apply(el, opType, opValue);
      })) : void 0;
      if (_.isString(result)) {
        result += newSlice;
      } else {
        result.push.apply(result, newSlice);
      }
      n += l;
    }
    if (n !== spliceTarget.length) {
      throw new Error("Cannot apply splice of length " + n + " to " + (JSON.stringify(spliceTarget)));
    }
    if (!_.isString(result)) {
      return Object.freeze(result);
    } else {
      return result;
    }
  };
  apply = function(target, opType, opValue) {
    if (opType == null) {
      return target;
    } else {
      switch (opType) {
        case 'Update':
        case 'Replace':
          return opValue;
        case 'Splice':
          return applyArrayOp(opValue, target);
        case 'JsonOp':
          return applyJsonOp(target, opValue);
        default:
          throw new Error("Unknown opType " + opType);
      }
    }
  };
  applyJsonOp = function(target, opObject) {
    var key, opKey, opType, opValue, ops, opsAtDepth, opsHere, result, value, _i, _len, _ref, _ref1, _ref2, _ref3;
    if (!(_.isObject(target) && _.isObject(opObject) && !_.isArray(target) && !_.isArray(opObject))) {
      throw new Error("Undefined op (" + (JSON.stringify(opObject)) + ") or target (" + (JSON.stringify(target)) + ")");
    }
    _ref = _.partition(_.keys(opObject), isOp), opsHere = _ref[0], opsAtDepth = _ref[1];
    ops = {};
    for (_i = 0, _len = opsHere.length; _i < _len; _i++) {
      key = opsHere[_i];
      _ref1 = opOf(key), opType = _ref1[0], opKey = _ref1[1];
      ops[opKey] = [opType, opObject[key]];
    }
    result = _.isArray(target) ? [] : {};
    for (key in target) {
      value = target[key];
      result[key] = key in ops ? ((_ref2 = ops[key], opType = _ref2[0], opValue = _ref2[1], _ref2), apply(value, opType, opValue)) : __indexOf.call(opsAtDepth, key) >= 0 ? applyJsonOp(target[key], opObject[key]) : target[key];
    }
    for (key in ops) {
      _ref3 = ops[key], opType = _ref3[0], opValue = _ref3[1];
      if (!(!(key in target))) {
        continue;
      }
      if (opType !== 'Update' && opType !== 'Replace') {
        throw new Error("Illegal operation " + (JSON.stringify(opType)) + " on " + (JSON.stringify(target)));
      }
      result[key] = opValue;
    }
    for (key in result) {
      value = result[key];
      if (value == null) {
        delete result[key];
      }
    }
    return Object.freeze(result);
  };
  normalizeJsonOp = function(opObject) {
    var key, lastSpliceOp, newObject, newSplice, newValue, normalize2, opType, prop, spliceOp, value, _ref;
    newObject = {};
    for (key in opObject) {
      value = opObject[key];
      _ref = opOf(key), opType = _ref[0], prop = _ref[1];
      newValue = (function() {
        var _i, _len;
        switch (opType) {
          case 'Splice':
            normalize2 = function(a, b) {
              var newI;
              if (isKeep(a) && isKeep(b)) {
                return [a + b];
              } else if (isChange(a) && isChange(b)) {
                newI = (function() {
                  if (_.isString(a.i) && _.isString(b.i)) {
                    return a.i + b.i;
                  } else if (_.isArray(a.i) && _.isArray(b.i)) {
                    return a.i.concat(b.i);
                  } else {
                    throw new Error('Unexpected inserts');
                  }
                })();
                return [
                  {
                    d: a.d + b.d,
                    i: newI
                  }
                ];
              } else {
                return [a, b];
              }
            };
            newSplice = [];
            for (_i = 0, _len = value.length; _i < _len; _i++) {
              spliceOp = value[_i];
              if (isModify(spliceOp)) {
                spliceOp = normalizeJsonOp(spliceOp);
                if (spliceOp == null) {
                  spliceOp = 1;
                }
              }
              if (postLen(spliceOp) === 0 && preLen(spliceOp) === 0) {
                continue;
              }
              if (newSplice.length === 0) {
                newSplice.push(spliceOp);
              } else {
                lastSpliceOp = newSplice.pop();
                newSplice.push.apply(newSplice, normalize2(lastSpliceOp, spliceOp));
              }
            }
            if (newSplice.length === 0 || newSplice.length === 1 && isKeep(newSplice[0])) {
              return null;
            } else {
              return newSplice;
            }
            break;
          case 'JsonOp':
            return normalizeJsonOp(value);
          default:
            return value;
        }
      })();
      if ((opType === 'Update' || opType === 'Replace') || (newValue != null)) {
        newObject[key] = newValue;
      }
    }
    if (_.keys(newObject).length === 0) {
      return null;
    } else {
      return Object.freeze(newObject);
    }
  };
  transposeSpliceOp = function(a, b) {
    var aOp, aType, bOp, bType, newA, newB, resA, resAType, resB, resBType, _ref, _ref1, _ref2;
    if (preLen(a) !== preLen(b)) {
      throw new Error("Illegal op splice transpose " + (spliceOpToString(a)) + " and " + (spliceOpToString(b)));
    }
    if (isKeep(a)) {
      return [postLen(b), b];
    } else if (isKeep(b)) {
      return [a, postLen(a)];
    } else if (isChange(a)) {
      return [
        {
          i: a.i,
          d: postLen(b)
        }, postLen(a)
      ];
    } else if (isChange(b)) {
      return [
        postLen(b), {
          i: b.i,
          d: postLen(a)
        }
      ];
    } else if (isModify(a) && isModify(b)) {
      _ref = parseModify(a), aType = _ref[0], aOp = _ref[1];
      _ref1 = parseModify(b), bType = _ref1[0], bOp = _ref1[1];
      _ref2 = transpose(aType, aOp, bType, bOp), resAType = _ref2[0], resA = _ref2[1], resBType = _ref2[2], resB = _ref2[3];
      newA = resA != null ? addOpToObject({}, 'm', resAType, resA) : 1;
      newB = resB != null ? addOpToObject({}, 'm', resBType, resB) : 1;
      return [newA, newB];
    } else {
      throw new Error("Cannot transpose " + (spliceOpToString(a)) + " and " + (spliceOpToString(b)));
    }
  };
  transposeSplice = function(a, b) {
    var NO_MORE_ELEMENTS, aOps, bOps, la, lb, newA, newB, nextA, nextB, rem, resA, resAs, resB, resBs, splitA, splitB, _ref, _ref1, _ref2, _ref3, _ref4, _ref5, _ref6;
    NO_MORE_ELEMENTS = {};
    _ref = [[], []], resAs = _ref[0], resBs = _ref[1];
    _ref1 = [clone(a).reverse(), clone(b).reverse()], aOps = _ref1[0], bOps = _ref1[1];
    while (aOps.length > 0 || bOps.length > 0) {
      nextA = aOps.length > 0 ? aOps.pop() : NO_MORE_ELEMENTS;
      nextB = bOps.length > 0 ? bOps.pop() : NO_MORE_ELEMENTS;
      if (!((nextA != null) && (nextB != null))) {
        throw new Error("Encountered null while transposing " + (opToString('Splice', a)) + " and " + (opToString('Splice', b)));
      }
      if (nextA === NO_MORE_ELEMENTS) {
        if (preLen(nextB) > 0) {
          throw new Error("Second operand of splice transpose " + (opToString('Splice', a)) + ", " + (opToString(bType, b)) + " too long");
        }
        resBs.push(nextB);
        resAs.push(postLen(nextB));
        continue;
      }
      if (nextB === NO_MORE_ELEMENTS) {
        if (preLen(nextA) > 0) {
          throw new Error("First operand of splice transpose " + (opToString('Splice', a)) + ", " + (opToString('Splice', b)) + " too long");
        }
        resAs.push(nextA);
        resBs.push(postLen(nextA));
        continue;
      }
      _ref2 = [preLen(nextA), preLen(nextB)], la = _ref2[0], lb = _ref2[1];
      _ref5 = lb === 0 ? (aOps.push(nextA), [0, nextB]) : la === 0 ? (bOps.push(nextB), [nextA, 0]) : la === lb ? [nextA, nextB] : la > lb ? ((_ref3 = opSplit(nextA, lb), newA = _ref3[0], rem = _ref3[1], _ref3), aOps.push(rem), [newA, nextB]) : lb > la ? ((_ref4 = opSplit(nextB, la), newB = _ref4[0], rem = _ref4[1], _ref4), bOps.push(rem), [nextA, newB]) : void 0, splitA = _ref5[0], splitB = _ref5[1];
      if (isChange(splitA) && isChange(splitB)) {
        if (postLen(splitB) > 0) {
          resAs.push(postLen(splitB));
        }
        if (postLen(splitA) > 0) {
          resAs.push({
            i: splitA.i,
            d: 0
          });
        }
        if (postLen(splitB) > 0) {
          resBs.push({
            i: splitB.i,
            d: 0
          });
        }
        if (postLen(splitA) > 0) {
          resBs.push(postLen(splitA));
        }
      } else {
        _ref6 = transposeSpliceOp(splitA, splitB), resA = _ref6[0], resB = _ref6[1];
        if ((resA == null) || (resB == null)) {
          throw new Error("Produced null result (" + (JSON.stringify(resA)) + ", " + (JSON.stringify(resB)) + ") transposing " + (JSON.stringify(splitA)) + ", " + (JSON.stringify(splitB)));
        }
        if (resA !== 0) {
          resAs.push(resA);
        }
        if (resB !== 0) {
          resBs.push(resB);
        }
      }
    }
    return [resAs, resBs];
  };
  transpose = function(aType, a, bType, b) {
    var jsA, jsB, splA, splB, _ref, _ref1;
    if (!((aType != null) && (bType != null))) {
      throw 'No type in transpose';
    }
    if (bType === 'Replace' || bType === 'Update') {
      return [void 0, void 0, bType, b];
    } else if (aType === 'Replace' || aType === 'Update') {
      return [aType, a, void 0, void 0];
    } else if (aType === 'Splice' && bType === 'Splice') {
      _ref = transposeSplice(a, b), splA = _ref[0], splB = _ref[1];
      return ['Splice', splA, 'Splice', splB];
    } else if ((aType === 'JsonOp') && (bType === 'JsonOp')) {
      _ref1 = transposeJsonOp(a, b), jsA = _ref1[0], jsB = _ref1[1];
      return ['JsonOp', jsA, 'JsonOp', jsB];
    } else {
      throw new Error("Unknown op types " + aType + ", " + bType);
    }
  };
  transposeJsonOp = function(a, b) {
    var an, bn, dictA, dictB, fullKeyA, fullKeyB, key, newA, newAType, newAn, newB, newBType, newBn, opKey, opType, opTypeA, opTypeB, value, _i, _len, _ref, _ref1, _ref2, _ref3, _ref4, _ref5, _ref6, _ref7;
    newA = {};
    newB = {};
    dictA = {};
    dictB = {};
    for (key in a) {
      value = a[key];
      _ref = opOf(key), opType = _ref[0], opKey = _ref[1];
      dictA[opKey] = [key, opType, a[key]];
    }
    for (key in b) {
      value = b[key];
      _ref1 = opOf(key), opType = _ref1[0], opKey = _ref1[1];
      dictB[opKey] = [key, opType, b[key]];
    }
    _ref2 = _.union(_.keys(dictA), _.keys(dictB));
    for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
      key = _ref2[_i];
      _ref4 = (_ref3 = dictA[key]) != null ? _ref3 : [key, void 0, void 0], fullKeyA = _ref4[0], opTypeA = _ref4[1], an = _ref4[2];
      _ref6 = (_ref5 = dictB[key]) != null ? _ref5 : [key, void 0, void 0], fullKeyB = _ref6[0], opTypeB = _ref6[1], bn = _ref6[2];
      _ref7 = (opTypeA == null) || (opTypeB == null) ? [opTypeA, an, opTypeB, bn] : transpose(opTypeA, an, opTypeB, bn), newAType = _ref7[0], newAn = _ref7[1], newBType = _ref7[2], newBn = _ref7[3];
      if (newAn != null) {
        addOpToObject(newA, key, newAType, newAn);
      }
      if (newBn != null) {
        addOpToObject(newB, key, newBType, newBn);
      }
    }
    return [newA, newB];
  };
  transposePath = function(a, path) {
    var dKeep, dShift, el, keep, key, newPath, newTail, op, opType, opsHere, pathHead, pathIndex, pathTail, shift, spliceOp, _i, _len, _ref,
      _this = this;
    if ((path == null) || path.length === 0) {
      return path;
    }
    pathHead = _.head(path);
    pathTail = _.tail(path);
    if (a[pathHead] != null) {
      return [pathHead].concat(transposePath(a[pathHead], pathTail));
    } else {
      if (pathTail.length === 0) {
        return path;
      }
      opsHere = _.keys(a).filter(function(key) {
        return key.indexOf('$$' + pathHead) > 0;
      });
      if (opsHere.length === 0) {
        return path;
      }
      if (opsHere.length > 1) {
        throw new Error('Two operations at the same point');
      }
      key = opsHere[0];
      _ref = key.split('$$'), opType = _ref[0], el = _ref[1];
      if (opType === 'Update' || opType === 'Replace') {
        throw new Error('Invalidated this path');
      } else if (opType === 'Splice') {
        pathIndex = _.head(pathTail);
        if (!_.isNumber(pathIndex)) {
          throw new Error("Can't transpose '" + pathHead + "' with splice of '" + el + "'");
        }
        op = a[key];
        shift = 0;
        keep = 0;
        newTail = _.tail(pathTail);
        for (_i = 0, _len = op.length; _i < _len; _i++) {
          spliceOp = op[_i];
          dKeep = preLen(spliceOp);
          dShift = postLen(spliceOp) - dKeep;
          if (keep + dKeep > pathIndex) {
            if (spliceOp.d != null) {
              throw new Error('Invalidated this path');
            } else if (preLen(spliceOp) === 1) {
              newPath = _.tail(transposePath(spliceOp, ['m'].concat(newTail)));
            }
            break;
          }
          keep += dKeep;
          shift += dShift;
        }
        pathIndex += shift;
        return [pathHead, pathIndex].concat(newTail);
      } else {
        throw new Error('Unknown op type');
      }
    }
  };
  composeSplice = function(a, b) {
    var newOp, newOpType, opA, opB, opTypeA, opTypeB, _ref, _ref1, _ref2;
    if (!(postLen(b) === preLen(a) && postLen(b) > 0)) {
      throw "Illegal compose of splices " + (spliceOpToString(a)) + " and " + (spliceOpToString(b));
    }
    if (isKeep(a)) {
      return b;
    } else if (isKeep(b)) {
      return a;
    } else if (isChange(a)) {
      return {
        d: preLen(b),
        i: a.i
      };
    } else if (isChange(b)) {
      return {
        d: b.d,
        i: applyArrayOp([a], b.i)
      };
    } else if (isModify(a) && isModify(b)) {
      _ref = parseModify(a), opTypeA = _ref[0], opA = _ref[1];
      _ref1 = parseModify(b), opTypeB = _ref1[0], opB = _ref1[1];
      _ref2 = compose(opTypeA, opA, opTypeB, opB), newOpType = _ref2[0], newOp = _ref2[1];
      return addOpToObject({}, 'm', newOpType, newOp);
    } else {
      throw new Error("Cannot compose " + (JSON.stringify(a)) + " and " + (JSON.stringify(b)));
    }
  };
  composeSplices = function(a, b) {
    var a0, a1, b0, b1, la, lb, remA, remB, _ref, _ref1;
    if (a.length === 0 && b.length === 0) {
      return [];
    }
    a0 = _.head(a);
    if ((a0 != null) && preLen(a0) === 0) {
      return [a0].concat(composeSplices(_.tail(a), b));
    }
    b0 = _.head(b);
    if ((b0 != null) && postLen(b0) === 0) {
      return [b0].concat(composeSplices(a, _.tail(b)));
    }
    if (b.length === 0 && a.length > 0 || a.length === 0 && b.length > 0) {
      throw new Error("Composed slices of unequal length " + (JSON.stringify(a)) + " and " + (JSON.stringify(b)));
    }
    la = preLen(a0);
    lb = postLen(b0);
    remA = _.tail(a);
    remB = _.tail(b);
    if (la > lb) {
      _ref = opSplit(a0, lb), a0 = _ref[0], a1 = _ref[1];
      return [composeSplice(a0, b0)].concat(composeSplices([a1].concat(remA), remB));
    } else if (lb > la) {
      _ref1 = opPostSplit(b0, la), b0 = _ref1[0], b1 = _ref1[1];
      return [composeSplice(a0, b0)].concat(composeSplices(remA, [b1].concat(remB)));
    } else {
      return [composeSplice(a0, b0)].concat(composeSplices(remA, remB));
    }
  };
  compose = function(aType, a, bType, b) {
    if (aType === 'Update' || aType === 'Replace') {
      return [aType, a];
    } else if (a === void 0) {
      return [bType, b];
    } else if (b === void 0) {
      return [aType, a];
    } else if (bType === 'Update' || bType === 'Replace') {
      return [bType, apply(b, aType, a)];
    } else if (aType === 'JsonOp' && bType === 'JsonOp') {
      return ['JsonOp', composeJsonOps(a, b)];
    } else if (aType === 'Splice' && bType === 'Splice') {
      return ['Splice', composeSplices(a, b)];
    } else {
      throw new Error("Illegal composition of " + aType + " and " + bType);
    }
  };
  composeJsonOps = function(a, b) {
    var a_, b_, dictA, dictB, key, keys, newOpType, newOpValue, opKey, opType, opTypeA, opTypeB, result, value, _i, _len, _ref, _ref1, _ref2, _ref3, _ref4, _ref5, _ref6;
    result = {};
    dictA = {};
    dictB = {};
    for (key in a) {
      value = a[key];
      _ref = opOf(key), opType = _ref[0], opKey = _ref[1];
      dictA[opKey] = [opType, a[key]];
    }
    for (key in b) {
      value = b[key];
      _ref1 = opOf(key), opType = _ref1[0], opKey = _ref1[1];
      dictB[opKey] = [opType, b[key]];
    }
    keys = _.union(_.keys(dictA), _.keys(dictB));
    result = {};
    for (_i = 0, _len = keys.length; _i < _len; _i++) {
      key = keys[_i];
      _ref3 = (_ref2 = dictA[key]) != null ? _ref2 : [key, void 0, void 0], opTypeA = _ref3[0], a_ = _ref3[1];
      _ref5 = (_ref4 = dictB[key]) != null ? _ref4 : [key, void 0, void 0], opTypeB = _ref5[0], b_ = _ref5[1];
      if ((a_ != null) && (b_ != null)) {
        _ref6 = compose(opTypeA, a_, opTypeB, b_), newOpType = _ref6[0], newOpValue = _ref6[1];
        addOpToObject(result, key, newOpType, newOpValue);
      } else if (a_ != null) {
        addOpToObject(result, key, opTypeA, a_);
      } else if (b_ != null) {
        addOpToObject(result, key, opTypeB, b_);
      }
    }
    return result;
  };
  state = {};
  routes = {};
  SOState = function(domain, uuid) {
    var _this = this;
    this.domain = domain;
    this.uuid = uuid;
    this.unappliedOps = [];
    this.localHistory = [];
    this.historyStart = 0;
    this.localImage = {};
    this.sentToServer = 0;
    this.serverHistory = [];
    this.serverImage = this.localImage;
    this.listeners = [];
    this.requestState = function() {
      if (routes[_this.domain] == null) {
        routes[_this.domain] = wsrouter.addRoute(_this.domain, function() {});
      }
      return routes[_this.domain].send(uuid);
    };
    this.commitRoute = wsrouter.addRoute(this.uuid, function(msg) {
      var commits, deepFreeze, e, newServerCommits, newServerHistoryLength, oldServerHistoryLength, result, transformedCommits;
      result = void 0;
      deepFreeze = function(obj) {
        var key, val;
        for (key in obj) {
          val = obj[key];
          if (obj.hasOwnProperty(key) && _.isObject(val)) {
            deepFreeze(val);
          }
        }
        return Object.freeze(obj);
      };
      try {
        result = deepFreeze(JSON.parse(msg));
      } catch (_error) {
        e = _error;
        log.error("Error from server: " + msg);
        return;
      }
      if (result.image != null) {
        log.debug("Received image " + (JSON.stringify(result)) + " for " + _this.uuid);
        oldServerHistoryLength = _this.historyStart + _this.serverHistory.length;
        newServerHistoryLength = result.history.length + result.historyStart;
        if (oldServerHistoryLength > newServerHistoryLength) {
          throw new Error('Fatal: server sent shorter history than already confirmed');
        }
        if (result.historyStart > oldServerHistoryLength) {
          log.warn("Dropped all local history because server history is too short");
          _this.localHistory = [];
          _this.serverHistory = [];
          _this.historyStart = result.historyStart;
          _this.unappliedOps = [];
          _this.sentToServer = 0;
          _this.serverImage = _this.localImage = result.image;
          commits = result.history.reverse();
          transformedCommits = _this.receiveFromServer.apply(_this, commits);
          updateListeners(transformedCommits, _this.localImage, _this.listeners, true);
        } else {
          newServerCommits = _.drop(result.history, oldServerHistoryLength - result.historyStart);
          log.debug("Adding " + newServerCommits.length + " server commits from server image");
          transformedCommits = _this.receiveFromServer.apply(_this, newServerCommits);
          _this.sentToServer = 0;
          updateListeners(transformedCommits, _this.localImage, _this.listeners, true);
        }
      } else {
        commits = _.isArray(result) ? result.reverse() : [result];
        transformedCommits = _this.receiveFromServer.apply(_this, commits);
      }
      log.debug("Server updated " + _this.uuid + " to " + (JSON.stringify(_this.serverImage)));
      return _this.trySendingNextCommit();
    });
    wsrouter.onOpen(function() {
      return _this.requestState();
    });
    wsrouter.onError(function() {
      return _this.sentToServer = 0;
    });
    return this;
  };
  SOState.prototype.trySendingNextCommit = function() {
    var commit;
    if (this.sentToServer === 0 && this.localHistory.length > 0 && this.commitRoute.isOpen()) {
      commit = _.head(this.localHistory);
      log.debug("Sending commit " + (commitToString(commit)) + " to server");
      this.commitRoute.send(JSON.stringify(commit));
      return this.sentToServer += 1;
    }
  };
  SOState.prototype.commit = function() {
    var commit, composedOp, now, op, opToTranspose, ops, transposedOps, userId, vs, _i, _j, _len, _len1;
    ops = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    ops = this.unappliedOps.concat(ops);
    if (ops.length === 0) {
      return;
    }
    this.unappliedOps = [];
    transposedOps = [];
    for (_i = 0, _len = ops.length; _i < _len; _i++) {
      opToTranspose = ops[_i];
      for (_j = 0, _len1 = transposedOps.length; _j < _len1; _j++) {
        op = transposedOps[_j];
        opToTranspose = transposeJsonOp(opToTranspose, op)[0];
      }
      transposedOps.push(opToTranspose);
    }
    composedOp = normalizeJsonOp(_.foldl(transposedOps, (function(b, a) {
      return composeJsonOps(a, b);
    })));
    log.debug("Committing " + (opToString((op != null ? 'JsonOp' : void 0), composedOp)) + " to " + this.uuid);
    userId = getUser();
    if (userId == null) {
      throw new Error('Attempt to commit operation without active user');
    }
    now = Date.now();
    vs = this.vs();
    commit = {
      uuid: this.uuid,
      vs: vs,
      op: composedOp,
      author: userId,
      created: now
    };
    this.localImage = updateImage([composedOp], this.localImage);
    updateListeners([commit], this.localImage, this.listeners, false);
    this.localHistory.push(commit);
    return this.trySendingNextCommit();
  };
  listenerIdGen = 0;
  SOState.prototype.onChange = function(fn) {
    var id;
    id = listenerIdGen++;
    return this.listeners.push([id, fn]);
  };
  SOState.prototype.unsubscribe = function(listenerId) {
    return this.listeners = this.listeners.filter(function(_arg) {
      var fn, id;
      id = _arg[0], fn = _arg[1];
      return listenerId !== id;
    });
  };
  SOState.prototype.receiveFromServer = function() {
    var commit, commits, localCommit, newLocalCommit, newLocalHistory, newLocalOp, op, ops, transformedCommit, transformedCommits, _i, _j, _len, _len1, _ref, _ref1;
    commits = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    ops = _.pluck(commits, 'op');
    transformedCommits = [];
    for (_i = 0, _len = commits.length; _i < _len; _i++) {
      commit = commits[_i];
      if (commit.vs !== this.serverHistory.length + this.historyStart) {
        throw new Error("Received illegal commit from server " + (JSON.stringify(commit)) + ", history length " + (this.serverHistory.length + this.historyStart));
      }
      op = commit.op;
      this.serverHistory.push(commit);
      this.serverImage = updateImage([op], this.serverImage);
      if (this.sentToServer > 0 && _.isEqual(op, this.localHistory[0].op)) {
        log.debug("Received confirmation of commit " + (commitToString(commit)) + " from server");
        this.sentToServer -= 1;
        this.localHistory.shift();
      } else {
        log.debug("Processing new commit " + (commitToString(commit)) + " from server");
        newLocalHistory = [];
        _ref = this.localHistory;
        for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
          localCommit = _ref[_j];
          newLocalCommit = clone(localCommit);
          newLocalCommit.vs += 1;
          _ref1 = transposeJsonOp(localCommit.op, op), newLocalOp = _ref1[0], op = _ref1[1];
          newLocalCommit.op = normalizeJsonOp(newLocalOp);
          newLocalHistory.push(newLocalCommit);
        }
        this.localHistory = newLocalHistory;
        this.localImage = updateImage(_.pluck(this.localHistory, 'op'), this.serverImage);
        transformedCommit = clone(commit);
        transformedCommit.op = op;
        transformedCommits.push(transformedCommit);
      }
    }
    if (transformedCommits.length > 0) {
      updateListeners(transformedCommits, this.localImage, this.listeners, false);
    }
    return transformedCommits;
  };
  SOState.prototype.vs = function() {
    return this.localHistory.length + this.serverHistory.length + this.historyStart;
  };
  SOState.prototype.updatesSince = function(oldVs) {
    var n;
    if (oldVs < this.historyStart) {
      throw new Error('Attempt to get updates from before history started');
    }
    n = this.vs() - oldVs;
    if (n > this.localHistory.length) {
      return _.drop(this.serverHistory, oldVs).concat(this.localHistory);
    } else {
      return _.drop(this.localHistory, this.localHistory.length - n);
    }
  };
  Path = (function() {
    function Path(soState, path) {
      var stateListenerId, validate, vs,
        _this = this;
      this.path = path;
      if (_.isString(this.path)) {
        this.path = this.path.split('.');
      }
      if (!_.isArray(this.path)) {
        throw new Error("Path must be a string or array, found " + path);
      }
      this.listeners = [];
      vs = soState.vs();
      validate = function() {
        var e, newVs, update, updates, _i, _len;
        newVs = soState.vs();
        if (newVs > vs && vs >= soState.historyStart) {
          updates = _.pluck(soState.updatesSince(vs), 'op');
          try {
            for (_i = 0, _len = updates.length; _i < _len; _i++) {
              update = updates[_i];
              _this.path = transposePath(update, _this.path);
            }
            return vs = newVs;
          } catch (_error) {
            e = _error;
            if (e.message === 'Invalidated this path') {
              return _this.path = void 0;
            } else {
              throw e;
            }
          }
        }
      };
      this.image = function() {
        var el, image, _i, _len, _ref;
        validate();
        if (this.path == null) {
          throw new Error('Path invalidated by other operations');
        }
        image = soState.localImage;
        _ref = this.path;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          el = _ref[_i];
          if (image == null) {
            throw new Error("Couldn't find " + this.path + " in " + (JSON.stringify(soState.localImage)));
          }
          image = image[el];
        }
        return image;
      };
      this.isValid = function() {
        validate();
        return this.path != null;
      };
      listenerIdGen = 0;
      stateListenerId = void 0;
      this.onChange = function(callback) {
        var id,
          _this = this;
        if (this.listeners.length === 0) {
          stateListenerId = soState.onChange(function(newImage, op) {
            var id, image, pathEl, result, toRemove, _i, _j, _len, _len1, _ref, _ref1, _ref2;
            _ref = _this.path;
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              pathEl = _ref[_i];
              op = op.at(pathEl);
              if (op == null) {
                return;
              }
            }
            image = _this.image();
            toRemove = [];
            _ref1 = _this.listeners;
            for (_j = 0, _len1 = _ref1.length; _j < _len1; _j++) {
              _ref2 = _ref1[_j], id = _ref2[0], callback = _ref2[1];
              if (op != null) {
                result = callback(image, op);
                if (result === 'unregister') {
                  toRemove.push(callback);
                }
              }
            }
            return _this.listeners = _.difference(_this.listeners, toRemove);
          });
        }
        id = listenerIdGen++;
        this.listeners.push([id, callback]);
        return id;
      };
      this.unsubscribe = function(idToUnsubscribe) {
        this.listeners = this.listeners.filter(function(_arg) {
          var callback, id;
          id = _arg[0], callback = _arg[1];
          return id !== idToUnsubscribe;
        });
        if (this.listeners.length === 0 && (stateListenerId != null)) {
          soState.unsubscribe(stateListenerId);
        }
        return this;
      };
      this.createOp = function(opType, op) {
        var el, image, newOp, pathWithImage;
        image = soState.localImage;
        pathWithImage = (function() {
          var _i, _len, _ref, _results;
          _ref = _.initial(this.path);
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            el = _ref[_i];
            _results.push(image = image[el]);
          }
          return _results;
        }).call(this);
        el = _.last(this.path);
        newOp = createOp(opType, op, el, image);
        this.addRawOp(newOp);
        return this;
      };
      this.addRawOp = function(op) {
        var el, image, opType, pathWithImage, result, _i, _len, _ref, _ref1;
        image = soState.localImage;
        pathWithImage = (function() {
          var _i, _len, _ref, _results;
          _ref = this.path;
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            el = _ref[_i];
            result = [el, image];
            image = image[el];
            _results.push(result);
          }
          return _results;
        }).call(this);
        _ref = _.initial(pathWithImage).reverse();
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          _ref1 = _ref[_i], el = _ref1[0], image = _ref1[1];
          opType = _.isArray(op) ? 'Splice' : _.isObject(op) ? 'JsonOp' : 'Unknown recursive op type #{op}';
          op = createOp(opType, op, el, image);
        }
        soState.unappliedOps.push(op);
        return this;
      };
      this.commit = function() {
        soState.commit();
        return this;
      };
      this.at = function() {
        var subpath;
        subpath = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
        return new Path(soState, this.path.concat(subpath));
      };
      this.uuid = soState.uuid;
      this.vs = function() {
        return soState.vs();
      };
    }

    Path.prototype.commitRawOp = function(op) {
      this.addRawOp(op);
      return this.commit();
    };

    Path.prototype.update = function() {
      var x;
      x = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      return this.setOp('Update').apply(null, x);
    };

    Path.prototype.replace = function() {
      var x;
      x = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      return this.setOp('Replace').apply(null, x);
    };

    Path.prototype.setOp = function(opType) {
      var _this = this;
      return function(value) {
        return _this.createOp(opType, value);
      };
    };

    Path.prototype.append = function(value) {
      var image, _ref;
      image = (_ref = this.image()) != null ? _ref : [];
      return this.insert(image.length, value);
    };

    Path.prototype.insert = function(index, value) {
      return this.splice(index, 0, value);
    };

    Path.prototype["delete"] = function(index, nDelete) {
      return this.splice(index, nDelete, _.isArray(this.image()) ? [] : '');
    };

    Path.prototype.splice = function(index, nDelete, value) {
      var l, obj, spliceOp;
      obj = this.image();
      if (!((obj != null) && _.isNumber(index) && (0 <= index && index <= obj.length - nDelete))) {
        throw new Error("Invalid splice at " + index + ", length " + nDelete + ", path " + this.path + ", on array " + (JSON.stringify(obj)));
      }
      if ((_.isString(obj) && !_.isString(value)) || (_.isArray(obj) && !_.isArray(value))) {
        throw new Error("Attempt to illegally insert " + value + " at " + this.path + " into " + (JSON.stringify(obj)));
      }
      spliceOp = [];
      if (index > 0) {
        spliceOp.push(index);
      }
      spliceOp.push({
        d: nDelete,
        i: value
      });
      l = value.length;
      if (index + nDelete < obj.length) {
        spliceOp.push(obj.length - index - nDelete);
      }
      return this.createOp('Splice', spliceOp);
    };

    Path.prototype.bindToScope = function(scope, name) {
      var applyChanges, safeApply;
      safeApply = function(fn) {
        if (scope.$$phase || scope.$root.$$phase) {
          return fn();
        } else {
          return scope.$apply(fn);
        }
      };
      applyChanges = function(image) {
        return safeApply(function() {
          if (image != null) {
            return scope[name] = clone(image);
          }
        });
      };
      applyChanges(this.image());
      return this.onChange(applyChanges);
    };

    return Path;

  })();
  Op = (function() {
    function Op(opType, op) {
      var spliceOp, _i, _len, _ref, _ref1;
      this.opType = opType;
      this.op = op;
      this.isNull = false;
      if ((_ref = this.opType) === 'Update' || _ref === 'Replace') {
        this.value = this.op;
      } else if ((this.opType == null) || (this.op == null)) {
        this.isNull = true;
      } else if (this.opType === 'JsonOp') {
        if (!_.isObject(this.op)) {
          throw new Error('Illegal JsonOp');
        }
      } else if (this.opType === 'Splice') {
        if (!_.isArray(this.op)) {
          throw new Error('Illegal Splice');
        }
        this.preLenSum = 0;
        this.postLenSum = 0;
        _ref1 = op != null ? op : [];
        for (_i = 0, _len = _ref1.length; _i < _len; _i++) {
          spliceOp = _ref1[_i];
          this.preLenSum += preLen(spliceOp);
          this.postLenSum += postLen(spliceOp);
        }
      } else {
        throw new Error('Illegal Op');
      }
    }

    Op.prototype.keys = function() {
      if (this.opType === 'JsonOp') {
        return _.map(_.keys(this.op), function(key) {
          return opOf(key)[1];
        });
      } else if (this.opType === 'Update' || this.opType === 'Replace') {
        return _.keys(this.op);
      } else {
        throw new Error('can only get keys for JsonOp');
      }
    };

    Op.prototype.at = function(prop) {
      var innerOp, key, keys, opType, _ref;
      if (this.opType === 'JsonOp' && _.isString(prop)) {
        keys = _.filter(_.keys(this.op), function(key) {
          return opOf(key)[1] === prop;
        });
        if (keys.length === 0) {
          return void 0;
        } else {
          key = keys[0];
          innerOp = this.op[key];
          opType = opOf(key)[0];
          return new Op(opType, innerOp);
        }
      } else if (((_ref = this.opType) === 'Update' || _ref === 'Replace') && _.isString(prop)) {
        if ((this.op != null) && (this.op[prop] != null)) {
          return new Op(this.opType, this.op[prop]);
        } else {
          return void 0;
        }
      } else {
        throw new Error('Illegal call to at');
      }
    };

    Op.prototype.dl = function() {
      if (!_.isArray(this.op)) {
        throw new Error('dl only valid for array ops');
      }
      return this.postLenSum - this.preLenSum;
    };

    Op.prototype.updatedRange = function() {
      var a0, a1, getOr0;
      if (this.opType !== 'Splice') {
        throw new Error('range only valid for array ops');
      }
      getOr0 = function(x) {
        if (_.isNumber(x)) {
          return x;
        } else {
          return 0;
        }
      };
      a0 = getOr0(_.head(this.op));
      a1 = getOr0(_.last(this.op));
      return [a0, this.preLenSum - a1];
    };

    Op.prototype.isNull = function() {
      return this.op == null;
    };

    Op.prototype.isReplace = function() {
      return this.opType === 'Update' || this.opType === 'Replace';
    };

    Op.prototype.toString = function() {
      return opToString(this.opType, this.op);
    };

    return Op;

  })();
  return {
    create: function(domain) {
      if (domain == null) {
        domain = 'data';
      }
      return this.fetch(domain, generateUuid());
    },
    fetch: function(domain, uuid) {
      log.info("Fetching shared object " + domain + ": " + uuid);
      if (state[uuid] == null) {
        state[uuid] = new SOState(domain, uuid);
      }
      return new Path(state[uuid], []);
    },
    stateOf: function(uuid) {
      return clone(state[uuid]);
    },
    fnsForUnitTests: {
      normalizeJsonOp: normalizeJsonOp,
      transpose: transpose,
      compose: compose,
      apply: apply
    }
  };
};
;
//# sourceMappingURL=zync.js.map