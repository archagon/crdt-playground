# TODO

Contained herein are the most important TODOs that need to be checked off before I can start dipping my toe in the water of actually using this thing in my apps.

* Commits need to be streamlined: don't commit unless necessary
* BinaryEncodable needs to be figured out and correctly patched + integrated
* Non-priority next to priority sibling insertion needs to be implemented more carefully
* String CRDT needs to be rock-solid, emojis, cursors, and all
* Ranged inserts and deletes
* Code needs to be profiled on iOS, especially for large data files
* Need to figure out "soft verification" for large number of sites
* More throws and error handling in CRDT classes; less asserts
* Migration needs to be thought about
* Guaranteed consistency needs to be thought about (what if the model designer makes a mistake? merge [CRDTCausalTreesWeave] must *always* succeed, and any higher layers [e.g. CausalTreeBezierWrapper] need to deal with developer error in a reasonable manner)
