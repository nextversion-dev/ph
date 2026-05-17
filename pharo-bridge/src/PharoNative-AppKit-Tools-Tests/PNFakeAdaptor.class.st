"
PNFakeAdaptor is a no-network stand-in for PNAppKitAdaptor used in
PNSystemBrowserTest. It records every JSON-RPC `call:` / `notify:` so
tests can assert against the widget commands that would have been sent
to the shell, and it lets tests fire synthetic events through the same
dispatch path that real shell notifications use.

It is *not* an adaptor in the literal sense; it overrides the singleton
API of PNAppKitAdaptor so that all PNAppKitWidget instances created
during a test see a controlled fake instead of a real TCP connection.
"
Class {
	#name : 'PNFakeAdaptor',
	#superclass : 'PNAppKitAdaptor',
	#instVars : [
		'calls',
		'eventHandlersByKey',
		'fakeIdCounter'
	],
	#category : 'PharoNative-AppKit-Tools-Tests',
	#package : 'PharoNative-AppKit-Tools-Tests'
}

{ #category : 'testing utility' }
PNFakeAdaptor class >> useDuring: aBlock [
	"Install a fresh fake as PNAppKitAdaptor default for the duration of
	aBlock, restoring whatever was there afterwards. The block receives
	the fake instance as its first argument."

	| previous fake |
	previous := PNAppKitAdaptor classVarNamed: #Default.
	fake := self new.
	PNAppKitAdaptor classVarNamed: #Default put: fake.
	^ [ aBlock value: fake ] ensure: [
		  PNAppKitAdaptor classVarNamed: #Default put: previous ]
]

{ #category : 'initialization' }
PNFakeAdaptor >> initialize [

	"Skip the real adaptor's super initialize which would create a mutex
	plus pending-call infrastructure we don't need."
	calls := OrderedCollection new.
	eventHandlersByKey := Dictionary new.
	fakeIdCounter := 0
]

{ #category : 'accessing' }
PNFakeAdaptor >> calls [
	"All recorded (method -> params) pairs in send order."

	^ calls
]

{ #category : 'accessing' }
PNFakeAdaptor >> callsOfMethod: aMethodName [
	"Subset of calls whose method name matches aMethodName."

	^ calls select: [ :each | (each at: 'method') = aMethodName ]
]

{ #category : 'accessing' }
PNFakeAdaptor >> reset [
	"Clear the recording so a single test phase can isolate the calls
	it cares about."

	calls := OrderedCollection new.
	eventHandlersByKey := Dictionary new
]

{ #category : 'public' }
PNFakeAdaptor >> call: aMethodName params: aDict [
	"Record the call and return a benign synthetic response. For
	widget.getProp we answer { value: nil } so callers don't NPE; every
	other verb returns { ok: true }."

	calls add: (Dictionary new
			 at: 'method' put: aMethodName;
			 at: 'params' put: aDict;
			 yourself).
	aMethodName = 'widget.getProp' ifTrue: [
		^ Dictionary new at: 'value' put: nil; yourself ].
	^ Dictionary new at: 'ok' put: true; yourself
]

{ #category : 'public' }
PNFakeAdaptor >> notify: aMethodName params: aDict [

	calls add: (Dictionary new
			 at: 'method' put: aMethodName;
			 at: 'params' put: aDict;
			 yourself)
]

{ #category : 'public' }
PNFakeAdaptor >> onEvent: aWidgetId named: anEventSymbol do: aBlock [

	eventHandlersByKey
		at: aWidgetId , '/' , anEventSymbol asString
		put: aBlock
]

{ #category : 'public' }
PNFakeAdaptor >> offEvent: aWidgetId [

	| prefix |
	prefix := aWidgetId , '/'.
	(eventHandlersByKey keys select: [ :k | k beginsWith: prefix ])
		do: [ :k | eventHandlersByKey removeKey: k ifAbsent: [ nil ] ]
]

{ #category : 'public' }
PNFakeAdaptor >> nextWidgetId [

	fakeIdCounter := fakeIdCounter + 1.
	^ 'fake-' , fakeIdCounter asString
]

{ #category : 'testing utility' }
PNFakeAdaptor >> fireEvent: aWidgetId named: anEventSymbol payload: aDict [
	"Synthetically deliver an event the same way the real adaptor would
	from its reader process. Looks up the registered handler and invokes
	it synchronously (no fork) so tests can assert immediately."

	| key handler |
	key := aWidgetId , '/' , anEventSymbol asString.
	handler := eventHandlersByKey at: key ifAbsent: [ ^ self ].
	handler value: aDict
]
