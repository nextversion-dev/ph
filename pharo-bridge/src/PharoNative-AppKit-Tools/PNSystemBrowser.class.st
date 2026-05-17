"
A System Browser whose entire UI logic lives in Pharo. AppKit only renders
what we tell it to. This is the Pharo-driven counterpart to the v1
fat-client PharoNativeBrowser.app: the layout and selection cascade are
the same, but everything from window construction through the
package/class/protocol/method queries down to source assembly happens in
this image, in this class, hot-reloadable like any other Smalltalk code.

Iteration 2 visual surface:
  - Packages pane is an NSOutlineView: top-level rows are packages,
    each package's children are its PackageTags. Selecting a tag scopes
    the Classes pane to that tag.
  - Every pane has a NSSearchField filter input above it that does a
    case-insensitive substring match against the displayed names.

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
		'packagesPane',
		'classesPane',
		'protocolsPane',
		'methodsPane',
		'packagesFilter',
		'classesFilter',
		'protocolsFilter',
		'methodsFilter',
		'packagesScroll',
		'classesScroll',
		'protocolsScroll',
		'methodsScroll',
		'packagesOutline',
		'classesTable',
		'protocolsTable',
		'methodsTable',
		'sourceContainer',
		'sourceScroll',
		'sourceToolbar',
		'sourceTextView',
		'acceptButton',
		'statusLabel',
		'allPackages',
		'allClasses',
		'allProtocols',
		'allMethods',
		'displayedPackages',
		'displayedClasses',
		'displayedProtocols',
		'displayedMethods',
		'packageFilterText',
		'classFilterText',
		'protocolFilterText',
		'methodFilterText',
		'selectedPackage',
		'selectedTag',
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

	self initializeFilterState.
	self buildWindow.
	self wireSelectionHandlers.
	self loadPackages.
	window show.
	"NSSplitView ignores #setPosition:ofDividerAt: until the split has
	performed at least one layout pass. Set the divider AFTER the window
	is on screen so the position takes effect."
	outerSplit dividerPositions: #( 420 ).
	^ self
]

