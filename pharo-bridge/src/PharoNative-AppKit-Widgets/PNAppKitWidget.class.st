"
I am the abstract superclass of all native AppKit widget wrappers. I hold
the widget id and a reference to the adaptor, and provide create / setProp
/ invoke / subscribe / destroy primitives. Concrete subclasses
(PNNSWindow, PNNSButton, PNNSTextField, ...) expose idiomatic accessors
on top of me.

This is the Pharo-side analog of a VisualWorks Wrapper or a VAST Common
Widgets peer-holder: a Smalltalk object that wraps a native widget by id
and forwards messages over the protocol.
"
Class {
	#name : 'PNAppKitWidget',
	#superclass : 'Object',
	#instVars : [
		'id',
		'adaptor',
		'destroyed'
	],
	#category : 'PharoNative-AppKit-Widgets',
	#package : 'PharoNative-AppKit-Widgets'
}

{ #category : 'subclass responsibility' }
PNAppKitWidget class >> widgetTypeName [
	"Return the wire type name registered with the shell, e.g. 'NSWindow'."

	^ self subclassResponsibility
]

{ #category : 'instance creation' }
PNAppKitWidget class >> new [
	"Allocate a new wrapper, ask the adaptor for an id, and create the
	matching widget on the shell side with no extra props. Subclasses can
	then send setProp: messages to configure it."

	| inst |
	inst := super new.
	inst createOnShell.
	^ inst
]

{ #category : 'initialization' }
PNAppKitWidget >> initialize [

	super initialize.
	adaptor := PNAppKitAdaptor default.
	id := adaptor nextWidgetId.
	destroyed := false
]

{ #category : 'accessing' }
PNAppKitWidget >> id [

	^ id
]

{ #category : 'accessing' }
PNAppKitWidget >> adaptor [

	^ adaptor
]

{ #category : 'lifecycle' }
PNAppKitWidget >> createOnShell [
	"Send widget.create with no props. Subclasses can override
	#initialProps to seed properties at create time."

	adaptor
		call: 'widget.create'
		params: (Dictionary new
				 at: 'id' put: id;
				 at: 'type' put: self class widgetTypeName;
				 at: 'props' put: self initialProps;
				 yourself)
]

{ #category : 'private' }
PNAppKitWidget >> initialProps [
	"Override in subclasses to seed properties at creation time. Default
	is an empty Dictionary."

	^ Dictionary new
]

{ #category : 'private' }
PNAppKitWidget >> setProp: aName value: aValue [
	"Send widget.setProp with the given name and value."

	self ensureNotDestroyed.
	adaptor
		call: 'widget.setProp'
		params: (Dictionary new
				 at: 'id' put: id;
				 at: 'name' put: aName;
				 at: 'value' put: aValue;
				 yourself)
]

{ #category : 'private' }
PNAppKitWidget >> invoke: aSelector [

	^ self invoke: aSelector args: #()
]

{ #category : 'private' }
PNAppKitWidget >> invoke: aSelector args: anArray [

	self ensureNotDestroyed.
	^ adaptor
		  call: 'widget.invoke'
		  params: (Dictionary new
				   at: 'id' put: id;
				   at: 'selector' put: aSelector;
				   at: 'args' put: anArray asArray;
				   yourself)
]

{ #category : 'private' }
PNAppKitWidget >> subscribe: anEventName do: aBlock [
	"Register aBlock to fire when the shell emits the named event for me,
	and ask the shell to start emitting that event."

	self ensureNotDestroyed.
	adaptor onEvent: id named: anEventName do: aBlock.
	adaptor
		call: 'widget.subscribe'
		params: (Dictionary new
				 at: 'id' put: id;
				 at: 'event' put: anEventName;
				 yourself)
]

{ #category : 'lifecycle' }
PNAppKitWidget >> addChild: aChildWidget role: aRoleString [

	self ensureNotDestroyed.
	adaptor
		call: 'widget.addChild'
		params: (Dictionary new
				 at: 'parentId' put: id;
				 at: 'childId' put: aChildWidget id;
				 at: 'role' put: aRoleString;
				 yourself)
]

{ #category : 'lifecycle' }
PNAppKitWidget >> destroy [
	"Tear down the widget on the shell and forget any event handlers."

	destroyed ifTrue: [ ^ self ].
	destroyed := true.
	adaptor offEvent: id.
	[
	adaptor
		call: 'widget.destroy'
		params: (Dictionary new at: 'id' put: id; yourself) ]
		on: Error
		do: [ :ignored | ]
]

{ #category : 'lifecycle' }
PNAppKitWidget >> isDestroyed [

	^ destroyed
]

{ #category : 'private' }
PNAppKitWidget >> ensureNotDestroyed [

	destroyed ifTrue: [
		self error:
			'Widget ' , id , ' has been destroyed and cannot accept messages' ]
]

{ #category : 'frames' }
PNAppKitWidget >> frame: aRectangle [
	"Convenience: ship a Pharo Rectangle as { x, y, w, h }."

	self
		setProp: 'frame'
		value: (Dictionary new
				 at: 'x' put: aRectangle origin x;
				 at: 'y' put: aRectangle origin y;
				 at: 'w' put: aRectangle extent x;
				 at: 'h' put: aRectangle extent y;
				 yourself)
]

{ #category : 'frames' }
PNAppKitWidget >> autoresizingMask: anArrayOfSymbols [
	"AppKit autoresizing mask. Accepts any combination of:
	#width, #height, #minX, #maxX, #minY, #maxY.
	Only meaningful for NSView-rooted widgets."

	self
		setProp: 'autoresizingMask'
		value: (anArrayOfSymbols collect: [ :s | s asString ]) asArray
]

{ #category : 'frames' }
PNAppKitWidget >> fillSuperview [
	"Tell the shell that this widget should grow with its container.
	Equivalent to setting autoresizingMask to [width, height]."

	^ self autoresizingMask: #( width height )
]
