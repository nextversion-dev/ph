"
A System Browser whose entire UI logic lives in Pharo. AppKit only renders
what we tell it to. This is the Pharo-driven counterpart to the v1
fat-client PharoNativeBrowser.app: the layout and selection cascade are
the same, but everything from window construction through the
package/class/protocol/method queries down to source assembly happens in
this image, in this class, hot-reloadable like any other Smalltalk code.

Iteration 3 visual surface:
  - Packages pane is an NSOutlineView: top-level rows are packages,
    each package's children are its PackageTags.
  - Classes pane is *also* an NSOutlineView, showing the inheritance
    hierarchy of in-package classes: each top-level row is a class
    whose superclass lives outside the package, with in-package
    subclasses nested underneath.
  - A 3-segment Instance / Class / Both control above the Classes pane
    picks which side the Protocols + Methods + Source panes browse.
  - Method rows are prefixed with decorations:
       arrow  override of a superclass method
       *      abstract (subclassResponsibility) method
       ~      extension method (defined in a different package)
  - Each pane (Packages / Classes / Protocols / Methods) has an
    NSSearchField filter input above it.  Filtering the Classes pane
    drops the hierarchy and shows a flat list of matches.
  - Bottom region is an NSTabView with two tabs: Source (editable,
    with the Accept button) and Hierarchy (read-only chain from
    Object down to the selected class).

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
		'sideToggle',
		'packagesScroll',
		'classesScroll',
		'protocolsScroll',
		'methodsScroll',
		'packagesOutline',
		'classesOutline',
		'protocolsTable',
		'methodsTable',
		'bottomTabs',
		'sourceContainer',
		'sourceScroll',
		'sourceToolbar',
		'sourceTextView',
		'acceptButton',
		'statusLabel',
		'hierarchyContainer',
		'hierarchyScroll',
		'hierarchyTextView',
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
		'currentSide',
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
	outerSplit dividerPositions: #( 420 ).
	^ self
]

