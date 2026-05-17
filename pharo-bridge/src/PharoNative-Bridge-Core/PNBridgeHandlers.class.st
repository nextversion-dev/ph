"
I am PNBridgeHandlers, the read-only JSON-RPC handler set for the v1 native
System Browser. PNBridgeServer parses the incoming JSON and calls
#dispatch:with: on me. Each public ``handle*`` method returns plain Arrays
and Dictionaries that STONJSON can serialize directly.

Method namespaces, all read-only in v1:
   system.listPackages       () -> [{ name, classCount }]
   package.listClasses       ({ package })
                              -> [{ name, side: 'instance'|'class', superclass }]
   class.listProtocols       ({ class, side })
                              -> [{ name, methodCount }]
   protocol.listMethods      ({ class, side, protocol })
                              -> [selector]
   method.getSource          ({ class, side, selector })
                              -> { source, category, author, timestamp }
"
Class {
	#name : 'PNBridgeHandlers',
	#superclass : 'Object',
	#category : 'PharoNative-Bridge-Core',
	#package : 'PharoNative-Bridge-Core'
}

{ #category : 'dispatch' }
PNBridgeHandlers >> dispatch: methodName with: paramsDict [
	"Map a JSON-RPC method name to one of my handler selectors."

	methodName = 'system.listPackages' ifTrue: [ ^ self handleListPackages: paramsDict ].
	methodName = 'package.listClasses' ifTrue: [ ^ self handleListClasses: paramsDict ].
	methodName = 'class.listProtocols' ifTrue: [ ^ self handleListProtocols: paramsDict ].
	methodName = 'protocol.listMethods' ifTrue: [ ^ self handleListMethods: paramsDict ].
	methodName = 'method.getSource' ifTrue: [ ^ self handleGetSource: paramsDict ].
	^ self error: 'Unknown method: ' , methodName
]

{ #category : 'private' }
PNBridgeHandlers >> classFromName: aString side: sideString [
	"Resolve a class name (instance- or class-side) to a Behavior, or nil
	if the name doesn't refer to a known class."

	| behavior |
	behavior := Smalltalk classNamed: aString asSymbol.
	behavior ifNil: [ ^ nil ].
	sideString = 'class' ifTrue: [ ^ behavior classSide ].
	^ behavior instanceSide
]

{ #category : 'handlers' }
PNBridgeHandlers >> handleGetSource: paramsDict [

	| className side selector behavior method source category author timestamp |
	className := paramsDict at: 'class' ifAbsent: [
		             ^ self error: 'class is required' ].
	side := paramsDict at: 'side' ifAbsent: [ 'instance' ].
	selector := paramsDict at: 'selector' ifAbsent: [
		            ^ self error: 'selector is required' ].
	behavior := self classFromName: className side: side.
	behavior ifNil: [ ^ self error: 'Unknown class: ' , className ].
	method := behavior compiledMethodAt: selector asSymbol ifAbsent: [ nil ].
	method ifNil: [ ^ self error: 'No method: ' , className , '>>' , selector ].
	source := [ method sourceCode ]
		          on: Error
		          do: [ :ex | '" source unavailable: ' , ex messageText , ' "' ].
	category := [ method protocolName asString ]
		            on: Error
		            do: [ :ex | '' ].
	author := [ method author asString ]
		          on: MessageNotUnderstood
		          do: [ :ex | '' ].
	timestamp := [ method timeStamp asString ]
		             on: MessageNotUnderstood
		             do: [ :ex | '' ].
	^ Dictionary new
		  at: 'source' put: source;
		  at: 'category' put: category;
		  at: 'author' put: author;
		  at: 'timestamp' put: timestamp;
		  yourself
]

{ #category : 'handlers' }
PNBridgeHandlers >> handleListClasses: paramsDict [

	| packageName package classes |
	packageName := paramsDict at: 'package' ifAbsent: [
		               ^ self error: 'package is required' ].
	package := PackageOrganizer default
		           packageNamed: packageName
		           ifAbsent: [ nil ].
	package ifNil: [ ^ Array new ].
	classes := package definedClasses
		           asSortedCollection: [ :a :b | a name < b name ].
	^ Array streamContents: [ :s |
		  classes do: [ :each |
			  | superclassName |
			  superclassName := each superclass
				                    ifNil: [ '' ]
				                    ifNotNil: [ :sc | sc name asString ].
			  s nextPut: (Dictionary new
					   at: 'name' put: each name asString;
					   at: 'side' put: 'instance';
					   at: 'superclass' put: superclassName;
					   yourself).
			  each classSide ifNotNil: [ :meta |
					  meta hasMethods ifTrue: [
						  s nextPut: (Dictionary new
								   at: 'name' put: each name asString;
								   at: 'side' put: 'class';
								   at: 'superclass'
								   put: (meta superclass
										    ifNil: [ '' ]
										    ifNotNil: [ :sc | sc name asString ]);
								   yourself) ] ] ] ]
]

{ #category : 'handlers' }
PNBridgeHandlers >> handleListMethods: paramsDict [

	| className side protocolName behavior selectors |
	className := paramsDict at: 'class' ifAbsent: [
		             ^ self error: 'class is required' ].
	side := paramsDict at: 'side' ifAbsent: [ 'instance' ].
	protocolName := paramsDict at: 'protocol' ifAbsent: [ nil ].
	behavior := self classFromName: className side: side.
	behavior ifNil: [ ^ Array new ].
	selectors := protocolName
		             ifNil: [ behavior selectors ]
		             ifNotNil: [ behavior selectorsInProtocol: protocolName ].
	^ (selectors asSortedCollection: [ :a :b | a asString < b asString ])
		  asArray collect: [ :sel | sel asString ]
]

{ #category : 'handlers' }
PNBridgeHandlers >> handleListPackages: paramsDict [

	| packages |
	packages := PackageOrganizer default packages
		            asSortedCollection: [ :a :b | a name < b name ].
	^ packages asArray collect: [ :pkg |
		  Dictionary new
			  at: 'name' put: pkg name asString;
			  at: 'classCount' put: pkg definedClasses size;
			  yourself ]
]

{ #category : 'handlers' }
PNBridgeHandlers >> handleListProtocols: paramsDict [

	| className side behavior |
	className := paramsDict at: 'class' ifAbsent: [
		             ^ self error: 'class is required' ].
	side := paramsDict at: 'side' ifAbsent: [ 'instance' ].
	behavior := self classFromName: className side: side.
	behavior ifNil: [ ^ Array new ].
	^ ((behavior protocols
		    asSortedCollection: [ :a :b | a name asString < b name asString ])
		   asArray) collect: [ :protocol |
		  Dictionary new
			  at: 'name' put: protocol name asString;
			  at: 'methodCount'
			  put: (behavior selectorsInProtocol: protocol name) size;
			  yourself ]
]
