"
Wrapper for NSTabView. Add tabs by sending #addTab:title: with a child
widget and a title string -- the widget becomes the tab's content view.

Typical use:
   tabs := PNNSTabView new.
   tabs
      addTab: sourceContainer title: 'Source';
      addTab: hierarchyView title: 'Hierarchy'.
   tabs onTabSelected: [ :index :title |
      title = 'Hierarchy' ifTrue: [ self refreshHierarchy ] ].

The tab title is encoded into the addChild role string as
`'tab:<title>'`. Pick titles that don't contain raw colons; if you
need a colon, escape it on both sides (out of scope here).
"
Class {
	#name : 'PNNSTabView',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSTabView class >> widgetTypeName [

	^ 'NSTabView'
]

{ #category : 'properties' }
PNNSTabView >> selectedIndex: anInteger [

	^ self setProp: 'selectedIndex' value: anInteger
]

{ #category : 'children' }
PNNSTabView >> addTab: aChildWidget title: aTitle [
	"Append a tab labelled aTitle whose content view is aChildWidget."

	^ self addChild: aChildWidget role: 'tab:' , aTitle asString
]

{ #category : 'events' }
PNNSTabView >> onTabSelected: aBlock [
	"aBlock takes two arguments: the index of the newly-selected tab and
	its title string."

	self subscribe: 'tabSelected' do: [ :payload |
		aBlock
			value: (payload at: 'index' ifAbsent: [ -1 ])
			value: (payload at: 'title' ifAbsent: [ '' ]) ]
]
