"
PNDebuggerWindow is the Pharo-driven native debugger. It uses the
TDebugger trait so Oups discovers it and routes every debug session
through it. With a higher rank than the default in-image debugger we
always win the selection -- the result: any unhandled exception in the
Pharo image opens an AppKit window rendered by PharoNativeShell.app,
not a Morphic debugger.

End-to-end flow:

   user expression (e.g. `1/0`)
     -> exception signals
     -> OupsDebuggerSystem >> openDebuggerOnRequest:
     -> OupsDebuggerSelectionStrategy picks highest-rank TDebugger user
     -> PNDebuggerWindow class >> debugSession: aSession
     -> instance >> openOn: aSession  builds window via widget protocol
     -> #debugSession: returns; Oups suspends the offending process
     -> user clicks Step Over / Proceed / Abandon
     -> PNDebuggerWindow sends DebugSession messages
     -> refresh on each step

The window holds the standard four widget regions:

   stack list (NSTableView) | source view (NSTextView)
   ------------------------------------------------
   variables list (NSTableView, 2 columns: name, value)
   ------------------------------------------------
   button row: Proceed | Restart | Step Over | Abandon

All widgets come from the existing widget protocol -- no shell changes
were required for this class.
"
Class {
	#name : 'PNDebuggerWindow',
	#superclass : 'Object',
	#traits : 'TDebugger',
	#classTraits : 'TDebugger classTrait',
	#instVars : [
		'session',
		'window',
		'outerSplit',
		'topSplit',
		'stackScroll',
		'stackTable',
		'sourceScroll',
		'sourceTextView',
		'bottomBox',
		'varsScroll',
		'varsTable',
		'buttonRow',
		'proceedButton',
		'restartButton',
		'stepOverButton',
		'abandonButton',
		'currentStack',
		'selectedFrameIndex'
	],
	#category : 'PharoNative-AppKit-Tools',
	#package : 'PharoNative-AppKit-Tools'
}

