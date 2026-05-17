"
Baseline for the PharoNative bridge packages. Provides a single Metacello
entry point that loads:

   PharoNative-Bridge-Core      (server, JSON-RPC dispatcher, handlers)
   PharoNative-Bridge-MenuHook  (World menu integration)

Usage (from the command line):

   Pharo Pharo.image st pharo-bridge/scripts/install.st --save --quit

or directly in a workspace:

   Metacello new
       baseline: 'PharoNativeBridge';
       repository: 'tonel:///path/to/pharo-bridge/src';
       load.
"
Class {
	#name : 'BaselineOfPharoNativeBridge',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfPharoNativeBridge',
	#package : 'BaselineOfPharoNativeBridge'
}

{ #category : 'baseline' }
BaselineOfPharoNativeBridge >> baseline: spec [

	<baseline>
	spec for: #common do: [
		"v1 fat-client bridge (System Browser data API)."
		spec package: 'PharoNative-Bridge-Core'.
		spec
			package: 'PharoNative-Bridge-MenuHook'
			with: [ spec requires: 'PharoNative-Bridge-Core' ].

		"Pharo-driven widget protocol (VAST/VW-style)."
		spec package: 'PharoNative-AppKit-Adaptor'.
		spec
			package: 'PharoNative-AppKit-Widgets'
			with: [ spec requires: 'PharoNative-AppKit-Adaptor' ].
		spec
			package: 'PharoNative-AppKit-Examples'
			with: [ spec requires: 'PharoNative-AppKit-Widgets' ].
		spec
			package: 'PharoNative-AppKit-Tools'
			with: [ spec requires: 'PharoNative-AppKit-Widgets' ] ]
]
