# CRDT Playground

A proof-of-concept implementation of Victor Grishchenko's [Causal Trees][trees] CRDT, which I'll gradually try to whittle into semi-production shape. State-based (CvRDT) implementation. Features many tweaks, including a synced identifier map, atom references, and priority atoms. Also uses Lamport timestamps instead of "awareness". Written in Swift. Includes a visualizer, a text data type, a shape data type, and imitation peers, so you can clearly see how merging functions in a P2P environment. Also includes a (VERY NON-PRODUCTION) iOS text editing demo over CloudKit. Everything should be *O*(*n*log*n*)!

<img src="mac-main.gif" />

<img src="mac-shapes.gif" />

<img src="mac-revisions.gif" />

<img src="iphone.gif" />

<img src="mac-yarns.gif" />

[trees]: http://www.ds.ewi.tudelft.nl/~victor/articles/ctre.pdf