{ #category : 'accessing' }
PNDebuggerWindow class >> availableAutomatically [

	"We always want Oups to pick us when an exception fires."
	^ true
]

{ #category : 'accessing' }
PNDebuggerWindow class >> closeAllDebuggers [
	"Called by OupsDebuggerSystem class >> closeAllDebuggers. Tear down
	every open native debugger window. Errors per-instance are swallowed
	so a damaged window does not block sibling cleanup."

	self allInstancesDo: [ :inst |
		[ inst destroyAll ] on: Error do: [ :ignored | ] ]
]

{ #category : 'instance creation' }
PNDebuggerWindow class >> debugSession: aDebugSession [
	"TDebugger entry point. Build a window for aDebugSession and return
	promptly so OupsDebuggerSystem can suspend the offending process."

	^ self new openOn: aDebugSession
]

{ #category : 'debugging' }
PNDebuggerWindow class >> handlesDebugSession: aDebugSession [
	"Always handle. The default trait implementation checks
	`SmalltalkImage current isInteractive`; we override so the native
	debugger is picked in both interactive and headless images, since
	the actual UI lives in PharoNativeShell.app anyway."

	^ true
]

{ #category : 'accessing' }
PNDebuggerWindow class >> rank [
	"Higher than the default (which is DebuggerSettings defaultDebuggerRank,
	typically ~100). 1000 ensures we win the selection strategy."

	^ 1000
]

{ #category : 'opening' }
PNDebuggerWindow >> openOn: aDebugSession [
	"Build the window from aDebugSession and show it. Called once per
	session, from the class-side debugSession: entry point."

	session := aDebugSession.
	selectedFrameIndex := 0.
	self buildWindow.
	self wireSelectionHandlers.
	self wireButtons.
	self refresh.
	window show.
	"NSSplitView ignores setPosition:ofDividerAt: until after first
	layout; set divider positions after the window is on screen."
	outerSplit dividerPositions: #( 460 ).
	topSplit dividerPositions: #( 360 ).
	^ self
]

{ #category : 'building' }
PNDebuggerWindow >> buildWindow [
	"Layout:
	  window
	    outerSplit (vertical stack, divider horizontal)
	      topSplit (horizontal stack, divider vertical)
	        stackScroll -> stackTable        (left, ~33% width)
	        sourceScroll -> sourceTextView   (right, ~67% width)
	      bottomBox (PNNSView, container)
	        varsScroll -> varsTable          (most of bottom)
	        buttonRow (PNNSView)              (40-tall strip at bottom)
	          proceedButton, restartButton, stepOverButton, abandonButton"

	window := PNNSWindow new
		          title: 'Debugger';
		          contentSize: 1100 @ 780;
		          yourself.

	stackTable := PNNSTableView new.
	stackTable columns: { (Dictionary new
				 at: 'title' put: 'Frame';
				 at: 'identifier' put: 'name';
				 yourself) }.
	stackScroll := PNNSScrollView new
		               borderType: 'none';
		               documentView: stackTable;
		               frame: (0 @ 0 extent: 360 @ 460);
		               yourself.

	sourceTextView := PNNSTextView new
		                  editable: false;
		                  string: '';
		                  yourself.
	sourceScroll := PNNSScrollView new
		                borderType: 'none';
		                hasVerticalScroller: true;
		                documentView: sourceTextView;
		                frame: (360 @ 0 extent: 740 @ 460);
		                yourself.

	topSplit := PNNSSplitView new
		            vertical: true;
		            dividerStyle: 'thin';
		            frame: (0 @ 320 extent: 1100 @ 460);
		            yourself.
	topSplit
		addArrangedSubview: stackScroll;
		addArrangedSubview: sourceScroll.

	"Variables list: 2 columns -- name, value."
	varsTable := PNNSTableView new.
	varsTable columns: {
			(Dictionary new
				 at: 'title' put: 'Name';
				 at: 'identifier' put: 'name';
				 at: 'width' put: 160;
				 yourself).
			(Dictionary new
				 at: 'title' put: 'Value';
				 at: 'identifier' put: 'value';
				 yourself) }.
	varsScroll := PNNSScrollView new
		              borderType: 'none';
		              hasVerticalScroller: true;
		              documentView: varsTable;
		              frame: (0 @ 40 extent: 1100 @ 240);
		              autoresizingMask: #( width height );
		              yourself.

	"Button row sits at the bottom of bottomBox. autoresizingMask = #(width)
	keeps it pinned to its origin (y=0) while it stretches with the window."
	buttonRow := PNNSView new
		             frame: (0 @ 0 extent: 1100 @ 40);
		             autoresizingMask: #( width );
		             yourself.

	proceedButton := PNNSButton new
		                 title: 'Proceed';
		                 frame: (10 @ 4 extent: 110 @ 32);
		                 yourself.
	restartButton := PNNSButton new
		                 title: 'Restart';
		                 frame: (130 @ 4 extent: 110 @ 32);
		                 yourself.
	stepOverButton := PNNSButton new
		                  title: 'Step Over';
		                  frame: (250 @ 4 extent: 110 @ 32);
		                  yourself.
	abandonButton := PNNSButton new
		                 title: 'Abandon';
		                 frame: (370 @ 4 extent: 110 @ 32);
		                 yourself.

	buttonRow
		addSubview: proceedButton;
		addSubview: restartButton;
		addSubview: stepOverButton;
		addSubview: abandonButton.

	bottomBox := PNNSView new
		             frame: (0 @ 0 extent: 1100 @ 320);
		             yourself.
	bottomBox
		addSubview: varsScroll;
		addSubview: buttonRow.

	outerSplit := PNNSSplitView new
		              vertical: false;
		              dividerStyle: 'thin';
		              frame: (0 @ 0 extent: 1100 @ 780);
		              yourself.
	outerSplit
		addArrangedSubview: topSplit;
		addArrangedSubview: bottomBox.

	window contentView addSubview: outerSplit.
	outerSplit fillSuperview.

	window onWillClose: [ self destroyAll ]
]

{ #category : 'wiring' }
PNDebuggerWindow >> wireSelectionHandlers [

	stackTable onSelectionChanged: [ :row | self frameRowSelected: row ].
	varsTable onSelectionChanged: [ :row | "v1: no-op" ]
]

{ #category : 'wiring' }
PNDebuggerWindow >> wireButtons [

	proceedButton onClicked: [ self actProceed ].
	restartButton onClicked: [ self actRestart ].
	stepOverButton onClicked: [ self actStepOver ].
	abandonButton onClicked: [ self actAbandon ]
]

{ #category : 'refresh' }
PNDebuggerWindow >> refresh [
	"Repopulate every pane from the current session. Called after every
	step / restart, and once at window-open time."

	currentStack := [ session stack asArray ]
		                on: Error
		                do: [ :ignored | #(  ) ].
	stackTable rows: (currentStack collect: [ :ctx |
			 Array with: (self frameLabelFor: ctx) ]).

	(currentStack isEmpty or: [ selectedFrameIndex >= currentStack size ])
		ifTrue: [ selectedFrameIndex := 0 ].
	currentStack ifNotEmpty: [
		"Setting selectedRow on the table re-fires onSelectionChanged."
		stackTable selectedRow: selectedFrameIndex ]
		ifEmpty: [
			sourceTextView string: ''.
			varsTable rows: #(  ) ].

	window title: self windowTitle
]

{ #category : 'refresh' }
PNDebuggerWindow >> frameRowSelected: aRowIndex [

	selectedFrameIndex := aRowIndex max: 0.
	(currentStack isEmpty or: [ aRowIndex < 0 ]) ifTrue: [
		sourceTextView string: ''.
		varsTable rows: #(  ).
		^ self ].
	(aRowIndex < currentStack size) ifFalse: [ ^ self ].
	self displaySourceFor: (currentStack at: aRowIndex + 1).
	self displayVarsFor: (currentStack at: aRowIndex + 1)
]

{ #category : 'refresh' }
PNDebuggerWindow >> displaySourceFor: aContext [

	| src |
	src := [ aContext sourceCode ]
		       on: Error
		       do: [ :ex | nil ].
	sourceTextView string: (src ifNil: [ '"no source available"' ])
]

{ #category : 'refresh' }
PNDebuggerWindow >> displayVarsFor: aContext [
	"Build a 2-column rows list: { receiver, args, temps }, each rendered
	with #printString for the value. printString itself can fail (broken
	#printOn: implementations are how some bugs even reach us), so each
	row's value is wrapped in an on:do: that falls back to a stub."

	| rows |
	rows := OrderedCollection new.
	rows add: { 'self'. (self safePrint: aContext receiver) }.
	[
	| names |
	names := aContext tempNames.
	names withIndexDo: [ :name :i |
		rows add:
			{ name asString. (self safePrint: (aContext tempAt: i)) } ] ]
		on: Error
		do: [ :ex |
			rows add: { '<temps>'.
			            'unable to read locals: ' , ex messageText } ].
	varsTable rows: rows asArray
]

{ #category : 'refresh' }
PNDebuggerWindow >> frameLabelFor: aContext [

	^ [
	  | label |
	  label := aContext receiver class name asString , ' >> '
	           , aContext selector asString.
	  label size > 100
		  ifTrue: [ (label first: 97) , '...' ]
		  ifFalse: [ label ] ]
		  on: Error
		  do: [ :ex | '<unreadable frame: ' , ex messageText , '>' ]
]

{ #category : 'refresh' }
PNDebuggerWindow >> windowTitle [

	| exception className msg |
	exception := [ session exception ] on: Error do: [ :ignored | nil ].
	exception ifNil: [ ^ 'Debugger' ].
	className := exception class name asString.
	msg := [ exception messageText ] on: Error do: [ :ignored | nil ].
	msg isEmptyOrNil ifTrue: [ ^ 'Debugger: ' , className ].
	msg size > 80 ifTrue: [ msg := (msg first: 77) , '...' ].
	^ 'Debugger: ' , className , ' -- ' , msg
]

{ #category : 'private' }
PNDebuggerWindow >> safePrint: anObject [
	"Some objects have buggy #printOn: implementations. Guard so the
	debugger UI never crashes on a printOn: error -- which would lead to
	a debugger-of-the-debugger spiral."

	^ [ anObject printString ]
		  on: Error
		  do: [ :ex | '<printString error: ' , ex messageText , '>' ]
]

{ #category : 'actions' }
PNDebuggerWindow >> actProceed [
	"Resume the suspended process and close the window. Errors from
	#resume (e.g. session is already terminated) are swallowed."

	[ session resume ] on: Error do: [ :ignored | ].
	self destroyAll
]

{ #category : 'actions' }
PNDebuggerWindow >> actRestart [

	| frame |
	currentStack isEmpty ifTrue: [ ^ self ].
	frame := currentStack at: (selectedFrameIndex + 1).
	[ session restart: frame ] on: Error do: [ :ignored | ].
	self refresh
]

{ #category : 'actions' }
PNDebuggerWindow >> actStepOver [

	| frame |
	currentStack isEmpty ifTrue: [ ^ self ].
	frame := currentStack at: (selectedFrameIndex + 1).
	[ session stepOver: frame ] on: Error do: [ :ignored | ].
	self refresh
]

{ #category : 'actions' }
PNDebuggerWindow >> actAbandon [
	"Terminate the suspended process and close the window."

	[ session terminate ] on: Error do: [ :ignored | ].
	self destroyAll
]

{ #category : 'lifecycle' }
PNDebuggerWindow >> destroyAll [
	"Tear down every widget wrapper in safe order. Called from
	#actProceed, #actAbandon, the window's willClose handler, and the
	class-side closeAllDebuggers cleanup. Per-widget errors are swallowed
	so a partly-destroyed tree never blocks the rest of cleanup."

	#( proceedButton restartButton stepOverButton abandonButton
	   buttonRow varsTable varsScroll bottomBox
	   sourceTextView sourceScroll stackTable stackScroll
	   topSplit outerSplit window )
		do: [ :ivar |
			(self instVarNamed: ivar) ifNotNil: [ :w |
				[ w destroy ] on: Error do: [ :ignored | ].
				self instVarNamed: ivar put: nil ] ]
]
