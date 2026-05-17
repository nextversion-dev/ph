"
PNAutoStart bridges launcher scripts to the running Pharo image. It
serves two roles, both keyed off small filesystem markers:

  /tmp/pn-launch-native   -- one-shot startup marker. When the session
                             begins and this file exists, PNAutoStart
                             consumes it and opens a PNSystemBrowser.
                             Used by scripts/launch-native.sh on a fresh
                             image launch.

  /tmp/pn-trigger         -- runtime trigger. A forked watcher process
                             polls for this file every second. When it
                             appears the watcher deletes it and opens
                             a PNSystemBrowser. Used by
                             scripts/launch-native.sh when Pharo is
                             already running (in which case `open -a`
                             just refocuses the existing instance and
                             the startup hook never fires).

Both markers ensure the launcher does the right thing regardless of
whether the image is being started fresh or only refocused.
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

{ #category : 'accessing' }
PNAutoStart class >> triggerPath [

	^ '/tmp/pn-trigger'
]

{ #category : 'system startup' }
PNAutoStart class >> shutDown: quitting [
	"Nothing to do on shutdown; the watcher process is killed by the
	session manager along with all other non-resumable processes."
]

{ #category : 'system startup' }
PNAutoStart class >> startUp: isImageLaunching [
	"Fires once per session start. On a fresh image launch we also check
	the one-shot marker so scripts/launch-native.sh can open the native
	browser before the user sees anything."

	isImageLaunching ifFalse: [ ^ self ].
	"Drop any stale PNAppKitAdaptor singleton carried over in the image's
	class variables. Its sockets and reader process are dead after the
	save/resume cycle and would otherwise be reused, silently."
	[ PNAppKitAdaptor reset ] on: Error do: [ :ignored | ].
	self consumeStartupMarker.
	self installTriggerWatcher
]

{ #category : 'private' }
PNAutoStart class >> consumeStartupMarker [
	"If the one-shot marker is present, delete it and open a native
	browser ~500 ms later (Morphic finishes initialising first)."

	| marker |
	marker := self markerPath asFileReference.
	marker exists ifFalse: [ ^ self ].
	[ marker delete ] on: Error do: [ :ignored | ].
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

{ #category : 'private' }
PNAutoStart class >> installTriggerWatcher [
	"Fork a long-running poll watcher that opens a native browser when
	a trigger file appears. The watcher restarts itself on every image
	launch via #startUp:."

	[ self triggerWatcherLoop ]
		forkAt: Processor userBackgroundPriority
		named: 'PNAutoStart trigger watcher'
]

{ #category : 'private' }
PNAutoStart class >> triggerWatcherLoop [
	"Poll /tmp/pn-trigger once per second. When it appears, consume the
	file and open a native browser. Errors per iteration are swallowed
	so a transient FS hiccup never silently kills the watcher."

	[ true ] whileTrue: [
		[
		| trigger |
		trigger := self triggerPath asFileReference.
		trigger exists ifTrue: [
			[ trigger delete ] on: Error do: [ :ignored | ].
			[ PNSystemBrowser open ]
				on: Error
				do: [ :ex |
					Transcript
						show: 'PNAutoStart trigger: ';
						show: ex messageText;
						cr ] ] ]
			on: Error
			do: [ :ignored | ].
		(Delay forSeconds: 1) wait ]
]
