"
A System Browser whose entire UI logic lives in Pharo. AppKit only renders
what we tell it to. This is the Pharo-driven counterpart to the v1
fat-client PharoNativeBrowser.app: the layout and selection cascade are
the same, but everything from window construction through the
package/class/protocol/method queries down to source assembly happens in
this image, in this class, hot-reloadable like any other Smalltalk code.

Open via:
   PNSystemBrowser open
"
Class {
	#name : 'PNSystemBrowser',
	#superclass : 'Object',
	#instVars : [
		'window',
		'outerSplit',
		'topSplit',
		'packagesScroll',
		'classesScroll',
		'protocolsScroll',
		'methodsScroll',
		'sourceContainer',
		'sourceScroll',
		'sourceToolbar',
		'acceptButton',
		'statusLabel',
		'packagesTable',
		'classesTable',
		'protocolsTable',
		'methodsTable',
		'sourceTextView',
		'packages',
		'classes',
		'protocols',
		'methods',
		'selectedPackage',
		'selectedClass',
		'selectedProtocol',
		'selectedMethod'
	],
	#category : 'PharoNative-AppKit-Tools',
	#package : 'PharoNative-AppKit-Tools'
}

{ #category : 'opening' }
PNSystemBrowser class >> open [

	^ self new openWindow
]

{ #category : 'opening' }
PNSystemBrowser >> openWindow [

	self buildWindow.
	self wireSelectionHandlers.
	self populatePackages.
	window show.
	"NSSplitView ignores #setPosition:ofDividerAt: until the split has
	performed at least one layout pass. Set the divider AFTER the window
	is on screen so the position takes effect."
	outerSplit dividerPositions: #( 420 ).
	^ self
]

{ #category : 'building' }
PNSystemBrowser >> buildWindow [
	"Create the wrapper tree:
		window
		  outerSplit (vertical divider, horizontal arrangement) -- wait,
		  actually NSSplitView.isVertical = false stacks vertically. We want
		  the source pane below the lists, so outerSplit is non-vertical.
		    topSplit (isVertical=true, four columns)
		      packagesScroll -> packagesTable
		      classesScroll  -> classesTable
		      protocolsScroll -> protocolsTable
		      methodsScroll  -> methodsTable
		    sourceScroll -> sourceTextView"

	window := PNNSWindow new
		          title: 'Pharo System Browser (Pharo-driven)';
		          contentSize: 1100 @ 720;
		          yourself.

	outerSplit := PNNSSplitView new
		              vertical: false;
		              dividerStyle: 'thin';
		              yourself.

	topSplit := PNNSSplitView new
		            vertical: true;
		            dividerStyle: 'thin';
		            yourself.

	packagesTable := self buildSingleColumnTable: 'Packages'.
	classesTable := self buildSingleColumnTable: 'Classes'.
	protocolsTable := self buildSingleColumnTable: 'Protocols'.
	methodsTable := self buildSingleColumnTable: 'Methods'.

	packagesScroll := PNNSScrollView new
		                  borderType: 'none';
		                  documentView: packagesTable;
		                  yourself.
	classesScroll := PNNSScrollView new
		                 borderType: 'none';
		                 documentView: classesTable;
		                 yourself.
	protocolsScroll := PNNSScrollView new
		                   borderType: 'none';
		                   documentView: protocolsTable;
		                   yourself.
	methodsScroll := PNNSScrollView new
		                 borderType: 'none';
		                 documentView: methodsTable;
		                 yourself.

	"Seed initial frames so NSSplitView has reasonable size hints for the
	first layout pass; the dividerPositions: call after `show` then nails
	the final divider position. AppKit also propagates the inner split's
	width across the four columns as long as their initial widths are
	non-zero."
	packagesScroll frame: (0 @ 0 extent: 275 @ 420).
	classesScroll frame: (275 @ 0 extent: 275 @ 420).
	protocolsScroll frame: (550 @ 0 extent: 275 @ 420).
	methodsScroll frame: (825 @ 0 extent: 275 @ 420).
	topSplit frame: (0 @ 300 extent: 1100 @ 420).
	topSplit
		addArrangedSubview: packagesScroll;
		addArrangedSubview: classesScroll;
		addArrangedSubview: protocolsScroll;
		addArrangedSubview: methodsScroll.

	sourceTextView := PNNSTextView new
		                  editable: true;
		                  string: '';
		                  yourself.
	sourceScroll := PNNSScrollView new
		                borderType: 'none';
		                hasVerticalScroller: true;
		                documentView: sourceTextView;
		                frame: (0 @ 36 extent: 1100 @ 264);
		                autoresizingMask: #( width height );
		                yourself.

	"Toolbar pinned to the bottom of the source pane: Accept button on
	the left, status label that fills the remaining width and reports
	the result of the last save."
	acceptButton := PNNSButton new
		                title: 'Accept';
		                frame: (8 @ 4 extent: 100 @ 28);
		                yourself.
	statusLabel := PNNSTextField new
		               stringValue: '';
		               editable: false;
		               bordered: false;
		               frame: (118 @ 8 extent: 974 @ 22);
		               autoresizingMask: #( width );
		               yourself.
	sourceToolbar := PNNSView new
		                 frame: (0 @ 0 extent: 1100 @ 36);
		                 autoresizingMask: #( width );
		                 yourself.
	sourceToolbar
		addSubview: acceptButton;
		addSubview: statusLabel.

	sourceContainer := PNNSView new
		                   frame: (0 @ 0 extent: 1100 @ 300);
		                   yourself.
	sourceContainer
		addSubview: sourceScroll;
		addSubview: sourceToolbar.

	outerSplit frame: (0 @ 0 extent: 1100 @ 720).
	outerSplit
		addArrangedSubview: topSplit;
		addArrangedSubview: sourceContainer.

	window contentView addSubview: outerSplit.
	"Let the split grow with the window's content view."
	outerSplit fillSuperview.

	window onWillClose: [ self destroyAll ]
]

{ #category : 'building' }
PNSystemBrowser >> buildSingleColumnTable: aTitle [
	"Build a single-column table. We use a non-empty identifier so the
	shell looks up cell values correctly; the header is hidden by the
	shell when there is one column with an empty title, but a column
	identifier of 'name' is what we use to populate cells."

	| table |
	table := PNNSTableView new.
	table columns: { (Dictionary new
				  at: 'title' put: aTitle;
				  at: 'identifier' put: 'name';
				  yourself) }.
	^ table
]

{ #category : 'wiring' }
PNSystemBrowser >> wireSelectionHandlers [

	packagesTable
		onSelectionChanged: [ :row | self packageRowSelected: row ].
	classesTable
		onSelectionChanged: [ :row | self classRowSelected: row ].
	protocolsTable
		onSelectionChanged: [ :row | self protocolRowSelected: row ].
	methodsTable
		onSelectionChanged: [ :row | self methodRowSelected: row ].
	acceptButton onClicked: [ self acceptSource ]
]

{ #category : 'editing' }
PNSystemBrowser >> acceptSource [
	"Read the current source from the native text view and compile it
	into the selected behavior under the selected protocol, then write
	the updated class back to its Tonel source file on disk so the
	change survives a fresh image bootstrap. Surfaces every kind of
	error through the status label."

	| behavior protocolName source result wroteToDisk diskNote |
	behavior := self behaviorForSelectedClass.
	behavior ifNil: [
		statusLabel stringValue: 'no class selected'.
		^ self ].
	protocolName := selectedProtocol
		                ifNotNil: [ selectedProtocol name asString ]
		                ifNil: [ 'as yet unclassified' ].
	source := [ sourceTextView string ]
		          on: Error
		          do: [ :ex |
			          statusLabel stringValue:
				          'failed to read source: ' , ex messageText.
			          nil ].
	source ifNil: [ ^ self ].
	result := [ behavior compile: source classified: protocolName ]
		          on: Error
		          do: [ :ex |
			          statusLabel stringValue:
				          'compile error: ' , ex messageText.
			          nil ].
	result ifNil: [ ^ self ].
	"#compile:classified: answers the new selector. If it changed
	(e.g. you renamed the method) make sure the method list reflects
	that, and re-select the freshly compiled method."
	selectedMethod := result.
	self populateMethods.

	"Persist to disk. Falling back to image-only when no Tonel repo
	covers the package keeps the existing in-image behaviour for
	packages that haven't been registered with a working copy."
	wroteToDisk := [ self writeBehaviorToTonel: behavior ]
		               on: Error
		               do: [ :ex | ex ].
	diskNote := wroteToDisk == true
		            ifTrue: [ ' (saved to disk)' ]
		            ifFalse: [
			            wroteToDisk == false
				            ifTrue: [ ' (image-only; no Tonel repo)' ]
				            ifFalse: [
				            ' (image-only; tonel error: '
				            , (wroteToDisk messageText ifNil: [ wroteToDisk class name asString ])
				            , ')' ] ].
	statusLabel
		stringValue:
		'saved: ' , behavior name asString , ' >> ' , result asString
		, diskNote.
	"Re-read from the image so any formatter normalisation shows up."
	self displaySelectedMethodSource
]

{ #category : 'editing' }
PNSystemBrowser >> writeBehaviorToTonel: aBehavior [
	"Convenience: forward to the class-side utility."

	^ self class writeBehaviorToTonel: aBehavior
]

{ #category : 'editing' }
PNSystemBrowser class >> writeBehaviorToTonel: aBehavior [
	"Rewrite aBehavior's Tonel source file from its current in-image
	state so edits made via the Accept button survive a fresh image
	bootstrap. Returns true on success, false if the package has no
	matching Tonel repository registered (i.e. nothing was written).
	Errors propagate so the caller can surface them.

	We find the right repository by walking
	MCRepositoryGroup default repositories looking for a
	TonelRepository whose directory contains the package's folder.
	Both pharo/src and pharo-bridge/src are registered by install.sh,
	so methods in any package living in either tree get persisted."

	| pkg snap classDef repo packageDir stream writer instanceSide fileName |
	instanceSide := aBehavior instanceSide.
	pkg := instanceSide package.
	pkg ifNil: [ ^ false ].
	snap := (MCPackage new name: pkg name) snapshot.
	classDef := snap definitions
		            detect: [ :d |
			            d isClassDefinition and: [
				            d className = instanceSide name asString ] ]
		            ifNone: [ nil ].
	classDef ifNil: [ ^ false ].
	repo := MCRepositoryGroup default repositories
		        detect: [ :r |
			        r class name == #TonelRepository and: [
				        (r directory / pkg name) exists ] ]
		        ifNone: [ nil ].
	repo ifNil: [ ^ false ].
	packageDir := repo directory / pkg name.
	fileName := classDef className , '.class.st'.
	stream := WriteStream on: String new.
	writer := TonelWriter new
		          snapshot: snap;
		          directoryReference: repo directory;
		          yourself.
	writer writeClass: classDef on: stream.
	"Truncate-and-write the file with UTF-8 bytes so the read side
	(TonelReader on UTF-8 streams) round-trips correctly."
	(packageDir / fileName) ensureDelete.
	(packageDir / fileName) binaryWriteStreamDo: [ :s |
		s nextPutAll: stream contents utf8Encoded ].
	^ true
]

{ #category : 'private' }
PNSystemBrowser >> displaySelectedMethodSource [

	| behavior method src |
	(selectedMethod isNil or: [ methods isEmpty ]) ifTrue: [
		sourceTextView string: ''.
		^ self ].
	behavior := self behaviorForSelectedClass.
	behavior ifNil: [ ^ self ].
	method := behavior
		          compiledMethodAt: selectedMethod asSymbol
		          ifAbsent: [ nil ].
	method ifNil: [
		sourceTextView string: ''.
		^ self ].
	src := [ method sourceCode ]
		       on: Error
		       do: [ :ex | '"source unavailable: ' , ex messageText , '"' ].
	sourceTextView string: src
]

{ #category : 'populating' }
PNSystemBrowser >> populatePackages [

	packages := (PackageOrganizer default packages
		             asSortedCollection: [ :a :b | a name < b name ])
		            asArray.
	packagesTable rows: (packages collect: [ :pkg |
			 Array with: pkg name asString , '  (' , pkg definedClasses size asString , ')' ])
]

{ #category : 'selection handlers' }
PNSystemBrowser >> packageRowSelected: aRowIndex [

	(aRowIndex < 0 or: [ aRowIndex >= packages size ]) ifTrue: [
		selectedPackage := nil.
		classesTable rows: #().
		protocolsTable rows: #().
		methodsTable rows: #().
		sourceTextView string: ''.
		^ self ].
	selectedPackage := packages at: aRowIndex + 1.
	self populateClasses.
	protocolsTable rows: #().
	methodsTable rows: #().
	sourceTextView string: ''
]

{ #category : 'populating' }
PNSystemBrowser >> populateClasses [
	"Show both instance- and class-sides for every class defined in the
	selected package, mirroring v1's layout."

	| sorted |
	classes := OrderedCollection new.
	sorted := selectedPackage definedClasses asSortedCollection: [ :a :b |
		          a name < b name ].
	sorted do: [ :each |
		classes add: { each. 'instance'. each name asString }.
		each classSide ifNotNil: [ :meta |
			meta hasMethods ifTrue: [
				classes add: { each. 'class'. each name asString , ' class' } ] ] ].
	classesTable rows:
		(classes collect: [ :entry | Array with: (entry at: 3) ])
]

{ #category : 'selection handlers' }
PNSystemBrowser >> classRowSelected: aRowIndex [

	(aRowIndex < 0 or: [ aRowIndex >= classes size ]) ifTrue: [
		selectedClass := nil.
		protocolsTable rows: #().
		methodsTable rows: #().
		sourceTextView string: ''.
		^ self ].
	selectedClass := classes at: aRowIndex + 1.
	self populateProtocols.
	"Default: show all methods until the user picks a protocol."
	selectedProtocol := nil.
	self populateMethods.
	sourceTextView string: ''
]

{ #category : 'populating' }
PNSystemBrowser >> populateProtocols [
	"selectedClass is { instanceSideClass. 'instance' | 'class'. displayName }."

	| behavior sorted |
	behavior := self behaviorForSelectedClass.
	behavior ifNil: [
		protocolsTable rows: #().
		^ self ].
	sorted := (behavior protocols asSortedCollection: [ :a :b |
		           a name asString < b name asString ]) asArray.
	protocols := sorted.
	protocolsTable rows: (sorted collect: [ :p |
			 Array with: p name asString , '  ('
			 , (behavior selectorsInProtocol: p name) size asString , ')' ])
]

{ #category : 'selection handlers' }
PNSystemBrowser >> protocolRowSelected: aRowIndex [

	(aRowIndex < 0 or: [ aRowIndex >= protocols size ])
		ifTrue: [ selectedProtocol := nil ]
		ifFalse: [ selectedProtocol := protocols at: aRowIndex + 1 ].
	self populateMethods.
	sourceTextView string: ''
]

{ #category : 'populating' }
PNSystemBrowser >> populateMethods [

	| behavior selectors |
	behavior := self behaviorForSelectedClass.
	behavior ifNil: [
		methods := #(  ).
		methodsTable rows: #().
		^ self ].
	selectors := selectedProtocol
		             ifNil: [ behavior selectors ]
		             ifNotNil: [
		             behavior selectorsInProtocol: selectedProtocol name ].
	methods := (selectors asSortedCollection: [ :a :b |
		            a asString < b asString ]) asArray.
	methodsTable rows: (methods collect: [ :sel | Array with: sel asString ])
]

{ #category : 'selection handlers' }
PNSystemBrowser >> methodRowSelected: aRowIndex [

	(aRowIndex < 0 or: [ aRowIndex >= methods size ]) ifTrue: [
		selectedMethod := nil.
		sourceTextView string: ''.
		statusLabel stringValue: ''.
		^ self ].
	selectedMethod := methods at: aRowIndex + 1.
	statusLabel stringValue: ''.
	self displaySelectedMethodSource
]

{ #category : 'private' }
PNSystemBrowser >> behaviorForSelectedClass [
	"selectedClass is the 3-element array we built in #populateClasses."

	selectedClass ifNil: [ ^ nil ].
	^ (selectedClass at: 2) = 'class'
		  ifTrue: [ (selectedClass at: 1) classSide ]
		  ifFalse: [ (selectedClass at: 1) instanceSide ]
]

{ #category : 'lifecycle' }
PNSystemBrowser >> destroyAll [
	"Tear down every wrapper. Called from the willClose handler. We
	swallow errors per-widget because a partly-destroyed tree must not
	prevent the rest from being cleaned up."

	#( acceptButton statusLabel sourceToolbar
	   sourceTextView sourceScroll sourceContainer
	   methodsTable methodsScroll
	   protocolsTable protocolsScroll
	   classesTable classesScroll
	   packagesTable packagesScroll
	   topSplit outerSplit window )
		do: [ :ivar |
			(self instVarNamed: ivar) ifNotNil: [ :w |
				[ w destroy ] on: Error do: [ :ignored | ].
				self instVarNamed: ivar put: nil ] ]
]
