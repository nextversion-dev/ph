"
Wrapper for NSView. Used as a container in v1; subview is the one supported
child role.
"
Class {
	#name : 'PNNSView',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSView class >> widgetTypeName [

	^ 'NSView'
]

{ #category : 'children' }
PNNSView >> addSubview: aWidget [

	self addChild: aWidget role: 'subview'
]
