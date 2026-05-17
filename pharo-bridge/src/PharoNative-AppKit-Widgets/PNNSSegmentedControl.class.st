"
Wrapper for NSSegmentedControl in select-one mode (radio-button row).
Set the labels via #segments:, observe via #onSelectionChanged: -- the
block receives both the index (0-based) and the label string.
"
Class {
	#name : 'PNNSSegmentedControl',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSSegmentedControl class >> widgetTypeName [

	^ 'NSSegmentedControl'
]

{ #category : 'properties' }
PNNSSegmentedControl >> segments: anArrayOfStrings [
	"Replace the segment labels."

	^ self
		  setProp: 'segments'
		  value: (anArrayOfStrings collect: [ :s | s asString ]) asArray
]

{ #category : 'properties' }
PNNSSegmentedControl >> selectedSegment: anInteger [
	"Programmatic selection. Pass -1 to clear."

	^ self setProp: 'selectedSegment' value: anInteger
]

{ #category : 'properties' }
PNNSSegmentedControl >> selectedSegment [

	^ (self getProp: 'selectedSegment') ifNil: [ -1 ]
]

{ #category : 'events' }
PNNSSegmentedControl >> onSelectionChanged: aBlock [
	"aBlock takes two arguments: the index and the label of the
	freshly-selected segment."

	self subscribe: 'selectionChanged' do: [ :payload |
		aBlock
			value: (payload at: 'index' ifAbsent: [ -1 ])
			value: (payload at: 'label' ifAbsent: [ '' ]) ]
]
