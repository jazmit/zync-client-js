# Specification for essay component
describe 'A shared object', ->
    so           = undefined
    O            = undefined
    sendToServer = undefined
    deepFreeze   = undefined
    vs           = undefined
    wsCallback   = undefined

    beforeEach ->

        vs = 0

        # Provide a fake shared object socket
        sendToServer = jasmine.createSpy('sendToServer')

        WebSocket =
            OPEN: 0
            CLOSED: 1

        # Fake WSRouter
        fakeRouter =
            addRoute: (key, callback) ->
                wsCallback = callback
                isOpen: -> true
                send: sendToServer
                close: ->
            onOpen:  ->
            onError: ->

        fakeUserData = -> 1

        window.Logger =
            get: ->
                debug: ->
                info:  ->
                warn:  ->
                error: ->

        O = SOFactory(fakeUserData, fakeRouter)
        so = O.create()
        deepFreeze = (obj) ->
            for key, val of obj
                if obj.hasOwnProperty(key) and _.isObject(val)
                    deepFreeze(val)
            Object.freeze(obj)

    # Abstract the API somewhat
    # to allow experimentation with changing API
    image         = -> so.image()
    localCommits  = -> O.stateOf(so.uuid).localHistory
    localHistory  = -> _.pluck(localCommits(), 'op')
    serverHistory = -> _.pluck(O.stateOf(so.uuid).serverHistory, 'op')
    serverImage   = -> O.stateOf(so.uuid).serverImage
    receiveFromServer = (ops...) ->
        commits = for op in ops
            uuid: so.uuid
            op: op
            vs: vs++
            author: 1999
            created: Date.now()
            applied: Date.now()
        wsCallback(JSON.stringify commits)

    # Convenience methods for setting up simple test data
    createArray = ->
        so.commitRawOp Update$$arr: ['a', 'b']
        receiveFromServer Update$$arr: ['a', 'b']
    createString = ->
        so.commitRawOp Update$$str: "Hello"
        receiveFromServer Update$$str: "Hello"
    createProp = ->
        so.commitRawOp Update$$prop: {}
        receiveFromServer Update$$prop: {}

    it 'updates the local image on "update" using object paths', ->
        so.commitRawOp
            Update$$prop1: 'value1'
        expect( image().prop1 ).toBe 'value1'
        expect( serverHistory() ).toEqual []
        expect( localHistory()[0] ).toEqual
            Update$$prop1: 'value1'
        so.commitRawOp
            Update$$prop2:
                prop3:
                    prop4: 'value2'
        expect( image().prop2.prop3.prop4 ).toBe 'value2'
        expect( localHistory().length ).toBe 2

        so.commitRawOp
            Update$$prop2: 'value3'
        expect( image().prop2 ).toBe 'value3'
        expect( localHistory().length ).toBe 3

    it 'interpolates plain objects as updates', ->
        so.commitRawOp Update$$prop: 'value'
        expect( image().prop ).toBe 'value'

    it 'behaves correctly for "update" edge cases', ->
        expect( -> so.commitRawOp 'Update$$value').toThrow()

    describe 'interacting with the server', ->

        it 'should send updates to server when possible', ->
            # First update should be sent to server
            so.at('prop').update('value1').commit()
            expect( sendToServer.calls.length ).toBe 1
            expect( localHistory(so).length   ).toBe 1
            expect( serverHistory(so).length  ).toBe 0

            # Second update should not be sent, as
            # no confirmation received from server
            so.at('prop').update('value2').commit()
            expect( sendToServer.calls.length ).toBe 1
            expect( localHistory(so).length   ).toBe 2
            expect( serverHistory(so).length  ).toBe 0

            # Second update should be sent as soon as
            # confirmation received from server, and the 
            # first should be moved from local to server history
            receiveFromServer Update$$prop: 'value1'
            expect( sendToServer.calls.length ).toBe 2
            expect( localHistory(so).length   ).toBe 1
            expect( serverHistory(so).length  ).toBe 1

            ## When second confirmation is received from
            ## the server, all history should be server history
            receiveFromServer Update$$prop: 'value2'
            expect( sendToServer.calls.length ).toBe 2
            expect( localHistory(so).length   ).toBe 0
            expect( serverHistory(so).length  ).toBe 2


        it 'should accept new updates from the server', ->
            receiveFromServer Update$$prop: 'value'
            expect( image().prop ).toBe 'value'
            expect( localHistory(so).length ).toBe 0
            expect( serverHistory(so).length )

        it 'should merge non-conflicting updates from the server', ->
            so.commitRawOp            Update$$localProp: 'localValue'
            receiveFromServer(Update$$serverProp: 'serverValue')
            expect( image() ).toEqual deepFreeze
                localProp: 'localValue'
                serverProp: 'serverValue'

        it 'should merge conflicting updates from the server in favour of the server', ->
            so.commitRawOp            Update$$prop: 'localValue'
            receiveFromServer Update$$prop: 'serverValue'
            expect( image() ).toEqual deepFreeze
                prop: 'serverValue'


        # FUTURE
        xit 'should merge local updates into occluding updates from server', ->
            createProp()
            so.commitRawOp            prop:  Update$$localProp: 'localValue'
            receiveFromServer Update$$prop: serverProp: 'serverValue'
            expect( image() ).toEqual deepFreeze
                prop:
                    localProp: 'localValue'
                    serverProp: 'serverValue'

        it 'should wipe any local updates on server Replace', ->
            createProp()
            so.commitRawOp            prop:  Update$$localProp: 'localValue'
            receiveFromServer Replace$$prop: serverProp: 'serverValue'
            expect( image() ).toEqual deepFreeze
                prop:
                    serverProp: 'serverValue'

        # FUTURE
        xit 'should merge server updates into occluding local updates', ->
            createProp()
            so.commitRawOp                  Update$$prop: localProp: 'localValue'
            receiveFromServer prop: Update$$serverProp: 'serverValue'
            expect( image() ).toEqual deepFreeze
                prop:
                    localProp: 'localValue'
                    serverProp: 'serverValue'

        # Old meaning of Replace
        xit 'should wipe local replaces conflicting with server merges', ->
            createProp()
            so.commitRawOp Replace$$prop: localProp: 'localValue'
            receiveFromServer prop: Update$$serverProp: 'serverValue'
            expect( image() ).toEqual deepFreeze
                prop:
                    serverProp: 'serverValue'

        it 'should accept confirmation of own commit after transposition', ->
            so.commitRawOp Update$$x: [9]
            receiveFromServer Update$$x: [9]

            # Append '1' locally
            so.at('x').append([1]).commit()
            expect( image() ).toEqual deepFreeze
                x: [9, 1]
            expect( localCommits().length ).toBe 1

            # Append '2' from server
            receiveFromServer Splice$$x: [1, {i: [2], d: 0}]
            expect( serverImage() ).toEqual
                x: [9, 2]
            expect( image() ).toEqual deepFreeze
                x: [9, 2, 1]

            # Receive confirmation of original '1'
            # This was originally broken because of inconsistent normalization
            # a similar bug may appear if normalization not consistent between
            # client and server
            receiveFromServer Splice$$x: [2, {i: [1], d: 0}]
            expect( serverImage() ).toEqual
                x: [9, 2, 1]
            expect( image() ).toEqual deepFreeze
                x: [9, 2, 1]
            expect( localCommits().length ).toBe 0
            

        it 'should notify listeners on every update', ->
            mockListener = jasmine.createSpy('change listener')
            so.onChange mockListener
            so.commitRawOp Update$$prop: 'value'
            expect( mockListener ).toHaveBeenCalled()

        it 'should not notify listeners after unsubscribe', ->
            mockListener = jasmine.createSpy('change listener')
            listenerId = so.onChange mockListener
            so.unsubscribe(listenerId)
            so.commitRawOp Update$$prop: 'value'
            expect( mockListener ).not.toHaveBeenCalled()

        it 'should only notify listeners at that path', ->
            mockListener = jasmine.createSpy('change listener')
            so.commitRawOp
                Update$$prop1: 'value1'
                Update$$prop2: 'value1'
            so.at('prop2').onChange mockListener
            so.at('prop1').update('value2').commit()
            expect( mockListener ).not.toHaveBeenCalled()
            so.at('prop2').update('value2').commit()
            expect( mockListener ).toHaveBeenCalled()

        it 'should be immutable', ->
            so.commitRawOp Update$$prop: 'value'
            so.commitRawOp Update$$prop2: 'value2'
            expect( -> image().prop = 'value4' ).toThrow()

        it 'should allow updates inside arrays', ->
            so.commitRawOp
                Update$$arr: [{a: 2}]
            so.commitRawOp
                Splice$$arr: [{m: Update$$a: 3}]
            expect( image() ).toEqual deepFreeze
                arr: [{a: 3}]
                
        it 'should allow array insertion', ->
            so.commitRawOp Update$$arr: ['a','b']
            so.commitRawOp Splice$$arr: [1, {i: ['x'], d: 0}, 1]
            expect( image() ).toEqual deepFreeze
                arr: ['a','x','b']

        it 'should allow transpose of client insert and server update', ->
            createArray()
            so.commitRawOp Splice$$arr: [{i: ['x'], d: 0}, 2]
            receiveFromServer Splice$$arr: [{Update$$m: 'y'}, 1]
            expect( image() ).toEqual deepFreeze
                arr: ['x', 'y', 'b']

        it 'should allow transpose of client update and server insert', ->
            createArray()
            so.commitRawOp Splice$$arr: [{Update$$m: 'y'}, 1]
            receiveFromServer Splice$$arr: [{i: ['x'], d: 0}, 2]
            expect( image() ).toEqual deepFreeze
                arr: ['x', 'y', 'b']

        # FUTURE: reimplement update semantics
        xit 'should retain a server splice over a client update', ->
            createArray()
            so.commitRawOp Update$$arr: ['x']
            receiveFromServer Splice$$arr: [{d: 2, i: ['y']}]
            expect( image() ).toEqual deepFreeze
                arr: ['y']

        it 'should allow a client splice to remove a server update', ->
            createArray()
            so.commitRawOp Splice$$arr: [{d: 1, i: []}, 1]
            receiveFromServer Splice$$arr: [{Update$$m: 'q'}, 1]
            expect( image() ).toEqual deepFreeze
                arr: ['b']
            
        it 'should allow a client splice to remove a server update', ->
            createArray()
            so.commitRawOp Splice$$arr: [{d: 1, i: []}, 1]
            receiveFromServer Splice$$arr: [{i: ['q'], d: 1}, 1]
            expect( image() ).toEqual deepFreeze
                arr: ['q', 'b']
            
        it 'should allow merging of splices', ->
            createArray()
            so.commitRawOp Splice$$arr: [{d: 1, i: ['x']}, 1]
            receiveFromServer Splice$$arr: [1, {d: 1, i: ['y']}]
            expect( image() ).toEqual deepFreeze
                arr: ['x', 'y']

        it 'should allow splice merging with trailing inserts', ->
            createArray()
            so.commitRawOp Splice$$arr: [2, i: ['x'], d: 0]
            receiveFromServer Splice$$arr: [{d: 1, i: []}, 1]
            expect( image() ).toEqual deepFreeze
                arr: ['b', 'x']

        it 'should allow splice merging with overlaps', ->
            createArray()
            so.commitRawOp Splice$$arr: [1, {i: ['x'], d: 0}, {i: [], d: 1}]
            receiveFromServer Splice$$arr: [{d: 2, i: ['y']}]
            expect( image() ).toEqual deepFreeze
                arr: ['y', 'x']

        it 'should allow splicing of text', ->
            createString()
            so.commitRawOp Splice$$str: [1, {i: "", d: 3}, {i: 'ipp', d: 0}, 1]
            expect( image() ).toEqual deepFreeze
                str: 'Hippo'

        it 'should allow string splice merging', ->
            createString()
            so.commitRawOp Splice$$str: [3, {d: 2, i: 'p'}]
            receiveFromServer Splice$$str: [d: 1, i: 'Y', 4]
            expect( image() ).toEqual deepFreeze
                str: 'Yelp'

    it 'should allow string deletion', ->
        createString()
        so.commitRawOp Splice$$str: [1, {d: 3, i: ""}, 1]
        expect( image() ).toEqual deepFreeze
            str: 'Ho'

    it 'should reject Splices which are too short', ->
        createString()
        expect( ->
            so.commitRawOp Splice$$str: [1]
        ).toThrow()

    it 'should reject Splices which are too long', ->
        createString()
        expect( ->
            so.commitRawOp Splice$$str: [9]
        ).toThrow()

    it 'allows string insert via API', ->
        createString()
        so.at('str').insert(5, "!").commit()
        expect( image() ).toEqual deepFreeze
            str: 'Hello!'

    it 'allows string delete via API', ->
        createString()
        so.at('str').delete(4, 1).commit()
        expect( image() ).toEqual deepFreeze
            str: 'Hell'

    it 'allows array insert via API with array', ->
        createArray()
        so.at('arr').insert(1, ['x']).commit()
        expect( image() ).toEqual deepFreeze
            arr: ['a', 'x', 'b']

    it 'preserves arrays after index update', ->
        createArray()
        so.at('arr', 0).update('x').commit()
        expect( image() ).toEqual deepFreeze
            arr: ['x', 'b']
        expect( _.isArray(image().arr) ).toBe true


    it 'allows object set via API', ->
        createString()
        so.at('str')
               .update('newValue').commit()
        expect( image() ).toEqual deepFreeze
            str: 'newValue'

    it 'allows Append', ->
        createString()
        so.at('str').append(' world').commit()
        expect( image() ).toEqual deepFreeze
            str: 'Hello world'

    it 'correctly processes two array inserts', ->
        createArray()
        so.at('arr')
          .insert(0, ['^'])
          .append(['$'])
          .commit()
        expect( image() ).toEqual deepFreeze
            arr: ['^', 'a', 'b', '$']

    it 'can transpose two insert operations', ->
        createArray()
        so.at('arr').insert(0, ['x'])
                    .insert(0, ['y'])
                    .commit()
        expect( image() ).toEqual deepFreeze
            arr: ['x', 'y', 'a', 'b']

    it 'can transpose two splices ending in inserts', ->
        createArray()
        so.at('arr').insert(2, ['x'])
                    .insert(2, ['y'])
                    .commit()
        expect( image() ).toEqual deepFreeze
            arr: ['a', 'b', 'x', 'y' ]


    it 'has an API which rejects illegal calls', ->
        createString()
        b = so.at('str')
        expect(-> b.insert "Not here", 3, "s").toThrow()
        expect(-> b.insert 6, "s").toThrow()
        expect(-> b.insert 5, ['s']).toThrow()

    it 'can undefine properties via the API', ->
        so = O.create()
        so.at('a').update(1).commit()
        expect( so.image().a ).toBe 1
        so.at('a').update(undefined).commit()
        expect( so.image().a ).toBe undefined

    it 'should allow being moved by exterior splices', ->
        createArray() # [a, b]
        path = so.at('arr').at(1)
        expect( path.image() ).toEqual 'b'
        so.at('arr').insert(0, ['^']).commit()
        expect( path.image() ).toEqual 'b'

    it 'should transpose over local and server updates', ->
        createArray()
        path = so.at('arr', 1)
        expect( path.image() ).toEqual 'b'
        receiveFromServer(
            Splice$$arr: [{i: ['^'], d: 0}, 2]
        )
        expect( path.image() ).toEqual 'b'

    it 'should invalidate the path on delete', ->
        createArray()
        path = so.at('arr', 0)
        expect( path.isValid() ).toBe true
        so.at('arr').delete(0, 2).commit()
        expect( path.isValid() ).toBe false
        expect( -> path.image() ).toThrow 'Path invalidated by other operations'

    it 'should invalidate the path on update', ->
        createArray()
        path = so.at('arr', 0)
        expect( path.isValid() ).toBe true
        so.at('arr').update(['x', 'y']).commit()
        expect( path.isValid() ).toBe false
        expect( -> path.image() ).toThrow 'Path invalidated by other operations'

    it 'should not invalidate the path on colocated update', ->
        createArray()
        path = so.at('arr', 0)
        expect( path.isValid() ).toBe true
        so.at('arr', 0).update('x').commit()
        expect( path.isValid() ).toBe true
        #expect( path.image() ).toBe 'x'

    it 'should transpose over deep paths', ->
        so.at('arr').update([{myObj: ['hello' ] }]).commit()
        path = so.at('arr', 0, 'myObj', 0)
        expect( path.image() ).toBe 'hello'
        so.at('arr').insert(0, ['x']).commit()
        expect( path.image() ).toBe 'hello'

    it 'should transpose over diverging paths', ->
        so.at('arr').update([
            ['a', 'b'],
            ['x', 'y']
        ]).commit()
        path = so.at('arr', 1, 0)
        expect( path.image() ).toBe 'x'
        so.at('arr', 0).append(['c']).commit()
        expect( path.image() ).toBe 'x'

    it 'should operate indepedently from other SOs', ->
        so1 = O.create()
        so1.at('arr').update('a').commit()
        so2 = O.create()
        so2.at('arr').update('b').commit()
        expect( so1.at('arr').image() ).toBe 'a'
        expect( so2.at('arr').image() ).toBe 'b'

    it 'should delete properties that are updated to null', ->
        so.at('x').update(1).commit()
        expect( so.image().x ).toEqual 1
        so.at('x').update(null).commit()
        #expect( so.image() ).toEqual undefined

    it 'should allow paths to survive updates', ->
        path = so.at('here')
        path.update("a").commit()
        expect( path.image() ).toBe "a"

    it 'should allow use of addRawOp with paths', ->
        path = so.at('here')
        path.update({}).commit()
        path = path.at('there')
        path.update(everywhere: {prop: 'value'}).commit()
        path.addRawOp(there: {everywhere: Update$$prop: 'value2'}).commit()
        expect( so.image() ).toEqual deepFreeze(
            {here: there: everywhere: {prop: 'value2'}}
        )

    # TODO move somewhere more appropriate
    #it 'should bind to scope', ->
        #path = O.create().at('users')
        #path.update([]).commit()
        #scope = rootScope.$new()
        #path.bindToScope(scope, 'users')
        #path.update([1]).commit()
        #expect( scope.users ).toEqual [1]


    # TODO
    xit 'should deregister listeners on invalidation', ->

    describe 'should allow composition of ops', ->
        it 'for disjoint JSON ops', ->
            path = O.create()
            path.at('a').update(1)
            path.at('b').update(2)
            path.commit()
            expect( path.image() ).toEqual deepFreeze(
                {a: 1, b: 2}
            )

        it 'for splice ops', ->
            path = O.create()
            path.at('a').update([]).commit()
            path.at('a').append([1])
            path.at('a').append([2])
            path.commit()
            expect( path.image() ).toEqual deepFreeze(
                a: [1, 2]
            )

    describe 'on receiving an image update from the server', ->

        it 'should set the server image', ->
            wsCallback JSON.stringify(
                image: { a: 1 }
                history: []
                historyStart: 5
            )
            expect( so.image() ).toEqual deepFreeze( a: 1 )
            expect( so.vs() ).toBe 5

            so.at('a').update(2).commit()
            expect( so.vs() ).toBe 6

        it 'should preserve local commits when server history sent', ->

            # Put the system into a state with one local commit, and no server commits
            so.at('a').update(3).commit()
            localCommit = localCommits()[0]

            # State comes from server with a different commit
            serverCommit =
                vs: 0
                author: 221
                created: 4823
                op:
                    Update$$b: 4

            wsCallback JSON.stringify(
                image: {}
                history: [serverCommit]
                historyStart: 0
            )

            expect( image() ).toEqual deepFreeze { a: 3, b: 4 }
            expect( serverImage() ).toEqual ( b: 4 )
            expect( localCommits().length ).toEqual 1

        it 'ignore local commits in image updates from the server', ->

            # Put the system into a state with one local commit, and no server commits
            so.at('a').update(3).commit()
            localCommit = localCommits()[0]

            # State comes from server already including local commit
            wsCallback JSON.stringify(
                image: {}
                history: [localCommit]
                historyStart: 0
            )

            expect( image() ).toEqual deepFreeze( a: 3 )
            expect( serverImage() ).toEqual ( a: 3 )
            expect( localCommits().length ).toEqual 0

    describe 'Op API', ->
        it 'should retrieve subops with at', ->
            so.onChange (image, op) ->
                expect( op.at('a').opType ).toBe 'Update'
                expect( op.at('a').value  ).toBe 1
            so.at('a').update(1).commit()

        it 'should retrieve all subops keys with keys', ->
            so.onChange (image, op) ->
                expect( _.sortBy(op.keys(), _.identity) ).toEqual(['a', 'b'])
            so.at('a').update(1)
            so.at('b').update(2)
              .commit()

        it 'should allow using at to descend into updates', ->
            so.onChange (image, op) ->
                expect( op.at('c').at('u').opType ).toBe 'Update'
            so.at('c').update(
                u: 'hi'
                v: 'bye'
            ).commit()