{ #category : 'initialization' }
PNSystemBrowser >> initializeFilterState [

	packageFilterText := ''.
	classFilterText := ''.
	protocolFilterText := ''.
	methodFilterText := ''.
	allPackages := #(  ).
	allClasses := #(  ).
	allProtocols := #(  ).
	allMethods := #(  ).
	displayedPackages := #(  ).
	displayedClasses := #(  ).
	displayedProtocols := #(  ).
	displayedMethods := #(  )
]

{ #category : 'building' }
PNSystemBrowser >> buildWindow [
	"Layout:
		window
		  outerSplit (horizontal divider, stacked top/bottom)
		    topSplit (vertical divider, four panes left-to-right)
		      packagesPane: filter input + scrolled NSOutlineView
		      classesPane / protocolsPane / methodsPane: same pattern
		        but with NSTableViews
		    sourceContainer
		      sourceScroll -> sourceTextView
		      sourceToolbar (Accept + status)"

	window := PNNSWindow new
		          title: 'Pharo System Browser (Pharo-driven)';
		          contentSize: 1100 @ 720;
		          yourself.

	packagesOutline := PNNSOutlineView new
		                   columns: { (Dictionary new
				                    at: 'title' put: 'Packages';
				                    at: 'identifier' put: 'name';
				                    yourself) };
		                   yourself.
	classesTable := self buildSingleColumnTable: 'Classes'.
	protocolsTable := self buildSingleColumnTable: 'Protocols'.
	methodsTable := self buildSingleColumnTable: 'Methods'.

	packagesScroll := self wrapInScroll: packagesOutline.
	classesScroll := self wrapInScroll: classesTable.
	protocolsScroll := self wrapInScroll: protocolsTable.
	methodsScroll := self wrapInScroll: methodsTable.

	packagesFilter := self buildFilterField: 'Filter packages'.
	classesFilter := self buildFilterField: 'Filter classes'.
	protocolsFilter := self buildFilterField: 'Filter protocols'.
	methodsFilter := self buildFilterField: 'Filter methods'.

	packagesPane := self buildPaneWith: packagesFilter scroll: packagesScroll.
	classesPane := self buildPaneWith: classesFilter scroll: classesScroll.
	protocolsPane := self buildPaneWith: protocolsFilter scroll: protocolsScroll.
	methodsPane := self buildPaneWith: methodsFilter scroll: methodsScroll.

	topSplit := PNNSSplitView new
		            vertical: true;
		            dividerStyle: 'thin';
		            frame: (0 @ 300 extent: 1100 @ 420);
		            yourself.
	"Seed each pane's frame so the inner NSSplitView distributes them
	evenly on the first layout pass."
	packagesPane frame: (0 @ 0 extent: 275 @ 420).
	classesPane frame: (275 @ 0 extent: 275 @ 420).
	protocolsPane frame: (550 @ 0 extent: 275 @ 420).
	methodsPane frame: (825 @ 0 extent: 275 @ 420).
	topSplit
		addArrangedSubview: packagesPane;
		addArrangedSubview: classesPane;
		addArrangedSubview: protocolsPane;
		addArrangedSubview: methodsPane.

	self buildSourcePane.

	outerSplit := PNNSSplitView new
		              vertical: false;
		              dividerStyle: 'thin';
		              frame: (0 @ 0 extent: 1100 @ 720);
		              yourself.
	outerSplit
		addArrangedSubview: topSplit;
		addArrangedSubview: sourceContainer.

	window contentView addSubview: outerSplit.
	outerSplit fillSuperview.

	window onWillClose: [ self destroyAll ]
]

{ #category : 'building' }
PNSystemBrowser >> buildSingleColumnTable: aTitle [

	| table |
	table := PNNSTableView new.
	table columns: { (Dictionary new
				 at: 'title' put: aTitle;
				 at: 'identifier' put: 'name';
				 yourself) }.
	^ table
]

{ #category : 'building' }
PNSystemBrowser >> wrapInScroll: aWidget [

	^ PNNSScrollView new
		  borderType: 'none';
		  hasVerticalScroller: true;
		  documentView: aWidget;
		  yourself
]

{ #category : 'building' }
PNSystemBrowser >> buildFilterField: aPlaceholder [

	^ PNNSSearchField new
		  placeholder: aPlaceholder;
		  yourself
]

{ #category : 'building' }
PNSystemBrowser >> buildPaneWith: aFilterField scroll: aScrollView [
	"Compose a single column-pane: a 28-tall search field anchored at
	the top, with the scroll view filling everything below it."

	| pane |
	pane := PNNSView new.
	"Default frame is 275 x 420; later overridden when added to topSplit."
	pane frame: (0 @ 0 extent: 275 @ 420).
	"Search field pinned to the top edge.  In an unflipped NSView,
	y grows upward, so minYMargin = flexible distance from BOTTOM,
	which keeps the field stuck to the top as the pane grows taller."
	aFilterField
		frame: (4 @ 388 extent: 267 @ 26);
		autoresizingMask: #( width minY ).
	"Scroll fills the rest."
	aScrollView
		frame: (0 @ 0 extent: 275 @ 380);
		autoresizingMask: #( width height ).
	pane addSubview: aScrollView; addSubview: aFilterField.
	^ pane
]

{ #category : 'building' }
PNSystemBrowser >> buildSourcePane [

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
		addSubview: sourceToolbar
]

{ #category : 'wiring' }
PNSystemBrowser >> wireSelectionHandlers [

	packagesOutline
		onSelectionChanged: [ :id | self packageItemSelected: id ].
	classesTable
		onSelectionChanged: [ :row | self classRowSelected: row ].
	protocolsTable
		onSelectionChanged: [ :row | self protocolRowSelected: row ].
	methodsTable
		onSelectionChanged: [ :row | self methodRowSelected: row ].
	packagesFilter
		onTextChanged: [ :text | self packageFilterChanged: text ].
	classesFilter
		onTextChanged: [ :text | self classFilterChanged: text ].
	protocolsFilter
		onTextChanged: [ :text | self protocolFilterChanged: text ].
	methodsFilter
		onTextChanged: [ :text | self methodFilterChanged: text ].
	acceptButton onClicked: [ self acceptSource ]
]

{ #category : 'loading - packages' }
PNSystemBrowser >> loadPackages [

	allPackages := self readAllPackages.
	self refreshPackagesDisplay
]

{ #category : 'loading - packages' }
PNSystemBrowser >> readAllPackages [
	"Return all packages, sorted by name. Extracted so tests can stub
	the package source."

	^ (PackageOrganizer default packages
		   asSortedCollection: [ :a :b | a name < b name ]) asArray
]

{ #category : 'filter handlers' }
PNSystemBrowser >> packageFilterChanged: aString [

	packageFilterText := aString ifNil: [ '' ].
	self refreshPackagesDisplay
]

{ #category : 'filter handlers' }
PNSystemBrowser >> classFilterChanged: aString [

	classFilterText := aString ifNil: [ '' ].
	self refreshClassesDisplay
]

{ #category : 'filter handlers' }
PNSystemBrowser >> protocolFilterChanged: aString [

	protocolFilterText := aString ifNil: [ '' ].
	self refreshProtocolsDisplay
]

{ #category : 'filter handlers' }
PNSystemBrowser >> methodFilterChanged: aString [

	methodFilterText := aString ifNil: [ '' ].
	self refreshMethodsDisplay
]

{ #category : 'display' }
PNSystemBrowser >> refreshPackagesDisplay [
	"Apply the current filter to allPackages and push the resulting tree
	into the outline. We send a forest of `{ id, label, children }`
	dictionaries; tags become child nodes of their owning package."

	| items |
	displayedPackages := self packagesFilteredBy: packageFilterText.
	items := displayedPackages collect: [ :pkg | self treeNodeForPackage: pkg ].
	packagesOutline items: items asArray
]

{ #category : 'display' }
PNSystemBrowser >> treeNodeForPackage: aPackage [

	^ Dictionary new
		  at: 'id' put: 'pkg:' , aPackage name asString;
		  at: 'label'
		  put: aPackage name asString , '  ('
			  , aPackage definedClasses size asString , ')';
		  at: 'children' put: (self tagNodesForPackage: aPackage);
		  yourself
]

{ #category : 'display' }
PNSystemBrowser >> tagNodesForPackage: aPackage [
	"Return tree nodes for aPackage's PackageTags.  Many packages have
	no tags at all (or only the root tag), in which case we yield an
	empty array and the package row is shown as a leaf."

	| tagList |
	tagList := [ aPackage tags ]
		           on: Error
		           do: [ :ignored | #(  ) ].
	tagList isEmpty ifTrue: [ ^ Array new ].
	^ ((tagList asSortedCollection: [ :a :b | a name < b name ]) asArray
		   reject: [ :each | each isRoot or: [ each classes isEmpty ] ])
		  collect: [ :tag |
			  Dictionary new
				  at: 'id'
				  put: 'tag:' , aPackage name asString , ':'
					  , tag name asString;
				  at: 'label'
				  put: tag name asString , '  ('
					  , tag classes size asString , ')';
				  yourself ]
]

{ #category : 'filtering' }
PNSystemBrowser >> packagesFilteredBy: aString [
	"Return the subset of allPackages whose name matches aString as a
	case-insensitive substring. Empty string returns the full list.
	Pure function: extracted so tests can drive it directly without
	any widget plumbing."

	aString trimBoth isEmpty ifTrue: [ ^ allPackages ].
	^ allPackages select: [ :pkg |
		  pkg name asLowercase
			  includesSubstring: aString trimBoth asLowercase ]
]

{ #category : 'filtering' }
PNSystemBrowser >> classesFilteredBy: aString [
	"Return the subset of allClasses (3-element entries) whose display
	name matches the filter."

	aString trimBoth isEmpty ifTrue: [ ^ allClasses ].
	^ allClasses select: [ :entry |
		  (entry at: 3) asLowercase
			  includesSubstring: aString trimBoth asLowercase ]
]

{ #category : 'filtering' }
PNSystemBrowser >> protocolsFilteredBy: aString [

	aString trimBoth isEmpty ifTrue: [ ^ allProtocols ].
	^ allProtocols select: [ :p |
		  p name asString asLowercase
			  includesSubstring: aString trimBoth asLowercase ]
]

{ #category : 'filtering' }
PNSystemBrowser >> methodsFilteredBy: aString [

	aString trimBoth isEmpty ifTrue: [ ^ allMethods ].
	^ allMethods select: [ :sel |
		  sel asString asLowercase
			  includesSubstring: aString trimBoth asLowercase ]
]

{ #category : 'selection - packages' }
PNSystemBrowser >> packageItemSelected: anId [
	"Outline selection sends us the chosen item's id. The id encodes
	whether a package or a tag was picked."

	anId ifNil: [ ^ self clearPackageSelection ].
	(anId beginsWith: 'pkg:') ifTrue: [
		selectedPackage := self packageNamed: (anId allButFirst: 4).
		selectedTag := nil.
		^ self packageSelectionChanged ].
	(anId beginsWith: 'tag:') ifTrue: [
		| rest pkgName tagName |
		rest := anId allButFirst: 4.
		pkgName := rest copyUpTo: $:.
		tagName := rest copyAfter: $:.
		selectedPackage := self packageNamed: pkgName.
		selectedTag := selectedPackage
			               ifNotNil: [
				               selectedPackage
					               tagNamed: tagName asSymbol
					               ifAbsent: [ nil ] ].
		^ self packageSelectionChanged ].
	self clearPackageSelection
]

{ #category : 'selection - packages' }
PNSystemBrowser >> clearPackageSelection [

	selectedPackage := nil.
	selectedTag := nil.
	allClasses := #(  ).
	displayedClasses := #(  ).
	self refreshClassesDisplay.
	self clearClassSelection
]

{ #category : 'selection - packages' }
PNSystemBrowser >> packageSelectionChanged [

	allClasses := self loadClassEntries.
	self refreshClassesDisplay.
	self clearClassSelection
]

{ #category : 'loading - classes' }
PNSystemBrowser >> loadClassEntries [
	"Return the entries to display in the Classes pane.  Each entry is a
	3-tuple `{ instanceSideClass, sideString, displayName }`.  The class
	side is shown as a separate row when it actually has methods, matching
	v1's layout."

	| source |
	selectedPackage ifNil: [ ^ #(  ) ].
	source := selectedTag
		          ifNotNil: [ selectedTag classes ]
		          ifNil: [ selectedPackage definedClasses ].
	^ Array streamContents: [ :s |
		  ((source asSortedCollection: [ :a :b | a name < b name ]) asArray)
			  do: [ :each |
				  s nextPut: { each. 'instance'. each name asString }.
				  each classSide ifNotNil: [ :meta |
					  meta hasMethods ifTrue: [
						  s nextPut:
							  { each. 'class'. each name asString , ' class' } ] ] ] ]
]

{ #category : 'display' }
PNSystemBrowser >> refreshClassesDisplay [

	displayedClasses := self classesFilteredBy: classFilterText.
	classesTable rows:
		(displayedClasses collect: [ :entry | Array with: (entry at: 3) ])
]

{ #category : 'selection - classes' }
PNSystemBrowser >> classRowSelected: aRowIndex [

	(aRowIndex < 0 or: [ aRowIndex >= displayedClasses size ]) ifTrue: [
		^ self clearClassSelection ].
	selectedClass := displayedClasses at: aRowIndex + 1.
	allProtocols := self loadProtocolEntries.
	self refreshProtocolsDisplay.
	selectedProtocol := nil.
	allMethods := self loadMethodSelectors.
	self refreshMethodsDisplay.
	sourceTextView string: ''
]

{ #category : 'selection - classes' }
PNSystemBrowser >> clearClassSelection [

	selectedClass := nil.
	allProtocols := #(  ).
	displayedProtocols := #(  ).
	self refreshProtocolsDisplay.
	selectedProtocol := nil.
	allMethods := #(  ).
	displayedMethods := #(  ).
	self refreshMethodsDisplay.
	sourceTextView string: ''
]

{ #category : 'loading - protocols' }
PNSystemBrowser >> loadProtocolEntries [

	| behavior |
	behavior := self behaviorForSelectedClass.
	behavior ifNil: [ ^ #(  ) ].
	^ (behavior protocols asSortedCollection: [ :a :b |
		   a name asString < b name asString ]) asArray
]

{ #category : 'display' }
PNSystemBrowser >> refreshProtocolsDisplay [

	| behavior |
	behavior := self behaviorForSelectedClass.
	displayedProtocols := self protocolsFilteredBy: protocolFilterText.
	protocolsTable rows: (displayedProtocols collect: [ :p |
			 | count |
			 count := behavior
				          ifNil: [ 0 ]
				          ifNotNil: [
				          (behavior selectorsInProtocol: p name) size ].
			 Array with: p name asString , '  (' , count asString , ')' ])
]

{ #category : 'selection - protocols' }
PNSystemBrowser >> protocolRowSelected: aRowIndex [

	(aRowIndex < 0 or: [ aRowIndex >= displayedProtocols size ])
		ifTrue: [ selectedProtocol := nil ]
		ifFalse: [ selectedProtocol := displayedProtocols at: aRowIndex + 1 ].
	allMethods := self loadMethodSelectors.
	self refreshMethodsDisplay.
	sourceTextView string: ''
]

{ #category : 'loading - methods' }
PNSystemBrowser >> loadMethodSelectors [

	| behavior selectors |
	behavior := self behaviorForSelectedClass.
	behavior ifNil: [ ^ #(  ) ].
	selectors := selectedProtocol
		             ifNil: [ behavior selectors ]
		             ifNotNil: [
		             behavior selectorsInProtocol: selectedProtocol name ].
	^ (selectors asSortedCollection: [ :a :b |
		   a asString < b asString ]) asArray
]

{ #category : 'display' }
PNSystemBrowser >> refreshMethodsDisplay [

	displayedMethods := self methodsFilteredBy: methodFilterText.
	methodsTable rows:
		(displayedMethods collect: [ :sel | Array with: sel asString ])
]

{ #category : 'selection - methods' }
PNSystemBrowser >> methodRowSelected: aRowIndex [

	(aRowIndex < 0 or: [ aRowIndex >= displayedMethods size ]) ifTrue: [
		selectedMethod := nil.
		sourceTextView string: ''.
		statusLabel stringValue: ''.
		^ self ].
	selectedMethod := displayedMethods at: aRowIndex + 1.
	statusLabel stringValue: ''.
	self displaySelectedMethodSource
]

{ #category : 'private' }
PNSystemBrowser >> displaySelectedMethodSource [

	| behavior method src |
	(selectedMethod isNil or: [ displayedMethods isEmpty ]) ifTrue: [
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

{ #category : 'private' }
PNSystemBrowser >> packageNamed: aString [

	^ allPackages
		  detect: [ :p | p name asString = aString ]
		  ifNone: [ nil ]
]

{ #category : 'private' }
PNSystemBrowser >> behaviorForSelectedClass [
	"selectedClass is the 3-element array we built in #loadClassEntries."

	selectedClass ifNil: [ ^ nil ].
	^ (selectedClass at: 2) = 'class'
		  ifTrue: [ (selectedClass at: 1) classSide ]
		  ifFalse: [ (selectedClass at: 1) instanceSide ]
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
	allMethods := self loadMethodSelectors.
	self refreshMethodsDisplay.

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

{ #category : 'lifecycle' }
PNSystemBrowser >> destroyAll [
	"Tear down every wrapper. Called from the willClose handler. We
	swallow errors per-widget because a partly-destroyed tree must not
	prevent the rest from being cleaned up."

	#( acceptButton statusLabel sourceToolbar
	   sourceTextView sourceScroll sourceContainer
	   methodsTable methodsScroll methodsFilter methodsPane
	   protocolsTable protocolsScroll protocolsFilter protocolsPane
	   classesTable classesScroll classesFilter classesPane
	   packagesOutline packagesScroll packagesFilter packagesPane
	   topSplit outerSplit window )
		do: [ :ivar |
			(self instVarNamed: ivar) ifNotNil: [ :w |
				[ w destroy ] on: Error do: [ :ignored | ].
				self instVarNamed: ivar put: nil ] ]
]
