"
Signalled by PNAppKitAdaptor when the shell returns a JSON-RPC error
response. Carries the numeric code from the shell alongside the standard
exception message.
"
Class {
	#name : 'PNAppKitRpcError',
	#superclass : 'Error',
	#instVars : [
		'code'
	],
	#category : 'PharoNative-AppKit-Adaptor',
	#package : 'PharoNative-AppKit-Adaptor'
}

{ #category : 'accessing' }
PNAppKitRpcError >> code [

	^ code
]

{ #category : 'accessing' }
PNAppKitRpcError >> code: anInteger [

	code := anInteger
]
