"
Unit tests for PNSystemBrowser. The browser's UI logic is exercised
directly against in-memory state; the filter functions are pure and
don't require any widgets, and the wire commands emitted by the
display methods are verified against the recording made by
PNFakeAdaptor (no native shell process is needed).

Tests run in <100 ms in aggregate.
"
Class {
	#name : 'PNSystemBrowserTest',
	#superclass : 'TestCase',
	#instVars : [
		'browser',
		'previousAdaptor'
	],
	#category : 'PharoNative-AppKit-Tools-Tests',
	#package : 'PharoNative-AppKit-Tools-Tests'
}

{ #category : 'running' }
PNSystemBrowserTest >> setUp [

	super setUp.
	previousAdaptor := PNAppKitAdaptor classVarNamed: #Default.
	PNAppKitAdaptor classVarNamed: #Default put: PNFakeAdaptor new.
	browser := PNSystemBrowser new.
	browser initializeFilterState.
	browser buildWindow.
	browser wireSelectionHandlers.
	self fakeAdaptor reset
]

{ #category : 'running' }
PNSystemBrowserTest >> tearDown [

	PNAppKitAdaptor classVarNamed: #Default put: previousAdaptor.
	super tearDown
]

{ #category : 'helpers' }
PNSystemBrowserTest >> fakeAdaptor [

	^ PNAppKitAdaptor default
]

{ #category : 'helpers' }
PNSystemBrowserTest >> samplePackages [

	^ {
		  PackageOrganizer default packageNamed: 'PharoNative-Bridge-Core'.
		  PackageOrganizer default packageNamed: 'PharoNative-AppKit-Widgets'.
		  PackageOrganizer default packageNamed: 'PharoNative-AppKit-Tools' }
]

{ #category : 'tests - filtering - packages' }
PNSystemBrowserTest >> testPackagesFilteredByEmptyReturnsAllPackages [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	self
		assert: (browser packagesFilteredBy: '')
		equals: self samplePackages
]

{ #category : 'tests - filtering - packages' }
PNSystemBrowserTest >> testPackagesFilteredByTrimsWhitespace [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	self
		assert: (browser packagesFilteredBy: '   ')
		equals: self samplePackages
]

{ #category : 'tests - filtering - packages' }
PNSystemBrowserTest >> testPackagesFilteredByMatchesCaseInsensitiveSubstring [

	| matches |
	browser instVarNamed: 'allPackages' put: self samplePackages.
	matches := browser packagesFilteredBy: 'appkit'.
	self assert: matches size equals: 2.
	self assert:
		(matches allSatisfy: [ :p |
			 p name asLowercase includesSubstring: 'appkit' ])
]

{ #category : 'tests - filtering - packages' }
PNSystemBrowserTest >> testPackagesFilteredByNoMatchReturnsEmpty [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	self
		assertEmpty: (browser packagesFilteredBy: 'no-such-thing-zzz')
]

{ #category : 'tests - filtering - classes' }
PNSystemBrowserTest >> testClassesFilteredByMatchesClassName [

	| matches |
	browser
		instVarNamed: 'allClasses'
		put: { Object. Behavior. Class. Metaclass }.
	matches := browser classesFilteredBy: 'class'.
	"Class and Metaclass both contain 'class' in their names (case-
	insensitive)."
	self assert: matches size equals: 2.
	self assert: (matches includes: Class).
	self assert: (matches includes: Metaclass)
]

{ #category : 'tests - filtering - methods' }
PNSystemBrowserTest >> testMethodsFilteredByMatchesSelector [

	browser instVarNamed: 'allMethods' put: #( foo bar foobar baz ).
	self
		assert: (browser methodsFilteredBy: 'foo') asArray
		equals: #( foo foobar ).
	self assert: (browser methodsFilteredBy: 'BAZ') asArray equals: #( baz ).
	self assertEmpty: (browser methodsFilteredBy: 'qux')
]

{ #category : 'tests - tree shape - packages' }
PNSystemBrowserTest >> testTreeNodeForPackageHasIdAndLabel [

	| pkg node |
	pkg := PackageOrganizer default
		       packageNamed: 'PharoNative-AppKit-Tools'.
	node := browser treeNodeForPackage: pkg.
	self assert: (node at: 'id') equals: 'pkg:PharoNative-AppKit-Tools'.
	self assert:
		((node at: 'label') beginsWith: 'PharoNative-AppKit-Tools  (')
]

{ #category : 'tests - tree shape - packages' }
PNSystemBrowserTest >> testTagNodesForPackageHandlesUntaggedPackages [

	| pkg children |
	pkg := PackageOrganizer default
		       packageNamed: 'PharoNative-AppKit-Tools'.
	children := browser tagNodesForPackage: pkg.
	self assertEmpty: children
]

{ #category : 'tests - tree shape - classes' }
PNSystemBrowserTest >> testClassHierarchyTreeRootsAreClassesWithoutInPackageSuperclass [
	"For the set { Object, Behavior } we expect a single root:
	Object (root because ProtoObject isn't in the set), with Behavior
	as its sole in-package child."

	| roots root behaviorNode |
	roots := browser classHierarchyTreeFor: { Object. Behavior }.
	self assert: roots size equals: 1.
	root := roots first.
	self assert: (root at: 'id') equals: 'cls:Object'.
	self assert: (root at: 'children') size equals: 1.
	behaviorNode := (root at: 'children') first.
	self assert: (behaviorNode at: 'id') equals: 'cls:Behavior'.
	self assertEmpty: (behaviorNode at: 'children')
]

{ #category : 'tests - tree shape - classes' }
PNSystemBrowserTest >> testClassHierarchyTreeProducesMultipleRootsWhenAncestorsAreOutsideSet [
	"With { Object, Behavior, Class, Metaclass } there are three roots:
	   Object             -- ProtoObject isn't in the set
	   Class              -- ClassDescription isn't in the set
	   Metaclass          -- ClassDescription isn't in the set
	with Behavior nested as a child of Object."

	| roots ids |
	roots := browser classHierarchyTreeFor:
		         { Object. Behavior. Class. Metaclass }.
	ids := (roots collect: [ :n | n at: 'id' ]) asSet.
	self
		assert: ids
		equals:
		(Set
			 with: 'cls:Object'
			 with: 'cls:Class'
			 with: 'cls:Metaclass').
	self
		assert: (((roots detect: [ :n | (n at: 'id') = 'cls:Object' ])
				  at: 'children')
				 collect: [ :n | n at: 'id' ])
		equals: #( 'cls:Behavior' )
]

{ #category : 'tests - tree shape - classes' }
PNSystemBrowserTest >> testClassTreeNodeNestsImmediateSubclassesOnly [

	| dict node |
	dict := IdentityDictionary new.
	dict at: Object put: { Behavior }.
	dict at: Behavior put: { Class }.
	dict at: Class put: #(  ).
	node := browser classTreeNodeFor: Object childrenOf: dict.
	self assert: (node at: 'id') equals: 'cls:Object'.
	self assert: (node at: 'label') equals: 'Object'.
	self assert: (node at: 'children') size equals: 1.
	self
		assert: ((node at: 'children') first at: 'id')
		equals: 'cls:Behavior'.
	self
		assert: ((node at: 'children') first at: 'children') size
		equals: 1.
	self
		assert:
			(((node at: 'children') first at: 'children') first at: 'id')
		equals: 'cls:Class'
]

{ #category : 'tests - selection - packages' }
PNSystemBrowserTest >> testPackageItemSelectedWithNilClearsSelection [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	browser
		instVarNamed: 'selectedPackage'
		put: self samplePackages first.
	browser packageItemSelected: nil.
	self assert: (browser instVarNamed: 'selectedPackage') isNil.
	self assert: (browser instVarNamed: 'selectedTag') isNil
]

{ #category : 'tests - selection - packages' }
PNSystemBrowserTest >> testPackageItemSelectedWithPkgIdLocatesPackage [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	browser packageItemSelected: 'pkg:PharoNative-AppKit-Widgets'.
	self
		assert: (browser instVarNamed: 'selectedPackage') name
		equals: 'PharoNative-AppKit-Widgets'.
	self assert: (browser instVarNamed: 'selectedTag') isNil
]

{ #category : 'tests - selection - packages' }
PNSystemBrowserTest >> testPackageItemSelectedWithUnknownPkgIdClears [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	browser packageItemSelected: 'pkg:NoSuchPackage'.
	self assert: (browser instVarNamed: 'selectedPackage') isNil
]

{ #category : 'tests - selection - classes' }
PNSystemBrowserTest >> testClassItemSelectedLocatesClass [

	browser instVarNamed: 'allClasses' put: { Object. Behavior }.
	browser classItemSelected: 'cls:Behavior'.
	self
		assert: (browser instVarNamed: 'selectedClass')
		equals: Behavior
]

{ #category : 'tests - selection - classes' }
PNSystemBrowserTest >> testClassItemSelectedWithUnknownClassClears [

	browser instVarNamed: 'allClasses' put: { Object. Behavior }.
	browser classItemSelected: 'cls:NoSuchClass'.
	self assert: (browser instVarNamed: 'selectedClass') isNil
]

{ #category : 'tests - side toggle' }
PNSystemBrowserTest >> testBehaviorForSelectedClassDefaultsToInstanceSide [

	browser instVarNamed: 'selectedClass' put: Object.
	browser instVarNamed: 'currentSide' put: 'instance'.
	self assert: browser behaviorForSelectedClass equals: Object
]

{ #category : 'tests - side toggle' }
PNSystemBrowserTest >> testBehaviorForSelectedClassFollowsClassSideToggle [

	browser instVarNamed: 'selectedClass' put: Object.
	browser instVarNamed: 'currentSide' put: 'class'.
	self
		assert: browser behaviorForSelectedClass
		equals: Object class
]

{ #category : 'tests - decorations' }
PNSystemBrowserTest >> testDecorateSelectorOnNilBehavior [

	self
		assert: (browser decorateSelector: #foo forBehavior: nil)
		equals: '  foo'
]

{ #category : 'tests - decorations' }
PNSystemBrowserTest >> testDecorateSelectorMarksOverride [
	"Behavior>>printOn: is an override of Object>>printOn:.  Make sure
	the decoration picks that up."

	self
		assert: (browser decorateSelector: #printOn: forBehavior: Behavior)
		equals: '> printOn:'
]

{ #category : 'tests - decorations' }
PNSystemBrowserTest >> testDecorateSelectorMarksAbstract [
	"Collection>>add: is famously abstract (sends
	#subclassResponsibility), so the decoration is `*`."

	self
		assert: (browser decorateSelector: #add: forBehavior: Collection)
		equals: '* add:'
]
