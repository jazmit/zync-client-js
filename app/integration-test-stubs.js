// Stuff to make setTimeout work

var Timer = Java.type('java.util.Timer');
var Phaser = Java.type('java.util.concurrent.Phaser');
var TimeUnit = Java.type('java.util.concurrent.TimeUnit');
var onTaskFinished = function() {
    phaser.arriveAndDeregister();
};

var timer = new Timer('jsEventLoop', false);
var phaser = new Phaser();

function setTimeout(fn, millis) {
    var args = [].slice.call(arguments, 2, arguments.length);

    var phase = phaser.register();
    var canceled = false;
    timer.schedule(function() {
    if (canceled) {
        return;
    }

    try {
        fn.apply(context, args);
    } catch (e) {
        print(e);
    } finally {
        onTaskFinished();
    }
    }, millis);

    return function() {
        onTaskFinished();
        canceled = true;
    };
};

// Logger api
var Logger = {
  get: function() {
    return {
      debug:   function() {},
      info:    print,
      warning: print
    };
  }
};

// Websocket API
var WebSocket = {
  OPEN: 0,
  CLOSED: 1
};

var receiveFromServer = null

function fakeWebSocket() {
    this.readyState = WebSocket.OPEN;
    this.send = function(message) {
        print("sending "+message)
        javaCallbacks.sendToServer(message)
    };
    var me = this
    receiveFromServer = function(message) {
        me.onmessage({data: message})
    }
};


var wsRouter = WSFactory({websocket: "x"}, fakeWebSocket);

var schemata = {
    data: {
        "name" : "data",
        "vs" : "0.0.1",
        "schema": {
            "name": "dict",
            "subtype": {
                "name": "any"
            }
        }
    }
}
Zync = _.extend(Zync, ZyncFactory(wsRouter, schemata))
var z = null

function doSubscribe() {
    z = Zync.fetch('data', 'b1cde155-54d7-4dcb-b891-a40d10471fdc')
    z.onChange(function(image) {
        javaCallbacks.onChange(JSON.stringify(image))
    });
};

function commitRawOp(op) {
    print("Op is " + op)
    z.run(function() {
        z.commitRawOp(JSON.parse(op))
    })
}
