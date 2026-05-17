"
I am PNAppKitAdaptor, the singleton bridge between this Pharo image and a
PharoNativeShell.app process. I am the Pharo-side analog of VisualWorks's
WindowSystemAdaptor / VAST's Common Widgets adaptor.

On first use I:
   1. pick a free TCP port (bind a Socket to port 0, read localPort, close).
   2. spawn PharoNativeShell.app via `LibC system:`, passing --port=N.
   3. connect a SocketStream to 127.0.0.1:N, retrying for up to ~5 s while
      the shell is starting up.
   4. fork a reader process that consumes one JSON line at a time and
      routes by shape:
         - lines with `id` and `result`/`error` complete a pending request.
         - lines with `method` and no `id` are event notifications and are
           dispatched to handlers registered with #onEvent:named:do:.

Public API:
   PNAppKitAdaptor default                  ""the singleton, lazy-started""
   adaptor call: aMethodName params: aDict  ""synchronous request""
   adaptor notify: aMethodName params: aDict ""fire-and-forget""
   adaptor onEvent: widgetId named: anEventSymbol do: aBlock
   adaptor offEvent: widgetId
   adaptor nextWidgetId                     ""'w-NNN' suitable for widget.create""
   adaptor stop

I do not try to model AppKit. The wrapper classes in
PharoNative-AppKit-Widgets do that on top of me.
"
Class {
	#name : 'PNAppKitAdaptor',
	#superclass : 'Object',
	#instVars : [
		'socket',
		'stream',
		'readerProcess',
		'pendingMutex',
		'pending',
		'nextId',
		'idCounter',
		'eventHandlers',
		'shellPort'
	],
	#classVars : [
		'Default'
	],
	#category : 'PharoNative-AppKit-Adaptor',
	#package : 'PharoNative-AppKit-Adaptor'
}

