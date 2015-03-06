
# ************** SharedObject *****************
#
# Represents an object which is synchronized across clients via a server
# objects can be mutated while offline, then synced later
#
# Syntax:
#
# Create a new object, with a new uuid:
# so = SharedObject.create('domain here')
#
# .. or fetch an existing object from the server
# so = SharedObject.fetch(uuid)
#
# A plain immutable javascript object representation is available at
# so.image()
#
# Set values on the object:
# so.at('prop1').update('value1')
#
# OR
#
# so.addRawOp
#   prop1: value1
#
# Operations on arrays and strings can be called as follows:
# so.at('array_prop').insert index, ['new', 'items', 'for', 'array']
# so.at('string_prp').insert index, 'string to insert'
# so.at('prop').delete index, nToDelete
# so.at('prop').splice index, nToDelete, ['new', 'items']
#
# Operations can be chained, and should be committed when complete
# so.at('prop').delete(0, 1)
#              .delete(4, 1)
#              .insert(3, 'Hello')
#              .commit()
#
# To be notified of changes (whether local or from the server)
#
# so.onChange (newImage, updateOperationsArray) ->
#   .. process the new sharedobject here
#
# To 'unlisten', call
#
# so.unListen(method)
#
# Shared objects are immutable.
#
# To return a sub-shared object, use 'at'
# subobject  = so.at('a.b.c.d')
# subobject2 = so.at('a', 'b', 'c').at('d')
#
#
SOFactory = (getUser, wsrouter) ->

    log = Logger.get("so")

    generateUuid = ->
        # Adapted from http://stackoverflow.com/a/2117523/469981
        'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace /[xy]/g, (c) ->
            r = Math.random()*16|0
            (if c == 'x' then r else (r&0x3|0x8)).toString(16)

    clone = (obj) ->
        if !obj?
            throw new Error 'Cannot clone undefined'
        else
            JSON.parse(JSON.stringify obj)

    # Updates the given image and notifies listeners
    updateImage = (ops, target) ->
        for op in ops
            opType = if !op? then undefined else 'JsonOp'
            target = apply(target, opType, op)
        target

    updateListeners = (commits, target, listeners, isInitialState) ->
        ops = _.pluck(commits, 'op')
        op = if ops.length > 0
                 new Op('JsonOp', _.foldl(ops, composeJsonOps))
             else if isInitialState
                 new Op('Update', target)
             else
                 undefined
        listener(target, op) for [id, listener] in listeners

    # Defines the serialization format for operations
    createOp = (opType, op, el, image) ->
        getSuperOp = (opType, op, el) ->
            newObj = {}
            opIndex = if opType == 'JsonOp' then el else opType + '$$' + el
            newObj[opIndex] = op
            newObj
        if _.isNumber(el) and _.isArray(image)
            newArr = []
            if el > 0 then newArr.push el
            newArr.push getSuperOp(opType, op, 'm')
            rem = image.length - el - 1
            if rem > 0 then newArr.push rem
            newArr
        else if _.isString(el) and _.isObject(image)
            getSuperOp(opType, op, el)
        else
            throw new Error "Illegal path element #{el} against image #{image}"

    addOpToObject = (target, key, opType, opValue) ->
        prefix = if opType == 'JsonOp' then '' else opType+'$$'
        target[prefix + key] = opValue
        target


    # Determine whether the given object is an operation
    isOp = (key) ->
        key.indexOf('$$') > 0

    opOf = (key) ->
        z = key.split('$$')
        if z.length == 2
            z
        else
            ['JsonOp', key]

    # Convenience functions for info about slice operations
    isChange = (op) -> (_.isArray(op.i) or _.isString(op.i)) and _.isNumber(op.d)
    isKeep   = (op) -> _.isNumber(op)
    isModify = (op) ->
        _.isObject(op.m) or _.find(_.keys(op), (key) => key.indexOf("$$") > 0 )

    parseModify = (op) ->
        key = _.keys(op)[0]
        [opOf(key)[0], op[key]]

    # Length of slice to which this array operation can be applied
    preLen = (op) ->
        if _.isNumber(op) then op
        else if isChange(op) then op.d
        else if isModify(op) then 1
        else
            throw new Error "Unknown array op #{spliceOpToString op}"
    
    # Length of the slice produced by this array operation
    postLen = (op) ->
        if _.isNumber(op) then op
        else if isChange(op) then op.i.length
        else if isModify(op) then 1
        else
            throw new Error "Unknown array op #{spliceOpToString op}"

    # Split an array operation to apply to two smaller chunks
    opSplit = (op, n) ->
        if n > preLen(op) then throw new Error 'Illegal split'
        if _.isNumber(op)
            [n, op - n]
        else
            if isChange(op)
                [{i: op.i, d: n}, {i: (if _.isString(op.i) then "" else []), d: op.d - n}]
            else if isModify(op)
                throw new Error 'Cannot split modify operation'
            else
                throw new Error 'Unknown op'


    opPostSplit = (op, n) ->
        if n > postLen(op) or n < 1 then throw new Error "Illegal split #{n}"
        if _.isNumber(op)
            [n, op - n]
        else
            if isChange(op)
                [{i: op.i.slice(0, n), d: op.d}, {i: op.i.slice(n), d: 0}]
            else if isModify(op)
                throw new Error 'Cannot split modify'
            else
                throw new Error 'Unknown op'

    spliceOpToString = (spliceOp) ->
        if _.isNumber(spliceOp)
            spliceOp.toString()
        else if _.isObject(spliceOp)
            if spliceOp.d? and !spliceOp.i?
                "-#{spliceOp.d}"
            else if spliceOp.i? and !spliceOp.d?
                "+#{JSON.stringify spliceOp.i}"
            else if spliceOp.i? and spliceOp.d?
                "-#{spliceOp.d}/+#{JSON.stringify spliceOp.i}"
            else
                keys = _.keys(spliceOp)
                modifyOp = keys[0]
                [opType, opName] = opOf(keys[0])
                if opName != 'm'
                    throw new Error "Cannot convert #{JSON.stringify spliceOp} to string"
                opToString(opType, spliceOp[keys[0]])
        else
            throw new Error "Cannot convert #{JSON.stringify spliceOp} to string"

    # Convert an op to a compact string representation for debugging
    opToString = (opType, op) ->
      if !opType? then 'Id'
      else switch opType
          when 'Splice'
              "<#{_.map(op, spliceOpToString).join(' ')}>"
          when 'JsonOp'
              if !_.isObject(op) then throw new Error "JsonOp #{JSON.stringify op} should be object "
              kvs =
                  for k, subOp of op
                      [subOpType, subOpName] = opOf(k)
                      "#{subOpName}#{opToString(subOpType, subOp)}" 
              "{#{kvs.join(", ")}}"
          when 'Update'
              "=#{JSON.stringify op}"
          when 'Replace'
              "==#{JSON.stringify op}"
          else
              throw new Error "Cannot convert #{JSON.stringify op} to string"

    commitToString = (commit) ->
        "|#{commit.vs}: #{opToString 'JsonOp', commit.op}|"

        

    # Apply splice operation to a string or array
    applyArrayOp = (opList, spliceTarget) ->
        # Create a variable to accumulate the result
        result =
            if _.isString spliceTarget then ''
            else if _.isArray spliceTarget then []
            else throw new Error "Illegal splice operation " +
               "#{JSON.stringify opList} in #{JSON.stringify spliceTarget}"
        # n is the index into the spliceTarget
        n = 0
        for arrOp in opList
            # Take a slice of spliceTarget, apply the 
            # operation to it, then accumulate the result
            l        = preLen(arrOp)
            slice    = spliceTarget.slice(n, n+l)
            newSlice =
                if _.isNumber arrOp
                    slice # Keep op
                else if isChange(arrOp)
                    arrOp.i  # Replace or Insert
                else if isModify(arrOp)
                    [opType, opValue]  = parseModify(arrOp)
                    slice.map( (el) => apply(el, opType, opValue) )
            if _.isString result then result += newSlice
            else result.push newSlice...
            n += l
        unless n == spliceTarget.length
            throw new Error "Cannot apply splice of length #{n} to #{JSON.stringify spliceTarget}"
        unless _.isString result then Object.freeze result else result


    apply = (target, opType, opValue) ->
        if !opType?
            # Identity operation
            return target
        else switch opType
            when 'Update', 'Replace'
                # Simple 'Set' operation
                opValue
            when 'Splice'
                # Splice on a string or array
                applyArrayOp(opValue, target)
            when 'JsonOp'
                applyJsonOp(target, opValue)
            else
                throw new Error "Unknown opType #{opType}"


    # Apply an operation to an object, returning a new object
    # FUTURE: make this prettier/more efficient with Zippers?
    applyJsonOp = (target, opObject) ->

        unless _.isObject(target) and _.isObject(opObject) and !_.isArray(target) and !_.isArray(opObject)
            throw new Error "Undefined op (#{JSON.stringify opObject}) or target (#{JSON.stringify target})"

        # Partition the opObject into ops that apply at this path, and those that
        # recurse to a deeper object
        [opsHere, opsAtDepth] = _.partition _.keys(opObject), isOp

        # Create a map of key -> [opType, opValue] for this path
        ops = {}
        for key in opsHere
            [opType, opKey] = opOf key
            ops[opKey] = [opType, opObject[key]]

        # Build a new object for the result rather than mutating the original
        result = if _.isArray(target) then [] else {}
        for key, value of target
            result[key] =
                if key of ops
                    # There is an operation which needs to be applied here
                    [opType, opValue] = ops[key]
                    apply(value, opType, opValue)
                else if key in opsAtDepth
                    # Apply sub-op to sub-object
                    applyJsonOp(target[key], opObject[key])
                else
                    # Operation doesn't act here
                    # copy the already immutable object across
                    target[key]

        # Apply set ops to properties which don't exist yet
        for key, [opType, opValue] of ops when key not of target
            unless opType in ['Update', 'Replace']
                throw new Error "Illegal operation #{JSON.stringify opType} on #{JSON.stringify target}"
            result[key] = opValue # opValue should be immutable

        # Remove properties that have been set to null
        for key, value of result
            delete result[key] if !value?

        return Object.freeze result

    normalizeJsonOp = (opObject) ->

        # Allow commit(prop: value) instead of commit(prop: SharedObject.update(value))
        newObject = {}
        for key, value of opObject
            [opType, prop] = opOf(key)
            newValue = switch opType
                when 'Splice'
                    normalize2 = (a, b) ->
                        if isKeep(a) and isKeep(b)
                            [a + b]
                        else if isChange(a) and isChange(b)
                            newI = 
                                if _.isString(a.i) and _.isString(b.i)
                                    a.i + b.i
                                else if _.isArray(a.i) and _.isArray(b.i)
                                    a.i.concat b.i
                                else
                                    throw new Error 'Unexpected inserts'
                            [{d: a.d + b.d, i: newI}]
                        else
                            [a, b]

                    newSplice = []
                    for spliceOp in value
                        # First check for recursion
                        if isModify(spliceOp)
                            spliceOp = normalizeJsonOp(spliceOp)
                            if !spliceOp?
                                spliceOp = 1 # Keep(1)

                        # Skip non-ops such as {d: 0, i: []}
                        if postLen(spliceOp) == 0 and preLen(spliceOp) == 0
                            continue

                        # No normalization needed on first op
                        if newSplice.length == 0
                            newSplice.push(spliceOp)

                        # Normalize the ops in pairs
                        else
                            lastSpliceOp = newSplice.pop()
                            newSplice.push(normalize2(lastSpliceOp, spliceOp)...)
                    if newSplice.length == 0 or newSplice.length == 1 and isKeep(newSplice[0])
                        null
                    else
                        newSplice
                when 'JsonOp'
                    # Just recurse
                    normalizeJsonOp(value)
                else
                    value

            if opType in ['Update', 'Replace'] or newValue?
                # Reject undefined as the identity operation,
                # but keep Update: undefined and Replace: undefined as delete
                newObject[key] = newValue

        # make the operation immutable
        if _.keys(newObject).length == 0
            null # JSON.stringify returns "null" rather than null for undefined
        else
            Object.freeze(newObject)

    transposeSpliceOp = (a, b) ->

        # a and b must have equal prelengths
        unless preLen(a) == preLen(b)
            throw new Error "Illegal op splice transpose #{spliceOpToString a} and #{spliceOpToString b}"

        # Pass through 'Keep' operations
        if isKeep(a)      then [postLen(b), b]
        else if isKeep(b) then [a, postLen(a)]

        # Deal with deletion operations
        #else if isChange(a) and isChange(b)
        else if isChange(a)
            [{i: a.i, d: postLen(b)}, postLen(a)]
        else if isChange(b)
            [postLen(b), {i: b.i, d: postLen(a)}]
        # Recurse for modify slices
        else if isModify(a) and isModify(b)
            [aType, aOp] = parseModify(a)
            [bType, bOp] = parseModify(b)
            [resAType, resA, resBType, resB] = transpose(aType, aOp, bType, bOp)
            newA =
                if resA?
                    addOpToObject({}, 'm', resAType, resA)
                else
                    1
            newB =
                if resB?
                    addOpToObject({}, 'm', resBType, resB)
                else
                    1
            [newA, newB]
        else
            throw new Error "Cannot transpose #{spliceOpToString a} and #{spliceOpToString b}"

    transposeSplice = (a, b) ->
        NO_MORE_ELEMENTS = {}
        # Create arrays to receive the transpose result
        [resAs, resBs] = [[], []]
        # Reverse the input and make it writeable ready for processing
        [aOps, bOps] = [clone(a).reverse(), clone(b).reverse()]

        # Read through the ops until all are transposed
        while (aOps.length > 0 || bOps.length > 0)
            nextA = if aOps.length > 0 then aOps.pop() else NO_MORE_ELEMENTS
            nextB = if bOps.length > 0 then bOps.pop() else NO_MORE_ELEMENTS

            unless nextA? and nextB?
                throw new Error "Encountered null while transposing #{opToString 'Splice', a} and #{opToString 'Splice', b}"

            # Deal with the case of trailing inserts which cannot
            # be paired with anything for transposition
            if nextA == NO_MORE_ELEMENTS
                if preLen(nextB) > 0 then throw new Error "Second operand of splice transpose #{opToString 'Splice', a}, #{opToString bType, b} too long"
                resBs.push(nextB)
                # Certain that postLen(nextB) > 0
                resAs.push(postLen(nextB))
                continue
            if nextB == NO_MORE_ELEMENTS
                if preLen(nextA) > 0 
                    throw new Error "First operand of splice transpose #{opToString 'Splice', a}, #{opToString 'Splice', b} too long"
                resAs.push(nextA)
                # Certain that postLen(nextA) > 0
                resBs.push(postLen(nextA))
                continue

            # Split the operations into matching chunks and 
            # put the remainder back into the input
            [la, lb] = [preLen(nextA), preLen(nextB)]
            [splitA, splitB] =
                if lb == 0
                    # A has no prelength, deal with it first
                    aOps.push nextA
                    [0, nextB]
                else if la == 0
                    # B has no prelength, deal with it first
                    bOps.push nextB
                    [nextA, 0]
                else if la == lb
                    [nextA, nextB]
                else if la > lb
                    [newA, rem] = opSplit(nextA, lb)
                    aOps.push rem
                    [newA, nextB]
                else if lb > la
                    [newB, rem] = opSplit(nextB, la)
                    bOps.push rem
                    [nextA, newB]

            # Transpose the now matching chunks
            if isChange(splitA) and isChange(splitB)
                if postLen(splitB) > 0
                    resAs.push postLen(splitB)
                if postLen(splitA) > 0
                    resAs.push {i: splitA.i, d: 0}
                if postLen(splitB) > 0
                    resBs.push {i: splitB.i, d: 0}
                if postLen(splitA) > 0
                    resBs.push postLen(splitA)
            else
                [resA, resB] = transposeSpliceOp(splitA, splitB)
                if !resA? or !resB?
                    throw new Error "Produced null result (#{JSON.stringify resA}, #{JSON.stringify resB}) transposing #{JSON.stringify splitA}, #{JSON.stringify splitB}"
                resAs.push resA if resA != 0
                resBs.push resB if resB != 0
        [resAs, resBs]


    # Transpose two operations against each other
    transpose = (aType, a, bType, b) ->
        unless aType? and bType?
            throw 'No type in transpose'
        if bType == 'Replace' or bType == 'Update'
            [undefined, undefined, bType, b]
        else if aType == 'Replace' or aType == 'Update'
            [aType, a, undefined, undefined]
        else if aType == 'Splice' and bType == 'Splice'
            [splA, splB] = transposeSplice(a, b)
            ['Splice', splA, 'Splice', splB]
        else if (aType == 'JsonOp') and (bType == 'JsonOp')
            [jsA, jsB] = transposeJsonOp(a, b)
            ['JsonOp', jsA, 'JsonOp', jsB]
        else
            throw new Error "Unknown op types #{aType}, #{bType}"

    # Transpose two commands, each of which may contain many operations
    # a: The first argument is the unconfirmed client operation
    # b: The second argument is the confirmed server operation and has 
    #    priority where unresolvable conflicts occur
    transposeJsonOp = (a, b) ->
        newA = {}
        newB = {}

        # eg: Update$$prop1: value1
        # Create a dictionary of keys (eg: prop1) to
        #   the original Key (eg: Update$$prop1)
        #   the opType (eg: Update)
        #   the property (eg: value1)
        dictA = {}
        dictB = {}
        for key, value of a
            [opType, opKey] = opOf(key)
            dictA[opKey] = [key, opType, a[key]]
        for key, value of b
            [opType, opKey] = opOf(key)
            dictB[opKey] = [key, opType, b[key]]
        for key in _.union (_.keys dictA), (_.keys dictB)
            [fullKeyA, opTypeA, an] = dictA[key] ? [key, undefined, undefined]
            [fullKeyB, opTypeB, bn] = dictB[key] ? [key, undefined, undefined]
            [newAType, newAn, newBType, newBn] =
                if !opTypeA? or !opTypeB?
                    # One or the other key isn't defined
                    # Just pass through
                    [opTypeA, an, opTypeB, bn]
                else
                    # Both keys present, recurse
                    transpose(opTypeA, an, opTypeB, bn)
            addOpToObject(newA, key, newAType, newAn) if newAn?
            addOpToObject(newB, key, newBType, newBn) if newBn?
        [newA, newB]

    # Alters a path to take account of other operations
    # moving it around
    #
    # eg: for an object image
    #     arr: ['a', 'b']
    # and a path ['arr', 1] which points to 'a',
    # if a value is inserted before 'a', to make the image
    #     arr: ['x', 'a', 'b']
    # then the path should become
    #     ['arr', 2]
    # thus, still pointing to 'a'
    transposePath = (a, path) ->
        # Empty paths cannot be transformed
        # If there are operations deeper than this path,
        # then the path stays the same
        if !path? or path.length == 0 then return path
        pathHead = _.head(path)
        pathTail = _.tail(path)
        if a[pathHead]?
            # JSON Operation on a subpath of this path
            [pathHead].concat transposePath(a[pathHead], pathTail)
        else
            # If the operation applies exactly to this path, replacing or
            # mutating the object the path points to, we can keep this path,
            # which will then point to the new object
            if pathTail.length == 0 then return path

            # Get the operations that affect this path
            opsHere = _.keys(a).filter (key) => key.indexOf('$$' + pathHead) > 0

            # This operation doesn't affect this path
            if opsHere.length == 0 then return path

            # More than one operation at the same point
            if opsHere.length > 1 then throw new Error 'Two operations at the same point'

            # Found exactly one operation here
            key = opsHere[0]

            # Generate a new path transformed by this operation
            [opType, el] = key.split('$$')

            # Return a transformed path
            if opType == 'Update' or opType == 'Replace'
                # This path has been cut off by an
                # update in its midriff
                throw new Error 'Invalidated this path'
            else if opType == 'Splice'
                # Splice around the path's midriff
                # This component of the path must be a number
                pathIndex = _.head pathTail
                unless _.isNumber(pathIndex)
                    throw new Error "Can't transpose '#{pathHead}' with splice of '#{el}'"
                # Let's calculate the new index
                op = a[key]
                shift = 0
                keep  = 0
                newTail = _.tail(pathTail)
                for spliceOp in op
                    dKeep  = preLen(spliceOp)
                    dShift = postLen(spliceOp) - dKeep
                    # Delete op - shift left, or invalidate
                    if keep + dKeep > pathIndex
                        if spliceOp.d?
                            throw new Error 'Invalidated this path'
                        else if preLen(spliceOp) == 1
                            # Sub-operation on this slice,
                            # Transform the tail of this path
                            # TODO: add test for this
                            newPath = _.tail( transposePath(spliceOp, ['m'].concat newTail) )
                        break
                    keep  += dKeep
                    shift += dShift
                pathIndex += shift
                # Shiny new path
                [pathHead, pathIndex].concat(newTail)
            else
                throw new Error 'Unknown op type'


    # Compose single splices of identical length as a . b
    # ie: b is applied first
    # eg: {Update$$m: 3}, {i: [5], d: 0}
    composeSplice = (a, b) ->
        unless postLen(b) == preLen(a) and postLen(b) > 0
            throw "Illegal compose of splices #{spliceOpToString a} and #{spliceOpToString b}"
        if isKeep(a)
            # a keep op in a doesn't affect b
            b
        else if isKeep(b)
            # a keep op in b doesn't affect a
            a
        else if isChange(a)
            # a deletes whatever was modified in b
            { d: preLen(b), i: a.i }
        else if isChange(b)
            # An insert in a which is modified in b
            # Must apply a to contents of b
            { d: b.d, i: applyArrayOp([a], b.i) }
        else if isModify(a) and isModify(b)
            # Modify ops, recurse
            [opTypeA, opA] = parseModify(a)
            [opTypeB, opB] = parseModify(b)
            [newOpType, newOp] = compose(opTypeA, opA, opTypeB, opB)
            addOpToObject({}, 'm', newOpType, newOp)
        else
            throw new Error "Cannot compose #{JSON.stringify a} and #{JSON.stringify b}"

    # Composes splice operations of identical length on a whole array a.b
    # ie, b is applied before a
    # eg: [1, {i: 'Hi'}, 2] with [2, {d: 1}, 1]
    composeSplices = (a, b) ->
        # If a and b are Nil, we are finished
        if a.length == 0 and b.length == 0 then return []

        # Check for 0-postLength operations in a, which can be passed through
        a0 = _.head(a)
        if a0? and preLen(a0) == 0
            return [a0].concat composeSplices(_.tail(a), b)

        # Check for 0-preLength operations in b, which can be passed through
        b0 = _.head(b)
        if b0? and postLen(b0) == 0
            return [b0].concat composeSplices(a, _.tail(b))

        if b.length == 0 and a.length > 0 or a.length == 0 and b.length > 0
            throw new Error "Composed slices of unequal length #{JSON.stringify a} and #{JSON.stringify b}"

        la = preLen(a0)
        lb = postLen(b0)
        remA = _.tail(a)
        remB = _.tail(b)
        if la > lb
            # Splice up the first op in a, compose the matching slices and recurse
            [a0, a1] = opSplit(a0, lb)
            [composeSplice(a0, b0)].concat composeSplices([a1].concat(remA), remB)
        else if lb > la
            # Slice up the first op in b, compose the matching slices and recurse
            [b0, b1] = opPostSplit(b0, la)
            [composeSplice(a0, b0)].concat composeSplices(remA, [b1].concat(remB))
        else # la == lb
            # No slicing needed, just compose the matching slices and recurse
            [composeSplice(a0, b0)].concat composeSplices(remA, remB)

    # Compose two operation a and b as a.b, ie: b is applied first
    compose = (aType, a, bType, b) ->
        if aType == 'Update' or aType == 'Replace'
            # The update on the second op wins
            [aType, a]
        else if a == undefined
            # a is identity operation
            [bType, b]
        else if b == undefined
            # b is identity operation
            [aType, a]
        else if bType == 'Update' or bType == 'Replace'
            # b updates the object and a operated on the updated value
            [bType, apply(b, aType, a)]
        else if aType == 'JsonOp' and bType == 'JsonOp'
            ['JsonOp', composeJsonOps(a, b)]
        else if aType == 'Splice' and bType == 'Splice'
            ['Splice', composeSplices(a, b)]
        else
            throw new Error "Illegal composition of #{aType} and #{bType}"

    composeJsonOps = (a, b) ->
        # Make a record of all ops on a and b
        result = {}
        dictA = {}
        dictB = {}
        for key, value of a
            [opType, opKey] = opOf(key)
            dictA[opKey] = [opType, a[key]]
        for key, value of b
            [opType, opKey] = opOf(key)
            dictB[opKey] = [opType, b[key]]
        keys = _.union (_.keys dictA), (_.keys dictB)
        result = {}
        for key in keys
            [opTypeA, a_] = dictA[key] ? [key, undefined, undefined]
            [opTypeB, b_] = dictB[key] ? [key, undefined, undefined]
            if a_? and b_?
                # Recurse as both properties are operated on
                [newOpType, newOpValue] = compose(opTypeA, a_, opTypeB, b_)
                addOpToObject(result, key, newOpType, newOpValue)
            else if a_?
                # Only a is affected, pass through
                addOpToObject(result, key, opTypeA, a_)
            else if b_?
                # Only b is affected, pass through
                addOpToObject(result, key, opTypeB, b_)
        result

    # Define some global sharedobject state which
    # is necessary for communicating with the server and hiding
    # mutable state for individual sharedobjects
    # This is a map of UUID to state
    state = {}

    # Set up server communications
    routes = {}

    #log.setLevel(Logger.DEBUG)

    # Class representing the state of a shared object
    SOState = (@domain, @uuid) ->
        @unappliedOps  = [] # Array of operations yet to be appended
        @localHistory  = [] # Mutable array
        @historyStart  = 0  # History may not extend back to object creation
        @localImage    = {} # Immutable snapshot
        @sentToServer  = 0  # Number of commits from localHistory
        @serverHistory = [] # Mutable array
        @serverImage   = @localImage # Immutable snapshot
        @listeners     = [] # Mutable array

        @requestState = =>
            # When the websocket opens or re-opens, we subscribe to the shared object
            # Only when we receive the state update do we attempt to send new commits
            unless routes[@domain]?
                # Add a route for this domain
                routes[@domain] = wsrouter.addRoute(@domain, ->)

            # TODO: include history start request in send
            routes[@domain].send(uuid) # Subscribe to the shared object

        @commitRoute = wsrouter.addRoute @uuid, (msg) =>
                # Receive a message from the server
                result = undefined
                deepFreeze = (obj) ->
                    for key, val of obj
                        if obj.hasOwnProperty(key) and _.isObject(val)
                            deepFreeze(val)
                    Object.freeze(obj)
                try 
                    result = deepFreeze JSON.parse(msg)
                catch e
                    log.error "Error from server: #{msg}"
                    # TODO: clear local history and re-request state
                    #@requestState()
                    return
                if result.image?
                    log.debug "Received image #{JSON.stringify result} for #{@uuid}"
                    # Initial SO state sent from server
                    # {historyStart: Number, history: [Commit], state: JSON}

                    # Now we need to reintegrate local commits
                    #
                    oldServerHistoryLength = @historyStart + @serverHistory.length
                    newServerHistoryLength = result.history.length + result.historyStart

                    if oldServerHistoryLength > newServerHistoryLength
                        # Something has gone horribly wrong
                        throw new Error 'Fatal: server sent shorter history than already confirmed'

                    if result.historyStart > oldServerHistoryLength
                        log.warn "Dropped all local history because server history is too short"
                        # Server hasn't sent enough history to transform local commits.
                        # We must abandon all local commits
                        # FUTURE: consider re-requesting history instead?
                        @localHistory  = []
                        @serverHistory = []
                        @historyStart  = result.historyStart
                        @unappliedOps  = []
                        @sentToServer  = 0
                        @serverImage   = @localImage = result.image
                        commits = result.history.reverse()
                        transformedCommits = @receiveFromServer(commits...)
                        updateListeners(transformedCommits, @localImage, @listeners, true)
                    else
                        # We can transform local history against new commits supplied by the server
                        newServerCommits = _.drop(result.history, oldServerHistoryLength - result.historyStart)
                        log.debug "Adding #{newServerCommits.length} server commits from server image"

                        # Copy across values from server
                        transformedCommits = @receiveFromServer(newServerCommits...)

                        # If commits we sent to the server previously aren't in the image
                        # they must never have been received.
                        @sentToServer = 0
                        updateListeners(transformedCommits, @localImage, @listeners, true)
                    # - First, remove any local commits that have been applied on the server

                else
                    # Array of commits or one commit sent by server
                    commits = if _.isArray(result) then result.reverse() else [result]
                    transformedCommits = @receiveFromServer(commits...)
                log.debug "Server updated #{@uuid} to #{JSON.stringify @serverImage}"
                @trySendingNextCommit()

        wsrouter.onOpen => @requestState()

        wsrouter.onError =>
            # Assume all commits already sent never reached the server
            # the server will de-duplicate
            @sentToServer = 0

        this


    SOState :: trySendingNextCommit = ->
        if @sentToServer == 0 and @localHistory.length > 0 and @commitRoute.isOpen()
            commit = _.head(@localHistory)
            log.debug "Sending commit #{commitToString commit} to server"
            @commitRoute.send(JSON.stringify commit)
            @sentToServer += 1

    SOState :: commit = (ops...) ->

        # The first op applied is at the beginning of ops
        ops = @unappliedOps.concat(ops)
        if ops.length == 0
            return
        @unappliedOps = []

        # Transpose ops over each other to linearize them
        transposedOps = []
        for opToTranspose in ops
            for op in transposedOps
                opToTranspose = transposeJsonOp(opToTranspose, op)[0]
            transposedOps.push opToTranspose

        # Must reverse the arguments of compose, which takes the last applied op last
        composedOp = normalizeJsonOp _.foldl(transposedOps, ((b, a) -> composeJsonOps(a, b)))
        log.debug "Committing #{opToString (if op? then 'JsonOp' else undefined), composedOp} to #{@uuid}"

        # Create a commit for each op
        userId = getUser()
        if !userId?
            throw new Error 'Attempt to commit operation without active user'
        now = Date.now() # Milliseconds since 1970 UTC
        vs = @vs()
        commit =
            uuid: @uuid
            vs: vs
            op: composedOp
            author: userId
            created: now

        @localImage = updateImage([composedOp], @localImage)
        updateListeners([commit], @localImage, @listeners, false)
        @localHistory.push commit

        # If we got here with no errors, try sending the operations to the server
        @trySendingNextCommit()

    listenerIdGen = 0

    SOState :: onChange = (fn) ->
        id = listenerIdGen++
        @listeners.push [id, fn]

    SOState :: unsubscribe = (listenerId) ->
        @listeners = @listeners.filter ([id, fn]) ->
            listenerId != id

    # Integrate a commit received from the server, and adjust
    # local history to match.
    # Returns the server operation transformed by local history
    SOState :: receiveFromServer = (commits...) ->

        ops = _.pluck(commits, 'op')

        # Make sure all ops are immutable
        transformedCommits = []
        for commit in commits

            # Check that this update is valid
            unless commit.vs == @serverHistory.length + @historyStart
                # Server and client are out of sync
                # TODO reload SO from server
                throw new Error "Received illegal commit from server #{JSON.stringify commit}, history length #{@serverHistory.length + @historyStart}"

            op = commit.op
            # Update server history
            @serverHistory.push(commit)
            @serverImage = updateImage([op], @serverImage)
            # If op is exactly what we sent to the server
            # we are home and dry
            if @sentToServer > 0 and _.isEqual(op, @localHistory[0].op)
                log.debug "Received confirmation of commit #{commitToString commit} from server"
                # Confirmation of an op we sent to the server earlier
                # Just shift it from local to server history
                @sentToServer -= 1
                @localHistory.shift()
            else
                # This must be a new update from another client
                # Transform local history against it
                # Then apply it
                log.debug "Processing new commit #{commitToString commit} from server"

                newLocalHistory = []
                for localCommit in @localHistory
                    newLocalCommit = clone(localCommit)
                    newLocalCommit.vs += 1
                    [newLocalOp, op] = transposeJsonOp(localCommit.op, op)
                    newLocalCommit.op = normalizeJsonOp(newLocalOp)
                    newLocalHistory.push newLocalCommit
                @localHistory = newLocalHistory
                # Regenerate local image from server image
                @localImage   = updateImage(_.pluck(@localHistory, 'op'), @serverImage)
                transformedCommit = clone commit
                transformedCommit.op = op
                transformedCommits.push transformedCommit

        if transformedCommits.length > 0
            updateListeners(transformedCommits, @localImage, @listeners, false)

        transformedCommits

    SOState :: vs = ->
        @localHistory.length + @serverHistory.length + @historyStart

    SOState :: updatesSince = (oldVs) ->
        if oldVs < @historyStart
            # TODO: load history from server here?
            throw new Error 'Attempt to get updates from before history started'
        n = @vs() - oldVs
        if n > @localHistory.length
            # Include some server history
            _.drop(@serverHistory, oldVs).concat(@localHistory)
        else
            # Everything needed in local history
            _.drop(@localHistory, @localHistory.length - n)


    # An API for applying operations to part of a sharedobject
    class Path

        # Set up private state
        # soState, 
        constructor: (soState, @path) ->

            # Check path validity
            if _.isString(@path)
                @path = @path.split('.')
            if !_.isArray(@path)
                throw new Error "Path must be a string or array, found #{path}"

            @listeners = []

            vs = soState.vs()

            # TODO: cope with rewriting of history ?
            validate = =>
                newVs = soState.vs()
                if newVs > vs and vs >= soState.historyStart
                    updates = _.pluck(soState.updatesSince(vs), 'op')
                    try
                        for update in updates
                            @path = transposePath(update, @path)
                        vs = newVs
                    catch e
                        if e.message == 'Invalidated this path'
                            @path = undefined
                        else
                            throw e

            @image = ->
                validate()
                if !@path? then throw new Error 'Path invalidated by other operations'
                image = soState.localImage
                for el in @path
                    if !image?
                        throw new Error "Couldn't find #{@path} in #{JSON.stringify soState.localImage}"
                    image = image[el]
                image

            @isValid = ->
                validate()
                @path?

            listenerIdGen = 0
            stateListenerId = undefined

            @onChange = (callback) ->
                if @listeners.length == 0
                    stateListenerId = soState.onChange (newImage, op) =>
                        # Find op at this path
                        for pathEl in @path
                            op = op.at(pathEl)
                            if !op? then return
                        
                        image = @image()
                        toRemove = []
                        for [id, callback] in @listeners
                            # Only send updates if op is defined
                            if op?
                                result = callback(image, op)
                                if result == 'unregister'
                                    toRemove.push callback
                        @listeners = _.difference(@listeners, toRemove)
                id = listenerIdGen++
                @listeners.push [id, callback]
                return id


            @unsubscribe = (idToUnsubscribe) ->
                @listeners = @listeners.filter ([id, callback]) ->
                    id != idToUnsubscribe 
                if @listeners.length == 0 and stateListenerId?
                    soState.unsubscribe(stateListenerId)
                return this

            @createOp = (opType, op) ->
                image = soState.localImage
                pathWithImage = for el in _.initial(@path)
                    image  = image[el]
                el = _.last(@path)
                newOp = createOp(opType, op, el, image)
                @addRawOp(newOp)
                return this

            @addRawOp = (op) ->
                image = soState.localImage
                pathWithImage = for el in @path
                    result = [el, image]
                    image  = image[el]
                    result
                for [el, image] in _.initial(pathWithImage).reverse()
                    opType =
                        if _.isArray(op)
                            'Splice'
                        else if _.isObject(op)
                            'JsonOp'
                        else
                            'Unknown recursive op type #{op}'
                    op = createOp(opType, op, el, image)
                soState.unappliedOps.push op
                return this

            @commit = ->
                soState.commit()
                return this

            # Create a sub-path from this path
            @at = (subpath...) ->
                new Path(soState, @path.concat subpath)

            @uuid = soState.uuid

            @vs = -> soState.vs()

        commitRawOp: (op) ->
            @addRawOp(op)
            @commit()

        # Define the convenience methods for creating ops
        update:  (x...) -> @setOp('Update')(x...)
        replace: (x...) -> @setOp('Replace')(x...)
        setOp:   (opType) -> (value) => @createOp(opType, value)

        # Define convenience methods for arrays and strings
        append: (value) ->
            image = @image() ? []
            @insert(image.length, value)
        insert: (index, value) ->
            @splice(index, 0, value)
        delete: (index, nDelete) ->
            @splice(index, nDelete, if _.isArray(@image()) then [] else '')
        splice: (index, nDelete, value) ->

            # Check parameters are legal
            obj = @image()
            unless obj? and _.isNumber(index) and 0 <= index <= obj.length - nDelete
                throw new Error "Invalid splice at #{index}, length #{nDelete}, path #{@path}, on array #{JSON.stringify obj}"
            if (_.isString(obj) and !_.isString(value)) or (_.isArray(obj) and !_.isArray(value))
                throw new Error "Attempt to illegally insert #{value} at #{@path} into #{JSON.stringify obj}"

            # Create the splice operation
            spliceOp = []
            if index > 0 then spliceOp.push index
            spliceOp.push
                d: nDelete
                i: value
            l = value.length
            if index + nDelete < obj.length
                spliceOp.push (obj.length - index - nDelete)

            @createOp('Splice', spliceOp)

        # Utility methods for use with Angular
        bindToScope: (scope, name) ->
            safeApply = (fn) ->
                if scope.$$phase || scope.$root.$$phase then fn()
                else scope.$apply fn
            applyChanges = (image) -> safeApply ->
                if image? then scope[name] = clone(image)
            applyChanges(@image())
            @onChange applyChanges


    # API for querying ops
    class Op

        constructor: (@opType, @op) ->
            # Parameter checking
            @isNull = false
            if @opType in ['Update', 'Replace']
                @value = @op
            else if !@opType? or !@op?
                @isNull = true
            else if @opType == 'JsonOp'
                unless _.isObject(@op) then throw new Error 'Illegal JsonOp'
            else if @opType == 'Splice'
                unless _.isArray(@op) then throw new Error 'Illegal Splice'
                @preLenSum  = 0
                @postLenSum = 0
                for spliceOp in op ? []
                    @preLenSum  += preLen(spliceOp)
                    @postLenSum += postLen(spliceOp)
            else
                throw new Error 'Illegal Op'

        keys: ->
            if @opType == 'JsonOp'
                _.map _.keys(@op), (key) -> opOf(key)[1]
            else if @opType == 'Update' or @opType == 'Replace'
                _.keys(@op)
            else
                throw new Error 'can only get keys for JsonOp'

        at: (prop) ->
            if @opType == 'JsonOp' and _.isString(prop)
                keys = _.filter _.keys(@op), (key) -> opOf(key)[1] == prop
                if keys.length == 0
                    undefined
                else
                    key = keys[0]
                    innerOp = @op[key]
                    opType  = opOf(key)[0]
                    new Op(opType, innerOp)
            else if @opType in ['Update', 'Replace'] and _.isString(prop)
                if @op? and @op[prop]?
                    new Op(@opType, @op[prop])
                else
                    undefined
            else
                throw new Error 'Illegal call to at'

        dl: ->
            unless _.isArray(@op) then throw new Error 'dl only valid for array ops'
            @postLenSum - @preLenSum

        updatedRange: ->
            # Assumes normalized op, ie only one keep operation at beginning / end
            # of slice
            unless @opType == 'Splice' then throw new Error 'range only valid for array ops'
            getOr0 = (x) -> if _.isNumber(x) then x else 0
            a0 = getOr0(_.head(@op))
            a1 = getOr0(_.last(@op))
            [a0, @preLenSum - a1]

        isNull: ->
            !@op?

        isReplace: ->
            @opType == 'Update' or @opType == 'Replace'

        toString: ->
            opToString(@opType, @op)


    # Return static method API
    {
        create: (domain = 'data') ->
            @fetch(domain, generateUuid())

        fetch: (domain, uuid) ->
            # Fetch the shared object matching this uuid from the server unless $uuidUtils.test(uuid) throw 'Illegal UUID'
            # Unless the so is already here,
            # create a new shared object, and ask the server for updates
            unless state[uuid]?
                log.info("Fetching shared object #{domain}: #{uuid}")
                state[uuid] = new SOState(domain, uuid)
            new Path(state[uuid], [])

        isLoaded: (uuid) ->
            state[uuid]?

        # This is mainly for testing purposes
        stateOf: (uuid) ->
            clone(state[uuid])

        fnsForUnitTests:
            normalizeJsonOp: normalizeJsonOp
            transpose: transpose
            compose: compose
            apply: apply
    }


