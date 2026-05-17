"
Wrapper for NSScrollView. Wraps any view (typically an NSTableView or
NSTextView) as scrollable content.
"
Class {
	#name : 'PNNSScrollView',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSScrollView class >> widgetTypeName [

	^ 'NSScrollView'
]

{ #category : 'properties' }
PNNSScrollView >> hasVerticalScroller: aBoolean [

	^ self setProp: 'hasVerticalScroller' value: aBoolean
]

{ #category : 'properties' }
PNNSScrollView >> hasHorizontalScroller: aBoolean [

	^ self setProp: 'hasHorizontalScroller' value: aBoolean
]

{ #category : 'properties' }
PNNSScrollView >> borderType: aString [
	"One of 'none', 'line', 'bezel', 'groove'."

	^ self setProp: 'borderType' value: aString
]

{ #category : 'children' }
PNNSScrollView >> documentView: aWidget [
	"Assign aWidget (typically a PNNSTableView or PNNSTextView) as the
	scroll view's document. NSScrollView accepts exactly one document view;
	calling this twice replaces the previous document on the shell side."

	^ self addChild: aWidget role: 'documentView'
]