{ #category : 'accessing' }
PNAppKitAdaptor class >> default [

	^ Default ifNil: [
		  Default := self new.
		  Default ensureStarted.
		  Default ]
]

{ #category : 'control' }
PNAppKitAdaptor class >> reset [

	Default ifNotNil: [
		[ Default stop ] on: Error do: [ :ignored | ].
		Default := nil ]
]

{ #category : 'accessing' }
PNAppKitAdaptor class >> shellAppPath [
	"Location of PharoNativeShell.app relative to the image directory.
	Mirrors PNWorldMenu>>defaultAppPath: <repo>/pharo-native-shell/build/
	PharoNativeShell.app, where <repo> is image.parent.parent.parent."

	^ (FileLocator imageDirectory parent parent parent
	   / 'pharo-native-shell' / 'build' / 'PharoNativeShell.app')
		  fullName
]

{ #category : 'initialization' }
PNAppKitAdaptor >> initialize [

	super initialize.
	pendingMutex := Mutex new.
	pending := Dictionary new.
	eventHandlers := Dictionary new.
	idCounter := 0.
	nextId := 1
]

{ #category : 'public' }
PNAppKitAdaptor >> call: aMethodName params: aDict [
	"Send a JSON-RPC request and block until the response arrives.
	Answer the parsed result Dictionary or signal a PNAppKitRpcError."

	| id semaphore answer requestDict |
	self ensureStarted.
	id := pendingMutex critical: [ | x | x := nextId. nextId := nextId + 1. x ].
	semaphore := Semaphore new.
	pendingMutex critical: [
		pending at: id put: { semaphore. nil } ].
	requestDict := Dictionary new
		               at: 'jsonrpc' put: '2.0';
		               at: 'id' put: id;
		               at: 'method' put: aMethodName;
		               at: 'params' put: aDict;
		               yourself.
	self writeJsonLine: (STONJSON toString: requestDict).
	semaphore wait.
	answer := pendingMutex critical: [ (pending removeKey: id ifAbsent: [ nil ]) ].
	answer ifNil: [ ^ self error: 'Lost pending entry for id ' , id asString ].
	(answer at: 2) ifNotNil: [ :err |
		| code msg |
		code := err at: 'code' ifAbsent: [ -1 ].
		msg := err at: 'message' ifAbsent: [ 'unknown error' ].
		^ PNAppKitRpcError new code: code; messageText: msg; signal ].
	^ answer at: 3
]

{ #category : 'public' }
PNAppKitAdaptor >> notify: aMethodName params: aDict [
	"Send a fire-and-forget JSON-RPC notification (no id, no response).
	Currently unused, kept for parity with future event-driven flows."

	| requestDict |
	self ensureStarted.
	requestDict := Dictionary new
		               at: 'jsonrpc' put: '2.0';
		               at: 'method' put: aMethodName;
		               at: 'params' put: aDict;
		               yourself.
	self writeJsonLine: (STONJSON toString: requestDict)
]

{ #category : 'public' }
PNAppKitAdaptor >> onEvent: aWidgetId named: anEventSymbol do: aBlock [
	"Register a block to be invoked when the shell emits the named event
	for the given widget id. Replaces any prior handler for the same pair."

	| key |
	key := aWidgetId , '/' , anEventSymbol asString.
	pendingMutex critical: [ eventHandlers at: key put: aBlock ]
]

{ #category : 'public' }
PNAppKitAdaptor >> offEvent: aWidgetId [
	"Drop all event handlers attached to a widget. Called when the wrapper
	is destroyed."

	pendingMutex critical: [
		| prefix |
		prefix := aWidgetId , '/'.
		(eventHandlers keys select: [ :k | k beginsWith: prefix ])
			do: [ :k | eventHandlers removeKey: k ifAbsent: [ nil ] ] ]
]

{ #category : 'public' }
PNAppKitAdaptor >> nextWidgetId [

	^ pendingMutex critical: [
		  idCounter := idCounter + 1.
		  'w-' , idCounter asString ]
]

{ #category : 'control' }
PNAppKitAdaptor >> ensureStarted [
	"Start the shell process and connect to it if we have not already.
	If an existing shell is reachable via the port file it writes on
	startup, reuse that instead of spawning a duplicate -- otherwise
	macOS's auto-relaunch of PharoNativeShell.app gives us a stale shell
	on a different port that `open -a` cannot redirect."

	(stream isNotNil and: [ stream isConnected ]) ifTrue: [ ^ self ].
	(self tryConnectToExistingShell)
		ifTrue: [ ^ self startReader ].
	self startShell.
	self connect.
	self startReader
]

{ #category : 'control' }
PNAppKitAdaptor >> tryConnectToExistingShell [
	"If /tmp/pharo-native-shell.port exists and we can reach the port it
	names within 200 ms, hook up to that shell. Otherwise tear down and
	answer false so the caller can spawn a fresh shell."

	| portFile content port |
	portFile := '/tmp/pharo-native-shell.port' asFileReference.
	portFile exists ifFalse: [ ^ false ].
	content := [ portFile contents asString trimBoth ]
		           on: Error
		           do: [ :ignored | '' ].
	port := [ content asNumber asInteger ]
		        on: Error
		        do: [ :ignored | 0 ].
	(port isNil or: [ port = 0 ]) ifTrue: [ ^ false ].
	^ [
	  socket := Socket newTCP.
	  socket
		  connectTo: NetNameResolver localHostAddress
		  port: port.
	  socket waitForConnectionFor: 1.
	  socket isConnected
		  ifTrue: [
			  shellPort := port.
			  stream := SocketStream on: socket.
			  stream timeout: 365 * 24 * 3600.
			  true ]
		  ifFalse: [
			  socket destroy.
			  socket := nil.
			  false ] ]
		  on: Error
		  do: [ :ignored |
			  [ socket ifNotNil: [ :s | s destroy ] ]
				  on: Error
				  do: [ :ig | ].
			  socket := nil.
			  false ]
]

{ #category : 'control' }
PNAppKitAdaptor >> startShell [
	"Pick a free port, exec the shell with --port=N, store the port."

	| probe port command |
	probe := Socket newTCP.
	probe listenOn: 0 backlogSize: 1 interface: NetNameResolver loopBackAddress.
	port := probe localPort.
	probe destroy.
	shellPort := port.
	command := String streamContents: [ :s |
		           s nextPutAll: 'open -a '.
		           s nextPutAll: (self shellQuote: self class shellAppPath).
		           s nextPutAll: ' --args --port='.
		           s print: port ].
	LibC system: command
]

{ #category : 'private' }
PNAppKitAdaptor >> shellQuote: aString [
	"Single-quote a string for /bin/sh, escaping any embedded single quotes
	per the standard ''\\\\''''  trick (close quote, escaped quote, reopen)."

	^ String streamContents: [ :s |
		  s nextPut: $'.
		  aString do: [ :ch |
			  ch = $'
				  ifTrue: [ s nextPutAll: '''"''"''' ]
				  ifFalse: [ s nextPut: ch ] ].
		  s nextPut: $' ]
]

{ #category : 'control' }
PNAppKitAdaptor >> connect [
	"Connect to the shell, retrying up to 5 s while it starts up."

	| deadline lastError |
	deadline := DateAndTime now + 5 seconds.
	lastError := nil.
	[ DateAndTime now < deadline ] whileTrue: [
		[
		socket := Socket newTCP.
		socket connectTo: NetNameResolver localHostAddress port: shellPort.
		socket waitForConnectionFor: 1.
		socket isConnected
			ifTrue: [
				stream := SocketStream on: socket.
				stream timeout: 365 * 24 * 3600.
				^ self ]
			ifFalse: [ socket destroy ] ]
			on: Error
			do: [ :ex |
				lastError := ex.
				[ socket ifNotNil: [ :s | s destroy ] ] on: Error do: [ :ignored | ] ].
		(Delay forMilliseconds: 100) wait ].
	^ self
		  error: 'PharoNativeShell did not become reachable on 127.0.0.1:'
		  , shellPort asString , ' within 5 s'
			  , (lastError ifNil: [ '' ] ifNotNil: [ :e | ' (' , e messageText , ')' ])
]

{ #category : 'control' }
PNAppKitAdaptor >> startReader [
	"Fork the line-reading process that handles responses and event
	notifications."

	readerProcess := [ self runReaderLoop ]
		                 forkAt: Processor userBackgroundPriority
		                 named: 'PNAppKitAdaptor reader'
]

{ #category : 'private' }
PNAppKitAdaptor >> runReaderLoop [
	"Read one JSON line at a time; dispatch by shape."

	[ stream isNotNil and: [ stream isConnected ] ] whileTrue: [
		| line trimmed parsed |
		line := [ stream nextLineLf ]
			        on: Error
			        do: [ :ex | ^ self ].
		line ifNil: [ ^ self ].
		trimmed := line trimRight.
		trimmed ifNotEmpty: [
			parsed := [ STONJSON fromString: trimmed ]
				          on: Error
				          do: [ :ex | nil ].
			parsed ifNotNil: [ self handleParsed: parsed ] ] ]
]

{ #category : 'private' }
PNAppKitAdaptor >> handleParsed: aDict [
	"Either a response (has id) or a notification (has method, no id)."

	| id |
	id := aDict at: 'id' ifAbsent: [ nil ].
	id ifNotNil: [ ^ self deliverResponse: aDict withId: id ].
	^ self deliverNotification: aDict
]

{ #category : 'private' }
PNAppKitAdaptor >> deliverResponse: aDict withId: idValue [
	"Wake up the requester waiting on this id."

	| key entry semaphore |
	key := idValue isString
		       ifTrue: [ idValue asNumber ]
		       ifFalse: [ idValue ].
	entry := pendingMutex critical: [ pending at: key ifAbsent: [ nil ] ].
	entry ifNil: [ ^ self ].
	pendingMutex critical: [
		pending at: key put: {
			(entry at: 1).
			(aDict at: 'error' ifAbsent: [ nil ]).
			(aDict at: 'result' ifAbsent: [ nil ]) } ].
	semaphore := entry at: 1.
	semaphore signal
]

{ #category : 'private' }
PNAppKitAdaptor >> deliverNotification: aDict [
	"Dispatch a shell -> Pharo event notification to the registered block."

	| method params widgetId eventName payload key handler |
	method := aDict at: 'method' ifAbsent: [ nil ].
	method = 'event' ifFalse: [ ^ self ].
	params := aDict at: 'params' ifAbsent: [ ^ self ].
	widgetId := params at: 'id' ifAbsent: [ ^ self ].
	eventName := params at: 'event' ifAbsent: [ ^ self ].
	payload := params at: 'payload' ifAbsent: [ Dictionary new ].
	key := widgetId , '/' , eventName.
	handler := pendingMutex critical: [ eventHandlers at: key ifAbsent: [ nil ] ].
	handler ifNil: [ ^ self ].
	"Run handler asynchronously so reader loop is never blocked by a slow
	user block; also so that the block can itself make RPC calls."
	[
	[ handler value: payload ] on: Error do: [ :ex |
		Transcript
			show: 'PNAppKitAdaptor event handler error: ';
			show: ex messageText;
			cr ] ]
		forkAt: Processor userBackgroundPriority
		named: 'PNAppKitAdaptor handler ' , key
]

{ #category : 'private' }
PNAppKitAdaptor >> writeJsonLine: aString [
	"Single-line JSON + LF, flushed."

	pendingMutex critical: [
		stream
			nextPutAll: aString;
			nextPutAll: String lf;
			flush ]
]

{ #category : 'control' }
PNAppKitAdaptor >> stop [
	"Disconnect from the shell and wake any pending requests. The shell
	process keeps running so subsequent opens are instant; quit it from its
	app menu if you want it gone."

	readerProcess ifNotNil: [
		[ readerProcess terminate ] on: Error do: [ :ignored | ].
		readerProcess := nil ].
	stream ifNotNil: [
		[ stream close ] on: Error do: [ :ignored | ].
		stream := nil ].
	socket ifNotNil: [
		[ socket destroy ] on: Error do: [ :ignored | ].
		socket := nil ].
	pendingMutex critical: [
		pending valuesDo: [ :entry | (entry at: 1) signal ].
		pending := Dictionary new ]
]
