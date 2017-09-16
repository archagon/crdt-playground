# CRDT Playground

A proof-of-concept implementation of Victor Grishchenko's [Causal Trees][trees] CRDT algorithm/data structure, which I'll gradually try to whittle into semi-production shape. Features some tweaks, including a synced identifier map and priority atoms. Written in Swift. Includes a visualizer, a text data type, and imitation peers, so you can clearly see how merging functions in a P2P environment. Everything seems to work, albeit slowly; the core of the algorithm is O(N), though, so I think it'll all work out in the end!

<img src="Demo.gif" />

[trees]: https://ai2-s2-pdfs.s3.amazonaws.com/6534/c371ef78979d7ed84b6dc19f4fd529caab43.pdf