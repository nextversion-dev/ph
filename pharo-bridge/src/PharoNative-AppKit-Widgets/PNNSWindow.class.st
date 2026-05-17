"
Wrapper for NSWindow. Owns an automatically-created PNNSView as its content
view so common subview layouts work without an explicit container step.

Typical use:
   | win label |
   win := PNNSWindow new title: 'Hi'; contentSize: 320 @ 160; yourself.
   label := PNNSTextField new stringValue: 'hello'; frame: (10 @ 80 extent: 300 @ 24); yourself.
   win contentView addSubview: label.
   win show.
"
Class {
	#name : 'PNNSWindow',
	#superclass : 'PNAppKitWidget',
	#instVars : [
		'contentView'
	],
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSWindow class >> widgetTypeName [

	^ 'NSWindow'
]

{ #category : 'initialization' }
PNNSWindow >> createOnShell [
	"Create the window then attach a fresh NSView as its content view so
	the user can immediately addSubview: things."

	super createOnShell.
	contentView := PNNSView new.
	self addChild: contentView role: 'contentView'
]

{ #category : 'accessing' }
PNNSWindow >> contentView [

	^ contentView
]

{ #category : 'properties' }
PNNSWindow >> title: aString [

	^ self setProp: 'title' value: aString
]

{ #category : 'properties' }
PNNSWindow >> contentSize: aPoint [

	^ self
		setProp: 'contentSize'
		value: (Dictionary new
				 at: 'w' put: aPoint x;
				 at: 'h' put: aPoint y;
				 yourself)
]

{ #category : 'actions' }
PNNSWindow >> show [
	"Make the window key and bring it to the front."

	^ self invoke: 'makeKeyAndOrderFront'
]

{ #category : 'actions' }
PNNSWindow >> close [

	^ self invoke: 'close'
]

{ #category : 'events' }
PNNSWindow >> onWillClose: aBlock [
	"Run aBlock when the user closes the window. aBlock takes no
	arguments (the payload Dictionary is passed but typically ignored)."

	self subscribe: 'willClose' do: [ :payload | aBlock value ]
]

{ #category : 'lifecycle' }
PNNSWindow >> destroy [
	"Also tear down the implicit content view."

	contentView ifNotNil: [
		[ contentView destroy ] on: Error do: [ :ignored | ].
		contentView := nil ].
	super destroy
]
