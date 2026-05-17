"
Wrapper for NSSplitView. `vertical: true` draws a vertical divider with
horizontally-arranged children, matching AppKit's NSSplitView semantics.
Use `addArrangedSubview:` to populate, and `dividerPositions:` to set
divider offsets along the split axis.
"
Class {
	#name : 'PNNSSplitView',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSSplitView class >> widgetTypeName [

	^ 'NSSplitView'
]

{ #category : 'properties' }
PNNSSplitView >> vertical: aBoolean [

	^ self setProp: 'vertical' value: aBoolean
]

{ #category : 'properties' }
PNNSSplitView >> dividerStyle: aString [
	"One of 'thin', 'thick', 'paneSplitter'."

	^ self setProp: 'dividerStyle' value: aString
]

{ #category : 'properties' }
PNNSSplitView >> dividerPositions: anArrayOfNumbers [
	"Apply divider offsets, in order, along the split axis. Applied on the
	next runloop tick on the shell so the split view has finished its
	initial layout."

	^ self setProp: 'dividerPositions' value: anArrayOfNumbers asArray
]

{ #category : 'children' }
PNNSSplitView >> addArrangedSubview: aWidget [

	^ self addChild: aWidget role: 'arrangedSubview'
]
