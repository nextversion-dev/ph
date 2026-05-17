"
Wrapper for NSTextField. Default appearance is a non-editable, non-bordered
label; toggle #editable: and #bordered: to use it as a single-line input.
"
Class {
	#name : 'PNNSTextField',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSTextField class >> widgetTypeName [

	^ 'NSTextField'
]

{ #category : 'properties' }
PNNSTextField >> stringValue: aString [

	^ self setProp: 'stringValue' value: aString
]

{ #category : 'properties' }
PNNSTextField >> editable: aBoolean [

	^ self setProp: 'editable' value: aBoolean
]

{ #category : 'properties' }
PNNSTextField >> bordered: aBoolean [

	^ self setProp: 'bordered' value: aBoolean
]
