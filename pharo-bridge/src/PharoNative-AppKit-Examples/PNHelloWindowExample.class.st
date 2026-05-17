"
v1 smoke test for the Pharo-driven widget protocol.

Opens a native NSWindow containing an NSTextField (label) and an NSButton.
Clicking the button updates the label to show the current time. Closing
the window cleans up the wrappers on both sides.

Run from a Playground:
   PNHelloWindowExample open
"
Class {
	#name : 'PNHelloWindowExample',
	#superclass : 'Object',
	#category : 'PharoNative-AppKit-Examples',
	#package : 'PharoNative-AppKit-Examples'
}

{ #category : 'examples' }
PNHelloWindowExample class >> open [

	| window label button |
	window := PNNSWindow new
		          title: 'Hello from Pharo';
		          contentSize: 320 @ 160;
		          yourself.

	label := PNNSTextField new
		         stringValue: 'click the button';
		         editable: false;
		         bordered: false;
		         frame: (10 @ 100 extent: 300 @ 24);
		         yourself.

	button := PNNSButton new
		          title: 'Press me';
		          frame: (110 @ 40 extent: 100 @ 32);
		          yourself.
	button onClicked: [
		label
			stringValue:
			'clicked at ' , DateAndTime now asTime print24 ].

	window contentView
		addSubview: label;
		addSubview: button.

	window onWillClose: [
		button destroy.
		label destroy.
		window destroy ].

	window show.
	^ window
]
