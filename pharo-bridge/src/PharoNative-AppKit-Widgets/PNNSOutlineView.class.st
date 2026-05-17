"
Wrapper for NSOutlineView. Pharo ships a forest of items via `items:`,
each item a Dictionary with keys:

   id        String -- unique within this widget
   label     String -- display text
   children  Array of items (optional; absent or empty for leaves)

Selection is by item id. Programmatic selection / expansion is also by id.

Typical use:
   outline := PNNSOutlineView new.
   outline columns: { (Dictionary new
                        at: 'title' put: 'Packages';
                        at: 'identifier' put: 'name';
                        yourself) }.
   outline items: { ... forest ... }.
   outline onSelectionChanged: [ :id | self handlePackageSelected: id ].

The shell preserves expansion state across an #items: refresh whenever
the same id reappears, so a filter-driven re-set won't collapse open
branches.
"
Class {
	#name : 'PNNSOutlineView',
	#superclass : 'PNAppKitWidget',
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'wire' }
PNNSOutlineView class >> widgetTypeName [

	^ 'NSOutlineView'
]

{ #category : 'properties' }
PNNSOutlineView >> columns: anArrayOfDictionaries [
	"Same shape as PNNSTableView columns. Single-column trees are the
	common case; pass a one-element array."

	^ self setProp: 'columns' value: anArrayOfDictionaries asArray
]

{ #category : 'properties' }
PNNSOutlineView >> items: anArrayOfDictionaries [
	"Replace the tree contents with the given forest. Each item is a
	Dictionary with at least 'id' and 'label' keys; 'children' is
	optional. Expansion state is preserved for ids that reappear in
	the new tree."

	^ self setProp: 'items' value: anArrayOfDictionaries asArray
]

{ #category : 'properties' }
PNNSOutlineView >> selectedItem: anIdOrNil [

	^ self setProp: 'selectedItem' value: anIdOrNil
]

{ #category : 'properties' }
PNNSOutlineView >> expandItems: anArrayOfIds [
	"Expand the rows whose ids are listed. Useful right after #items:
	to open the top-level rows by default."

	^ self setProp: 'expandedItems' value: anArrayOfIds asArray
]

{ #category : 'events' }
PNNSOutlineView >> onSelectionChanged: aBlock [
	"aBlock takes one argument: the id of the selected item, or nil
	when nothing is selected."

	self subscribe: 'selectionChanged' do: [ :payload |
		aBlock value: (payload at: 'id' ifAbsent: [ nil ]) ]
]
