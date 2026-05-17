"
PNAutoStart is a SessionManager startup hook that opens a native System
Browser at image launch when a marker file is present. It lets launcher
scripts pick whether the image starts up plain (Morphic only) or with
the native UI already on screen, without modifying the saved image
between launches.

The marker file lives at `/tmp/pn-launch-native`. If it exists when the
image starts up, PNAutoStart forks a short-delayed `PNSystemBrowser open`
so the native window appears alongside Morphic. The marker is consumed
(deleted) immediately so a stale marker can't surprise later launches.

Launcher scripts:
   scripts/launch-morphic.sh -> deletes the marker, opens the image
   scripts/launch-native.sh   -> touches the marker, opens the image
"
Class {
	#name : 'PNAutoStart',
	#superclass : 'Object',
	#category : 'PharoNative-AppKit-Tools',
	#package : 'PharoNative-AppKit-Tools'
}

{ #category : 'class initialization' }
PNAutoStart class >> initialize [

	SessionManager default registerUserClassNamed: self name
]

{ #category : 'accessing' }
PNAutoStart class >> markerPath [

	^ '/tmp/pn-launch-native'
]

{ #category : 'system startup' }
PNAutoStart class >> shutDown: quitting [
	"Nothing to do on shutdown; we have no per-instance state."
]

{ #category : 'system startup' }
PNAutoStart class >> startUp: isImageLaunching [
	"Fires once per session start. When isImageLaunching is false the
	image is resuming from a save, in which case our marker is stale by
	definition. When true, check the marker and consume it."

	| marker |
	isImageLaunching ifFalse: [ ^ self ].
	marker := self markerPath asFileReference.
	marker exists ifFalse: [ ^ self ].
	[ marker delete ] on: Error do: [ :ignored | ].
	"Brief delay so Morphic, settings, etc. have finished their own
	startUp: hooks before we ask the bridge to spawn PharoNativeShell."
	[
	(Delay forMilliseconds: 500) wait.
	[ PNSystemBrowser open ]
		on: Error
		do: [ :ex |
			Transcript
				show: 'PNAutoStart: failed to open PNSystemBrowser: ';
				show: ex messageText;
				cr ] ]
		forkAt: Processor userBackgroundPriority
		named: 'PNAutoStart open'
]
