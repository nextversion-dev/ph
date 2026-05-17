"
I register a 'Native System Browser' entry in the World menu under the
existing Browse group. Selecting it makes sure PNBridgeServer is running,
captures the chosen port, and execs the macOS helper app via 'open -a'.

The helper app path can be overridden via the class-side App Path setting.
The default location is computed relative to the Pharo image directory and
points at PharoNativeBrowser.app inside the pharo-native-browser/build
folder of this repository.
"
Class {
	#name : 'PNWorldMenu',
	#superclass : 'Object',
	#classVars : [
		'AppPath'
	],
	#category : 'PharoNative-Bridge-MenuHook',
	#package : 'PharoNative-Bridge-MenuHook'
}

{ #category : 'accessing' }
PNWorldMenu class >> appPath [

	^ AppPath ifNil: [ self defaultAppPath ]
]

{ #category : 'accessing' }
PNWorldMenu class >> appPath: aStringOrNil [

	AppPath := aStringOrNil
]

{ #category : 'accessing' }
PNWorldMenu class >> defaultAppPath [
	"Default location of the macOS helper app, computed relative to the
	image directory. We expect this image to live in
	<repo>/pharo/build/bootstrap-cache/, so the helper app is two levels
	up at <repo>/pharo-native-browser/build/PharoNativeBrowser.app."

	^ (FileLocator imageDirectory parent parent parent
	   / 'pharo-native-browser' / 'build' / 'PharoNativeBrowser.app')
		  fullName
]

{ #category : 'actions' }
PNWorldMenu class >> openNativeBrowser [
	"Ensure the bridge is up and launch the native helper app with the
	port number as a command-line argument."

	| port appPath command |
	port := PNBridgeServer ensureRunning.
	appPath := self appPath.
	"Build: open -a <appPath> --args --port=<port>
	The shell quoting matters because the user's repo path can contain
	spaces."
	command := String streamContents: [ :s |
		           s nextPutAll: 'open -a '.
		           s nextPutAll: (self shellQuote: appPath).
		           s nextPutAll: ' --args --port='.
		           s print: port ].
	LibC system: command
]

{ #category : 'utility' }
PNWorldMenu class >> shellQuote: aString [
	"Single-quote a string for /bin/sh, escaping any embedded single quotes."

	^ String streamContents: [ :s |
		  s nextPut: $'.
		  aString do: [ :ch |
			  ch = $'
				  ifTrue: [ s nextPutAll: '''"''"''' ]
				  ifFalse: [ s nextPut: ch ] ].
		  s nextPut: $' ]
]

{ #category : 'world menu' }
PNWorldMenu class >> worldMenuOn: aBuilder [

	<worldMenu>
	(aBuilder item: #'Native System Browser')
		parent: #Browsing;
		action: [ self openNativeBrowser ];
		order: 1;
		help: 'Open the System Browser in a native macOS window (PharoNativeBrowser.app).';
		iconName: #smallSystemBrowser
]
