"
Wrapper for NSSearchField. Same family as PNNSTextField but with the
native macOS search-field chrome (rounded background, magnifying glass,
clear button). The textChanged event fires per keystroke so callers
can drive a live filter cheaply.

Typical use in PNSystemBrowser:
   filter := PNNSSearchField new
                 placeholder: 'Filter packages';
                 onTextChanged: [ :text | self refilterPackages: text ];
                 yourself.
"
Class {
	#name : 'PNNSSearchField',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSSearchField class >> widgetTypeName [

	^ 'NSSearchField'
]

{ #category : 'properties' }
PNNSSearchField >> stringValue: aString [

	^ self setProp: 'stringValue' value: aString asString
]

{ #category : 'properties' }
PNNSSearchField >> stringValue [
	"Read back the current text content."

	^ (self getProp: 'stringValue') ifNil: [ '' ]
]

{ #category : 'properties' }
PNNSSearchField >> placeholder: aString [
	"Greyed-out hint shown when the field is empty."

	^ self setProp: 'placeholder' value: aString asString
]

{ #category : 'events' }
PNNSSearchField >> onTextChanged: aBlock [
	"aBlock takes one argument: the current full text. Fires on every
	keystroke, so the block is expected to be cheap (or to debounce
	expensive work itself)."

	self subscribe: 'textChanged' do: [ :payload |
		aBlock value: (payload at: 'text' ifAbsent: [ '' ]) ]
]
