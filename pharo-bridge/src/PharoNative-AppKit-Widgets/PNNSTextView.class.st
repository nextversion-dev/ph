"
Wrapper for NSTextView. v2 ships read-only display of plain text plus
optional colored runs via #attributedRuns:. Editing comes in a later
iteration with a debounced commit protocol.
"
Class {
	#name : 'PNNSTextView',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSTextView class >> widgetTypeName [

	^ 'NSTextView'
]

{ #category : 'properties' }
PNNSTextView >> string: aString [
	"Replace the text view's contents."

	^ self setProp: 'string' value: aString asString
]

{ #category : 'properties' }
PNNSTextView >> string [
	"Read the text view's current contents back from the shell. Useful
	when the user has edited the field; pair with #editable: true."

	^ (self getProp: 'string') ifNil: [ '' ]
]

{ #category : 'properties' }
PNNSTextView >> attributedRuns: anArrayOfRunDictionaries [
	"Apply colored runs on top of the current string. Each run is a
	Dictionary with keys 'location' (Int), 'length' (Int), and
	'foreground' (named color: 'red', 'green', 'blue', 'purple', 'teal',
	'orange', 'yellow', 'pink', 'gray', 'label')."

	^ self setProp: 'attributedRuns' value: anArrayOfRunDictionaries asArray
]

{ #category : 'properties' }
PNNSTextView >> editable: aBoolean [

	^ self setProp: 'editable' value: aBoolean
]

{ #category : 'properties' }
PNNSTextView >> font: aFamilyAndSize [
	"Pass a Dictionary { 'family' -> 'Menlo'. 'size' -> 13 } asDictionary."

	^ self setProp: 'font' value: aFamilyAndSize
]
