"
Wrapper for NSTableView. v2 ships a simple bulk-replace row API: send
all rows at once via #rows:; the shell calls reloadData(). This is fine
for System Browser sizes (<= ~600 rows per table). Lazy/streaming row
delivery is a future optimisation.

Typical usage:
   table columns: { { 'title' -> 'Packages'. 'identifier' -> 'name' } asDictionary }.
   table rows: { #( 'Foo' ). #( 'Bar' ) }.
   table onSelectionChanged: [ :row | Transcript show: row asString; cr ].
"
Class {
	#name : 'PNNSTableView',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSTableView class >> widgetTypeName [

	^ 'NSTableView'
]

{ #category : 'properties' }
PNNSTableView >> columns: anArrayOfDictionaries [
	"Each entry is a Dictionary with keys 'title', 'identifier'
	(defaults to 'title'), and optional 'width'."

	^ self setProp: 'columns' value: anArrayOfDictionaries asArray
]

{ #category : 'properties' }
PNNSTableView >> rows: anArrayOfArrays [
	"Replace all rows. Each entry is an array of strings, one per column.
	Strings will be #asString'd here so passing Symbols or other display
	values is convenient."

	| materialised |
	materialised := anArrayOfArrays collect: [ :row |
		                row isString
			                ifTrue: [ Array with: row ]
			                ifFalse: [
			                row asArray collect: [ :cell | cell asString ] ] ].
	^ self setProp: 'rows' value: materialised asArray
]

{ #category : 'properties' }
PNNSTableView >> selectedRow: anInteger [
	"Programmatic selection. Pass -1 to deselect."

	^ self setProp: 'selectedRow' value: anInteger
]

{ #category : 'properties' }
PNNSTableView >> usesAlternatingRowBackgroundColors: aBoolean [

	^ self setProp: 'usesAlternatingRowBackgroundColors' value: aBoolean
]

{ #category : 'events' }
PNNSTableView >> onSelectionChanged: aBlock [
	"aBlock takes a single argument: the selected row index, or -1 if
	the user deselected. The block runs in a forked worker process so it
	is free to make further widget RPCs without deadlocking."

	self subscribe: 'selectionChanged' do: [ :payload |
		aBlock value: (payload at: 'row' ifAbsent: [ -1 ]) ]
]
