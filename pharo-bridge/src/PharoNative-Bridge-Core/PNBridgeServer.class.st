"
I am PNBridgeServer, a localhost TCP server that exposes a JSON-RPC 2.0 API
into the running Pharo image. The native macOS PharoNativeBrowser.app talks
to me to populate its System Browser without going through Morphic.

Wire format: newline-delimited JSON. Each request and each response is one
line of JSON terminated by a single LF.

A single instance is kept on the class side and is started on demand via
#ensureRunning. Multiple concurrent connections are supported; each is
served by its own forked Process.

Public class API
   PNBridgeServer ensureRunning  ""returns the listening port""
   PNBridgeServer port           ""nil if not running""
   PNBridgeServer stop

Implementation notes
   - The listening socket is opened on port 0 so the OS picks a free port;
     the chosen port is then recorded in Port.
   - The listener loops accepting connections and forks a worker process per
     connection. The worker reads lines, parses them as JSON-RPC, dispatches
     to PNBridgeHandlers, and writes a JSON response line back.
   - All dispatch happens off the UI process so the Morphic event loop is
     unaffected.
"
Class {
	#name : 'PNBridgeServer',
	#superclass : 'Object',
	#instVars : [
		'listener',
		'listenerProcess',
		'port',
		'handlers',
		'workerProcesses'
	],
	#classVars : [
		'Default'
	],
	#category : 'PharoNative-Bridge-Core',
	#package : 'PharoNative-Bridge-Core'
}

{ #category : 'accessing' }
PNBridgeServer class >> default [

	^ Default ifNil: [ Default := self new ]
]

{ #category : 'control' }
PNBridgeServer class >> ensureRunning [
	"Make sure the singleton server is listening, return the port number."

	| server |
	server := self default.
	server isRunning ifFalse: [ server start ].
	^ server port
]

{ #category : 'accessing' }
PNBridgeServer class >> port [

	^ Default ifNotNil: [ Default port ]
]

{ #category : 'control' }
PNBridgeServer class >> stop [

	Default ifNotNil: [ Default stop. Default := nil ]
]

{ #category : 'initialization' }
PNBridgeServer >> initialize [

	super initialize.
	handlers := PNBridgeHandlers new.
	workerProcesses := OrderedCollection new
]

{ #category : 'testing' }
PNBridgeServer >> isRunning [

	^ listenerProcess isNotNil and: [ listenerProcess isTerminated not ]
]

{ #category : 'accessing' }
PNBridgeServer >> port [

	^ port
]

{ #category : 'private - dispatch' }
PNBridgeServer >> processRequest: requestDict [
	"Dispatch a parsed JSON-RPC request dictionary to the handlers.
	Returns a response dictionary suitable for JSON encoding."

	| method params id result |
	method := requestDict at: 'method' ifAbsent: [ nil ].
	params := requestDict at: 'params' ifAbsent: [ Dictionary new ].
	id := requestDict at: 'id' ifAbsent: [ nil ].
	method ifNil: [
		^ self
			  responseForId: id
			  error: -32600
			  message: 'Invalid Request: missing method' ].
	[ result := handlers dispatch: method with: params ]
		on: Error
		do: [ :ex |
			^ self
				  responseForId: id
				  error: -32603
				  message: ex messageText ifNil: [ ex class name ] ].
	^ Dictionary new
		  at: 'jsonrpc' put: '2.0';
		  at: 'id' put: id;
		  at: 'result' put: result;
		  yourself
]

{ #category : 'private - dispatch' }
PNBridgeServer >> responseForId: id error: code message: messageString [

	| errDict |
	errDict := Dictionary new
		           at: 'code' put: code;
		           at: 'message' put: (messageString ifNil: [ 'error' ]);
		           yourself.
	^ Dictionary new
		  at: 'jsonrpc' put: '2.0';
		  at: 'id' put: id;
		  at: 'error' put: errDict;
		  yourself
]

{ #category : 'private - workers' }
PNBridgeServer >> serveConnection: aSocket [
	"Read JSON lines from aSocket, dispatch them, and write JSON response
	lines back. Returns (closing the connection) when the peer disconnects.
	Idle connections must be kept alive: a UI sitting on a method source
	view can go minutes without sending another request."

	| stream |
	stream := SocketStream on: aSocket.
	"Disable the default per-read timeout (default is ~30 s); a long-lived
	editor session may legitimately sit idle for a long time. We rely on
	socket-level connection close to detect a dead peer."
	stream timeout: 365 * 24 * 3600.
	[
	[ aSocket isConnected or: [ aSocket isOtherEndClosed ] ] whileTrue: [
		| line trimmed |
		line := [ stream nextLineLf ]
			        on: Error
			        do: [ :ex |
				        (ex isKindOf: ConnectionTimedOut)
					        ifTrue: [ '' ]
					        ifFalse: [ ^ self ] ].
		line ifNil: [ ^ self ].
		trimmed := line trimRight.
		trimmed ifNotEmpty: [ self handleLine: trimmed on: stream ] ] ]
		ensure: [
			[ stream close ] on: Error do: [ :ignored | ].
			[ aSocket destroy ] on: Error do: [ :ignored | ] ]
]

{ #category : 'private - workers' }
PNBridgeServer >> handleLine: aJsonString on: aStream [
	"Parse one JSON line, dispatch it, and write a single response line."

	| response |
	response := [
	             | request |
	             request := STONJSON fromString: aJsonString.
	             self processRequest: request ]
		            on: Error
		            do: [ :ex |
			            self
				            responseForId: nil
				            error: -32700
				            message: 'Parse error: ' , (ex messageText ifNil: [ ex class name ]) ].
	[
	aStream
		nextPutAll: (STONJSON toString: response);
		nextPutAll: String lf;
		flush ]
		on: Error
		do: [ :ignored | ]
]

{ #category : 'control' }
PNBridgeServer >> start [
	"Open a TCP listener on a free port and start accepting connections."

	listener := Socket newTCP.
	listener listenOn: 0 backlogSize: 4 interface: NetNameResolver loopBackAddress.
	port := listener localPort.
	listenerProcess := [ self runListenerLoop ]
		                   forkAt: Processor userBackgroundPriority
		                   named:
		                   'PNBridgeServer listener on port ' , port asString
]

{ #category : 'private - workers' }
PNBridgeServer >> runListenerLoop [
	"Accept connections forever and fork a worker process for each.
	#waitForAcceptFor:ifClosed:ifTimedOut: returns the accepted Socket on
	success, or nil from one of the blocks otherwise."

	[
	[ listener isValid ] whileTrue: [
		| client |
		client := listener
			          waitForAcceptFor: 60
			          ifClosed: [ nil ]
			          ifTimedOut: [ nil ].
		client ifNotNil: [
			| workerProcess |
			workerProcess := [ self serveConnection: client ]
				                 forkAt: Processor userBackgroundPriority
				                 named:
				                 'PNBridgeServer worker for ' , port asString.
			workerProcesses add: workerProcess ] ] ]
		ensure: [
			[ listener destroy ] on: Error do: [ :ignored | ].
			port := nil ]
]

{ #category : 'control' }
PNBridgeServer >> stop [

	listenerProcess ifNotNil: [
		[ listenerProcess terminate ] on: Error do: [ :ignored | ].
		listenerProcess := nil ].
	listener ifNotNil: [
		[ listener destroy ] on: Error do: [ :ignored | ].
		listener := nil ].
	workerProcesses do: [ :p |
		[ p terminate ] on: Error do: [ :ignored | ] ].
	workerProcesses := OrderedCollection new.
	port := nil
]
