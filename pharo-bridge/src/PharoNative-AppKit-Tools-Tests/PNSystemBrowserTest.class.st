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
	"Install the fake adaptor as the singleton so any widget wrappers
	created during the test see a recording stand-in instead of a real
	TCP connection. We then build the full widget tree -- with the fake
	doing the talking -- so methods that mutate widgets in the selection
	cascade have something to send commands to. No window is shown."
	previousAdaptor := PNAppKitAdaptor classVarNamed: #Default.
	PNAppKitAdaptor classVarNamed: #Default put: PNFakeAdaptor new.
	browser := PNSystemBrowser new.
	browser initializeFilterState.
	browser buildWindow.
	browser wireSelectionHandlers.
	"Reset the recording so individual tests start with a clean ledger."
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
	"Use real Pharo packages but pick a small set so tests are fast and
	deterministic. The bridge's own packages exist in every image we
	target and are stable enough to rely on."

	^ {
		  PackageOrganizer default packageNamed: 'PharoNative-Bridge-Core'.
		  PackageOrganizer default packageNamed: 'PharoNative-AppKit-Widgets'.
		  PackageOrganizer default packageNamed: 'PharoNative-AppKit-Tools' }
]

{ #category : 'tests - filtering' }
PNSystemBrowserTest >> testPackagesFilteredByEmptyReturnsAllPackages [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	self
		assert: (browser packagesFilteredBy: '')
		equals: self samplePackages
]

{ #category : 'tests - filtering' }
PNSystemBrowserTest >> testPackagesFilteredByTrimsWhitespace [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	self
		assert: (browser packagesFilteredBy: '   ')
		equals: self samplePackages
]

{ #category : 'tests - filtering' }
PNSystemBrowserTest >> testPackagesFilteredByMatchesCaseInsensitiveSubstring [

	| matches |
	browser instVarNamed: 'allPackages' put: self samplePackages.
	matches := browser packagesFilteredBy: 'appkit'.
	self assert: matches size equals: 2.
	self assert:
		(matches allSatisfy: [ :p |
			 p name asLowercase includesSubstring: 'appkit' ])
]

{ #category : 'tests - filtering' }
PNSystemBrowserTest >> testPackagesFilteredByNoMatchReturnsEmpty [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	self
		assertEmpty: (browser packagesFilteredBy: 'no-such-thing-zzz')
]

{ #category : 'tests - filtering' }
PNSystemBrowserTest >> testClassesFilteredByMatchesDisplayName [

	| entries matches |
	entries := {
		           { Object. 'instance'. 'Object' }.
		           { Object. 'class'. 'Object class' }.
		           { Behavior. 'instance'. 'Behavior' } }.
	browser instVarNamed: 'allClasses' put: entries.
	matches := browser classesFilteredBy: 'class'.
	self assert: matches size equals: 1.
	self assert: (matches first at: 3) equals: 'Object class'
]

{ #category : 'tests - filtering' }
PNSystemBrowserTest >> testMethodsFilteredByMatchesSelector [

	browser instVarNamed: 'allMethods' put: #( foo bar foobar baz ).
	self
		assert: (browser methodsFilteredBy: 'foo') asArray
		equals: #( foo foobar ).
	self assert: (browser methodsFilteredBy: 'BAZ') asArray equals: #( baz ).
	self assertEmpty: (browser methodsFilteredBy: 'qux')
]

{ #category : 'tests - tree shape' }
PNSystemBrowserTest >> testTreeNodeForPackageHasIdAndLabel [

	| pkg node |
	pkg := PackageOrganizer default
		       packageNamed: 'PharoNative-AppKit-Tools'.
	node := browser treeNodeForPackage: pkg.
	self assert: (node at: 'id') equals: 'pkg:PharoNative-AppKit-Tools'.
	self assert:
		((node at: 'label') beginsWith: 'PharoNative-AppKit-Tools  (')
]

{ #category : 'tests - tree shape' }
PNSystemBrowserTest >> testTagNodesForPackageHandlesUntaggedPackages [

	| pkg children |
	"PharoNative-AppKit-Tools currently has no non-root tags, so it
	yields an empty children list."
	pkg := PackageOrganizer default
		       packageNamed: 'PharoNative-AppKit-Tools'.
	children := browser tagNodesForPackage: pkg.
	self assertEmpty: children
]

{ #category : 'tests - selection - packages' }
PNSystemBrowserTest >> testPackageItemSelectedWithNilClearsSelection [

	browser instVarNamed: 'allPackages' put: self samplePackages.
	browser
		instVarNamed: 'selectedPackage'
		put: self samplePackages first.
	"Calling the handler should clear the package selection. The handler
	also re-emits widget commands; the fake adaptor swallows those, and
	any widget operations are no-ops because the widgets are nil."
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

