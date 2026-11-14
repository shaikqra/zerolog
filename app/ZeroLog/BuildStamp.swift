/// Which build is on this phone. The installable-build workflow overwrites
/// this file with the real commit and time before compiling; a local or
/// test build says "dev". Shown at the bottom of Settings so "is this the
/// new version?" is answered by reading, not by squinting at the 3D body.
enum BuildStamp {
    static let commit = "dev"
    static let built = ""
}
