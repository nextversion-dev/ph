"
Registers the Pharo-driven System Browser as a World menu entry. Sits at
order: 2 under #Browsing, below the v1 fat-client entry at order 1, so
both are visible during the migration and we can compare them.
"
Class {
	#name : 'PNToolsMenu',
	#superclass : 'Object',
	#category : 'PharoNative-AppKit-Tools',
	#package : 'PharoNative-AppKit-Tools'
}

{ #category : 'world menu' }
PNToolsMenu class >> worldMenuOn: aBuilder [

	<worldMenu>
	(aBuilder item: #'Native System Browser (Pharo-driven)')
		parent: #Browsing;
		action: [ PNSystemBrowser open ];
		order: 2;
		help:
			'Open the System Browser as native AppKit widgets driven entirely by Pharo (VAST/VW-style peer widgets).';
		iconName: #smallSystemBrowser
]
