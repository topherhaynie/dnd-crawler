extends RefCounted
class_name ProfileModel

## Profile data model.
##
## Owns the authoritative profiles array. Held by ProfileManager and shared
## with ProfileService via injection before _ready() runs so that all reads
## and writes operate on the same Array reference.

var profiles: Array = []
