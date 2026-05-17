"Install the PharoNative bridge packages into the running image.

The repository path is provided by the install.sh wrapper via the
PHARO_BRIDGE_REPO environment variable so the script does not have to
rely on the image's current working directory."

| repoPath |
repoPath := OSEnvironment current
	            at: 'PHARO_BRIDGE_REPO'
	            ifAbsent: [
		            self error:
			            'PHARO_BRIDGE_REPO env var is required. Run install.sh.' ].

Transcript
	show: 'Installing PharoNativeBridge from: ';
	show: repoPath;
	cr;
	flush.

"On re-install, Metacello will skip new packages added to the baseline
unless we drop the cached spec first. resetRegistry clears the in-image
project cache; removing the BaselineOf class forces Metacello to recompile
BaselineOfPharoNativeBridge>>baseline: from the tonel source."
[ MetacelloProjectRegistry resetRegistry ]
	on: Error
	do: [ :ignored | ].
(Smalltalk classNamed: #BaselineOfPharoNativeBridge) ifNotNil: [ :cls |
	[ cls removeFromSystem ] on: Error do: [ :ignored | ] ].

Metacello new
	baseline: 'PharoNativeBridge';
	repository: 'tonel://' , repoPath , '/src';
	onConflictUseIncoming;
	load.

Transcript
	show: 'PharoNativeBridge installed.';
	cr;
	flush.
