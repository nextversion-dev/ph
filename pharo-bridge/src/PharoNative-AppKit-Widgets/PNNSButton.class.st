"
Wrapper for NSButton (push button style).
"
Class {
	#name : 'PNNSButton',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSButton class >> widgetTypeName [

	^ 'NSButton'
]

{ #category : 'properties' }
PNNSButton >> title: aString [

	^ self setProp: 'title' value: aString
]

{ #category : 'properties' }
PNNSButton >> enabled: aBoolean [

	^ self setProp: 'enabled' value: aBoolean
]

{ #category : 'events' }
PNNSButton >> onClicked: aBlock [

	self subscribe: 'clicked' do: [ :payload | aBlock value ]
]