{ #category : 'initialization' }
PNSystemBrowser >> initializeFilterState [

	packageFilterText := ''.
	classFilterText := ''.
	protocolFilterText := ''.
	methodFilterText := ''.
	currentSide := 'instance'.
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
	classesOutline := PNNSOutlineView new
		                  columns: { (Dictionary new
				                   at: 'title' put: 'Classes';
				                   at: 'identifier' put: 'name';
				                   yourself) };
		                  yourself.
	protocolsTable := self buildSingleColumnTable: 'Protocols'.
	methodsTable := self buildSingleColumnTable: 'Methods'.

	packagesScroll := self wrapInScroll: packagesOutline.
	classesScroll := self wrapInScroll: classesOutline.
	protocolsScroll := self wrapInScroll: protocolsTable.
	methodsScroll := self wrapInScroll: methodsTable.

	packagesFilter := self buildFilterField: 'Filter packages'.
	classesFilter := self buildFilterField: 'Filter classes'.
	protocolsFilter := self buildFilterField: 'Filter protocols'.
	methodsFilter := self buildFilterField: 'Filter methods'.

	sideToggle := PNNSSegmentedControl new
		              segments: #( 'Instance' 'Class' 'Both' );
		              selectedSegment: 0;
		              frame: (4 @ 364 extent: 267 @ 22);
		              autoresizingMask: #( width minY );
		              yourself.

	packagesPane := self buildPaneWith: packagesFilter scroll: packagesScroll.
	classesPane := self buildClassesPaneWith: classesFilter toggle: sideToggle scroll: classesScroll.
	protocolsPane := self buildPaneWith: protocolsFilter scroll: protocolsScroll.
	methodsPane := self buildPaneWith: methodsFilter scroll: methodsScroll.

	topSplit := PNNSSplitView new
		            vertical: true;
		            dividerStyle: 'thin';
		            frame: (0 @ 300 extent: 1100 @ 420);
		            yourself.
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
	self buildHierarchyPane.

	bottomTabs := PNNSTabView new
		              frame: (0 @ 0 extent: 1100 @ 300);
		              yourself.
	bottomTabs
		addTab: sourceContainer title: 'Source';
		addTab: hierarchyContainer title: 'Hierarchy'.

	outerSplit := PNNSSplitView new
		              vertical: false;
		              dividerStyle: 'thin';
		              frame: (0 @ 0 extent: 1100 @ 720);
		              yourself.
	outerSplit
		addArrangedSubview: topSplit;
		addArrangedSubview: bottomTabs.

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
	"Standard pane: filter input pinned to the top, scroll filling the
	rest. Returned PNNSView assumes a 275 x 420 initial frame."

	| pane |
	pane := PNNSView new.
	pane frame: (0 @ 0 extent: 275 @ 420).
	aFilterField
		frame: (4 @ 388 extent: 267 @ 26);
		autoresizingMask: #( width minY ).
	aScrollView
		frame: (0 @ 0 extent: 275 @ 380);
		autoresizingMask: #( width height ).
	pane addSubview: aScrollView; addSubview: aFilterField.
	^ pane
]

{ #category : 'building' }
PNSystemBrowser >> buildClassesPaneWith: aFilterField toggle: aToggle scroll: aScrollView [
	"Classes pane has an additional segmented Instance/Class/Both toggle
	tucked between the filter and the scroll view."

	| pane |
	pane := PNNSView new.
	pane frame: (0 @ 0 extent: 275 @ 420).
	aFilterField
		frame: (4 @ 388 extent: 267 @ 26);
		autoresizingMask: #( width minY ).
	aToggle
		frame: (4 @ 360 extent: 267 @ 22);
		autoresizingMask: #( width minY ).
	aScrollView
		frame: (0 @ 0 extent: 275 @ 354);
		autoresizingMask: #( width height ).
	pane addSubview: aScrollView; addSubview: aToggle; addSubview: aFilterField.
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
		                frame: (0 @ 36 extent: 1100 @ 240);
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
		                   frame: (0 @ 0 extent: 1100 @ 276);
		                   yourself.
	sourceContainer
		addSubview: sourceScroll;
		addSubview: sourceToolbar
]

{ #category : 'building' }
PNSystemBrowser >> buildHierarchyPane [
	"Read-only text view that lists the selected class's inheritance
	chain from Object down. Lives as the second NSTabView tab."

	hierarchyTextView := PNNSTextView new
		                     editable: false;
		                     string: '';
		                     yourself.
	hierarchyScroll := PNNSScrollView new
		                   borderType: 'none';
		                   hasVerticalScroller: true;
		                   documentView: hierarchyTextView;
		                   frame: (0 @ 0 extent: 1100 @ 276);
		                   autoresizingMask: #( width height );
		                   yourself.
	hierarchyContainer := PNNSView new
		                      frame: (0 @ 0 extent: 1100 @ 276);
		                      yourself.
	hierarchyContainer addSubview: hierarchyScroll
]

{ #category : 'wiring' }
PNSystemBrowser >> wireSelectionHandlers [

	packagesOutline
		onSelectionChanged: [ :id | self packageItemSelected: id ].
	classesOutline
		onSelectionChanged: [ :id | self classItemSelected: id ].
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
	sideToggle
		onSelectionChanged: [ :index :label | self sideToggleChanged: label ].
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

{ #category : 'filter handlers' }
PNSystemBrowser >> sideToggleChanged: aLabel [
	"aLabel is 'Instance', 'Class', or 'Both' from the segmented control.
	`'Both'` is treated as 'instance' for query purposes (Calypso's
	classic behavior); the side toggle is a future home for showing
	both sides interleaved if we want it."

	currentSide := aLabel asLowercase.
	(currentSide = 'instance' or: [ currentSide = 'class' or: [
		 currentSide = 'both' ] ]) ifFalse: [ currentSide := 'instance' ].
	allProtocols := self loadProtocolEntries.
	self refreshProtocolsDisplay.
	allMethods := self loadMethodSelectors.
	self refreshMethodsDisplay.
	self displaySelectedMethodSource
]

{ #category : 'display' }
PNSystemBrowser >> refreshPackagesDisplay [

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

	aString trimBoth isEmpty ifTrue: [ ^ allPackages ].
	^ allPackages select: [ :pkg |
		  pkg name asLowercase
			  includesSubstring: aString trimBoth asLowercase ]
]

{ #category : 'filtering' }
PNSystemBrowser >> classesFilteredBy: aString [
	"Filter the in-package classes by case-insensitive substring match
	against the class name. Empty filter returns the full set."

	aString trimBoth isEmpty ifTrue: [ ^ allClasses ].
	^ allClasses select: [ :cls |
		  cls name asString asLowercase
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
	self refreshClassesDisplay.
	self clearClassSelection
]

{ #category : 'selection - packages' }
PNSystemBrowser >> packageSelectionChanged [

	allClasses := self loadClasses.
	self refreshClassesDisplay.
	self clearClassSelection
]

{ #category : 'loading - classes' }
PNSystemBrowser >> loadClasses [
	"Return the in-package classes (instance side). The Classes pane
	always renders instance-side rows; the Instance/Class/Both
	segmented control switches which side the *Protocols and Methods*
	panes browse."

	| source |
	selectedPackage ifNil: [ ^ #(  ) ].
	source := selectedTag
		          ifNotNil: [ selectedTag classes ]
		          ifNil: [ selectedPackage definedClasses ].
	^ (source asSortedCollection: [ :a :b | a name < b name ]) asArray
]

{ #category : 'display' }
PNSystemBrowser >> refreshClassesDisplay [
	"Apply the current filter, then build either an inheritance tree
	(empty filter) or a flat list (filter narrowed) of class entries
	for the outline view. Filtering inherently breaks the parent-child
	hierarchy, so we fall back to flat when there's text."

	displayedClasses := self classesFilteredBy: classFilterText.
	classFilterText trimBoth isEmpty
		ifTrue: [
			classesOutline items:
				(self classHierarchyTreeFor: displayedClasses) ]
		ifFalse: [
			classesOutline items: (displayedClasses collect: [ :c |
					 Dictionary new
						 at: 'id' put: 'cls:' , c name asString;
						 at: 'label' put: c name asString;
						 yourself ]) ]
]

{ #category : 'display' }
PNSystemBrowser >> classHierarchyTreeFor: aClassArray [
	"Build an inheritance forest from the given classes: a class's
	parent in the tree is its superclass if the superclass is itself
	in the array; otherwise the class is a top-level root."

	| set childrenOf parentOf roots |
	set := aClassArray asSet.
	childrenOf := IdentityDictionary new.
	parentOf := IdentityDictionary new.
	aClassArray do: [ :c | childrenOf at: c put: OrderedCollection new ].
	aClassArray do: [ :c |
		| sup |
		sup := c superclass.
		(set includes: sup) ifTrue: [
			parentOf at: c put: sup.
			(childrenOf at: sup) add: c ] ].
	roots := aClassArray reject: [ :c | parentOf includesKey: c ].
	^ ((roots asSortedCollection: [ :a :b | a name < b name ]) asArray
		   collect: [ :c |
		   self classTreeNodeFor: c childrenOf: childrenOf ])
]

{ #category : 'display' }
PNSystemBrowser >> classTreeNodeFor: aClass childrenOf: aDict [

	| children kids |
	children := (aDict at: aClass ifAbsent: [ #(  ) ])
		            asSortedCollection: [ :a :b | a name < b name ].
	kids := children asArray collect: [ :child |
		        self classTreeNodeFor: child childrenOf: aDict ].
	^ Dictionary new
		  at: 'id' put: 'cls:' , aClass name asString;
		  at: 'label' put: aClass name asString;
		  at: 'children' put: kids;
		  yourself
]

{ #category : 'selection - classes' }
PNSystemBrowser >> classItemSelected: anId [

	anId ifNil: [ ^ self clearClassSelection ].
	(anId beginsWith: 'cls:') ifFalse: [ ^ self clearClassSelection ].
	selectedClass := self classNamed: (anId allButFirst: 4).
	selectedClass ifNil: [ ^ self clearClassSelection ].
	allProtocols := self loadProtocolEntries.
	self refreshProtocolsDisplay.
	selectedProtocol := nil.
	allMethods := self loadMethodSelectors.
	self refreshMethodsDisplay.
	sourceTextView string: ''.
	self refreshHierarchyDisplay
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
	sourceTextView string: ''.
	self refreshHierarchyDisplay
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

	| behavior |
	displayedMethods := self methodsFilteredBy: methodFilterText.
	behavior := self behaviorForSelectedClass.
	methodsTable rows: (displayedMethods collect: [ :sel |
			 Array with:
				 (self decorateSelector: sel forBehavior: behavior) ])
]

{ #category : 'display' }
PNSystemBrowser >> decorateSelector: aSelector forBehavior: aBehavior [
	"Prefix the displayed selector with a single decoration glyph:
	   '>'  override of a superclass method
	   '*'  abstract (subclassResponsibility)
	   '~'  extension method (defined in a different package)
	The fallback is two spaces so non-decorated rows still align with
	their decorated siblings."

	| method label |
	aBehavior ifNil: [ ^ '  ' , aSelector asString ].
	method := aBehavior
		          compiledMethodAt: aSelector asSymbol
		          ifAbsent: [ ^ '  ' , aSelector asString ].
	label := aSelector asString.
	(self isExtensionMethod: method onBehavior: aBehavior) ifTrue: [
		^ '~ ' , label ].
	(self isAbstractMethod: method) ifTrue: [ ^ '* ' , label ].
	(self isOverrideMethod: method onBehavior: aBehavior) ifTrue: [
		^ '> ' , label ].
	^ '  ' , label
]

{ #category : 'decorations' }
PNSystemBrowser >> isAbstractMethod: aMethod [
	"A method is abstract iff its body sends #subclassResponsibility."

	^ [ aMethod sendsSelector: #subclassResponsibility ]
		  on: Error
		  do: [ :ignored | false ]
]

{ #category : 'decorations' }
PNSystemBrowser >> isExtensionMethod: aMethod onBehavior: aBehavior [
	"An extension method's package isn't the same as its class's
	package. Pharo's tonel format prefixes the protocol with '*' to
	mark extensions, but we read the relationship directly so a
	mis-categorised method still shows the right marker."

	| methodPkg classPkg |
	methodPkg := [ aMethod package ]
		             on: Error
		             do: [ :ignored | nil ].
	classPkg := [ aBehavior instanceSide package ]
		            on: Error
		            do: [ :ignored | nil ].
	(methodPkg isNil or: [ classPkg isNil ]) ifTrue: [ ^ false ].
	^ methodPkg ~= classPkg
]

{ #category : 'decorations' }
PNSystemBrowser >> isOverrideMethod: aMethod onBehavior: aBehavior [
	"True when the same selector is also defined somewhere up the
	superclass chain."

	| superclass selector |
	selector := aMethod selector ifNil: [ ^ false ].
	superclass := aBehavior superclass.
	[ superclass isNil ] whileFalse: [
		(superclass includesSelector: selector) ifTrue: [ ^ true ].
		superclass := superclass superclass ].
	^ false
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

{ #category : 'display' }
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

{ #category : 'display' }
PNSystemBrowser >> refreshHierarchyDisplay [
	"Render the selected class's inheritance chain into the Hierarchy
	tab.  Each line shows one class name, indented two spaces per
	subclassing step, with a `>` marker on the selected class."

	| lines chain instanceSide indent |
	selectedClass ifNil: [
		hierarchyTextView string: ''.
		^ self ].
	instanceSide := selectedClass instanceSide.
	chain := OrderedCollection new.
	chain add: instanceSide.
	[ chain first superclass isNil ] whileFalse: [
		chain addFirst: chain first superclass ].
	indent := -1.
	lines := chain collect: [ :c |
		         indent := indent + 1.
		         (String new: indent * 2 withAll: $ )
		         , (c == instanceSide
				          ifTrue: [ '> ' ]
				          ifFalse: [ '  ' ])
		         , c name asString ].
	hierarchyTextView string: (String streamContents: [ :s |
			 lines do: [ :line | s nextPutAll: line ] separatedBy: [ s lf ] ])
]

{ #category : 'private' }
PNSystemBrowser >> packageNamed: aString [

	^ allPackages
		  detect: [ :p | p name asString = aString ]
		  ifNone: [ nil ]
]

{ #category : 'private' }
PNSystemBrowser >> classNamed: aString [

	^ allClasses
		  detect: [ :c | c name asString = aString ]
		  ifNone: [ nil ]
]

{ #category : 'private' }
PNSystemBrowser >> behaviorForSelectedClass [
	"Pick the side the Protocols + Methods + Source panes browse from
	the Instance/Class/Both toggle."

	selectedClass ifNil: [ ^ nil ].
	currentSide = 'class' ifTrue: [ ^ selectedClass classSide ].
	^ selectedClass instanceSide
]

{ #category : 'editing' }
PNSystemBrowser >> acceptSource [

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
	selectedMethod := result.
	allMethods := self loadMethodSelectors.
	self refreshMethodsDisplay.

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
	self displaySelectedMethodSource
]

{ #category : 'editing' }
PNSystemBrowser >> writeBehaviorToTonel: aBehavior [

	^ self class writeBehaviorToTonel: aBehavior
]

{ #category : 'editing' }
PNSystemBrowser class >> writeBehaviorToTonel: aBehavior [
	"Rewrite aBehavior's Tonel source file from its current in-image
	state. Returns true on success, false if the package has no
	matching Tonel repository registered.  Errors propagate."

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
	(packageDir / fileName) ensureDelete.
	(packageDir / fileName) binaryWriteStreamDo: [ :s |
		s nextPutAll: stream contents utf8Encoded ].
	^ true
]

{ #category : 'lifecycle' }
PNSystemBrowser >> destroyAll [
	"Tear down every wrapper. Called from the willClose handler.
	Per-widget errors are swallowed so a partly-destroyed tree never
	prevents the rest from being cleaned up."

	#( acceptButton statusLabel sourceToolbar
	   sourceTextView sourceScroll sourceContainer
	   hierarchyTextView hierarchyScroll hierarchyContainer
	   bottomTabs
	   methodsTable methodsScroll methodsFilter methodsPane
	   protocolsTable protocolsScroll protocolsFilter protocolsPane
	   classesOutline classesScroll sideToggle classesFilter classesPane
	   packagesOutline packagesScroll packagesFilter packagesPane
	   topSplit outerSplit window )
		do: [ :ivar |
			(self instVarNamed: ivar) ifNotNil: [ :w |
				[ w destroy ] on: Error do: [ :ignored | ].
				self instVarNamed: ivar put: nil ] ]
]
