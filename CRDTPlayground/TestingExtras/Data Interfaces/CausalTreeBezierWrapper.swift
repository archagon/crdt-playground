//
//  CausalTreeBezierWrapper.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-25.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import AppKit

/* The Drawing Causal Tree looks a lot different from the Text Causal Tree. Our goal is to allow shapes to be grouped
 with their points and properties in the weave for O(shape) recreation. An atom can either be a shape, a point,
 an operation, or an attribute. Shapes can be caused only by other shapes as well as the zero atom; their weave order
 is their drawing order. On creation, shapes receive a blank ("root") atom, and all atoms relating to the shape will be
 linked to it. Points can be caused only by other points as well as the point start sentinel, for the first point
 in a shape; their weave order is their connection order. Start and end sentinel points are added to the root atom
 on creation to enable ranged operations, e.g. "shift all". Operations can be caused only by other operations in their
 type group as well as a point atom or root atom, for the first operation in a chain. (Some operations types, e.g.
 delete, can have multiple "chains", while most should be limited to a single chain.) Operation types are currently
 divided into transformations (move) and deletions. Operations must be priority atoms. The same goes for attributes,
 which can be thought of as register-type operations; the last weave value in a chain is taken as the definitive one.
 Each attribute is considered its own type group; attributes of different types shall not mix causally. Finally, since
 we'll be traversing chains of operations quite frequently, we want to make sure that we can find the end of a chain in
 O(number of operations in chain) time and not O(N) time, which is what would be required if we do the usual awareness
 and causal block derivation dance. Because our data is well-structured, we can figure this out by defining delimeters
 for each point/shape section and then stopping weave traversal when we reach them. */

/* How do we move an entire shape? Three possible ways:
 > move each individual point
 > add a "move" operation
 > implicitly, by moving the first point
 Moving each individual point is bad, b/c if another peer adds points then they won't get moved. So the choice is
 between an implicit operation and an explicit operation. Text editing works via implicit operations, i.e. every
 new character, instead of overwriting the previous character, implicitly shifts over every successive character.
 Here, for the sake of completeness, let's use operations. */

// this is where the CT structure is mapped to our local model
// AB: because I didn't want to deal with the extra complexity, shapes can't be deleted at the moment -- only points
// (in terms of user-facing stuff, that is: under the hood the CT preserves everything anyway)
class CausalTreeBezierWrapper
{
    // these will persist forever, but are expensive
    typealias PermPointId = (CausalTreeBezierT.SiteUUIDT, YarnIndex)
    
    // these are very fast, but will only persist for the current state of the CT, so any mutation or merge will clobber them
    typealias TempPointId = WeaveIndex
    typealias TempShapeId = WeaveIndex
    
    private unowned var crdt: CausalTreeBezierT
    
    init(crdt: CausalTreeBezierT) {
        self.crdt = crdt
    }
    
    /// **Complexity:** O(1)
    func permPoint(forPoint p: WeaveIndex) -> PermPointId
    {
        let aid = crdt.weave.weave()[Int(p)].id
        let owner = crdt.siteIndex.site(aid.site)!
        
        return (owner, aid.index)
    }
    
    /// **Complexity:** O(weave)
    func point(forPermPoint p: PermPointId) -> WeaveIndex
    {
        let owner = crdt.siteIndex.siteMapping()[p.0]!
        let aid = AtomId(site: owner, index: p.1)
        let index = crdt.weave.atomWeaveIndex(aid)!
        
        return index
    }
    
    enum ValidationError: Error
    {
        case noRootAfterShape
        case wrongParent
        case mixedUpType
        case unknownAtomInShape
        case nonPointInPointBlock
        case excessiveChains //shapes and atoms can only have one of each type of chain, e.g. points, transform operations, etc.
        case unexpectedAtom
    }
    
    // this is in addition to the low-level CT validation b/c our rules are more strict on this higher level
    // WARNING: not comprehensive, errors might still seep through
    /// **Complexity:** O(weave)
    func validate() throws
    {
        func vassert(_ v: Bool, _ e: ValidationError) throws
        {
            if !v { throw e }
        }
        
        let weave = crdt.weave.weave()
        
        var i = 1 //skip start atom
        
        while i < weave.count
        {
            processShapeBlock: if case .shape = weave[i].value
            {
                // iterating shape block
                let spi = i
                i += 1
                
                try vassert(weave[i].value.id == DrawDatum.Id.null, .noRootAfterShape)
                try vassert(weave[i].type == .valuePriority, .mixedUpType)
                try vassert(weave[i].cause == weave[spi].id, .wrongParent)
                
                let si = i
                i += 1
                
                // TODO:
                //var pendingRanges
                
                processShape: while !atomDelimitsShape(WeaveIndex(i))
                {
                    try vassert(weave[i].cause == weave[si].id, .wrongParent)
                    
                    var foundAtomChain = false
                    var operationChainCount = 0
                    var attributeChainCount = 0
                    
                    processPointBlock: if case .pointSentinelStart = weave[i].value
                    {
                        try vassert(!foundAtomChain, .excessiveChains)
                        foundAtomChain = true
                        
                        // iterating point block
                        //let psi = i
                        i += 1
                        
                        while weave[i].value.id != DrawDatum.Id.pointSentinelEnd
                        {
                            try vassert(weave[i].value.point, .nonPointInPointBlock)
                            try vassert(weave[i].type == .value, .mixedUpType)
                            
                            let pi = i
                            i += 1
                            
                            processPoint: while !atomDelimitsPoint(WeaveIndex(i))
                            {
                                var operationChainCount = 0
                                var attributeChainCount = 0
                                
                                if weave[i].value.operation || weave[i].value.attribute
                                {
                                    try vassert(weave[i].cause == weave[pi].id, .wrongParent)
                                    try vassert(weave[i].type == .valuePriority, .mixedUpType)
                                    
                                    if weave[i].value.operation
                                    {
                                        try vassert(operationChainCount < 1, .excessiveChains)
                                        operationChainCount += 1
                                    }
                                    else
                                    {
                                        try vassert(attributeChainCount < 1, .excessiveChains)
                                        attributeChainCount += 1
                                    }
                                    
                                    let oi = i
                                    i += 1
                                    
                                    // operations/attributes can only be chained to other operations/attributes of the same type
                                    while i < weave.count && weave[i].value.id == weave[oi].value.id
                                    {
                                        i += 1
                                    }
                                }
                                else if weave[i].type == .delete
                                {
                                    try vassert(weave[i].cause == weave[pi].id, .wrongParent)
                                    try vassert(weave[i].value.id == DrawDatum.Id.null, .mixedUpType)
                                    
                                    // we know deletes are childless and that this has (presumably) been verified
                                    i += 1
                                }
                            }
                        }
                        
                        i += 1
                    }
                    else if weave[i].value.attribute || weave[i].value.operation
                    {
                        try vassert(weave[i].type == .valuePriority, .mixedUpType)
                        
                        if weave[i].value.operation
                        {
                            try vassert(operationChainCount < 1, .excessiveChains)
                            operationChainCount += 1
                        }
                        else
                        {
                            try vassert(attributeChainCount < 1, .excessiveChains)
                            attributeChainCount += 1
                        }
                        
                        let oi = i
                        i += 1
                        
                        // operations/attributes can only be chained to other operations/attributes of the same type
                        while i < weave.count && weave[i].value.id == weave[oi].value.id
                        {
                            i += 1
                        }
                    }
                    else
                    {
                        try vassert(false, .unknownAtomInShape)
                    }
                }
            }
            else if weave[i].type == .end
            {
                break
            }
            else
            {
                try vassert(false, .unexpectedAtom)
            }
        }
        
        // needs to be covered:
        // * top level: shapes and null nodes, with shape-node-shape-node structure
        // * null nodes have point chain w/start and end sentinels
        // * nothing attaches to end sentinel; end sentinel attaches to start sentinel
        // * operation chains are all the same type
        // * operations are priority
        // * operations are only parented to shapes, points, or null atoms
        // * range references must be within the same shape
        // * value types don't interfere with built-in types
    }
    
    /// **Complexity:** O(weave)
    func shapesCount() -> Int
    {
        return Int(shapes().count)
    }
    
    /// **Complexity:** O(shape)
    func shapeCount(_ s: TempShapeId, withInvalid: Bool = false) -> Int
    {
        let points = allPoints(forShape: s)
        
        return points.reduce(0, { p,v in (withInvalid || self.pointIsValid(v)) ? p + 1 : p })
    }
    
    /// **Complexity:** O(shape)
    func pointValue(_ p: TempPointId) -> NSPoint?
    {
        if pointIsValid(p)
        {
            let pos = rawValueForPoint(p)
            
            let tPoint = transformForPoint(p)
            
            return pos.applying(tPoint)
        }
        else
        {
            return nil
        }
    }

    /// **Complexity:** O(shape)
    func nextValidPoint(afterPoint p: TempPointId, looping: Bool = true) -> TempPointId?
    {
        let shapeIndex = shapeForPoint(p)
        
        let points = allPoints(forShape: shapeIndex)
        
        let startingIndex: Int
        let weave = crdt.weave.weave()
        
        if case .pointSentinelStart = weave[Int(p)].value
        {
            startingIndex = 0 - 1
        }
        else if case .pointSentinelEnd = weave[Int(p)].value
        {
            startingIndex = points.count - 1
        }
        else
        {
            startingIndex = points.index(of: p)!
        }
        
        for i0 in 0..<points.count
        {
            var i = startingIndex + 1 + i0
            
            if !looping && i >= points.count
            {
                return nil
            }

            i = (((i % points.count) + points.count) % points.count)
            
            let index = points[i]

            if pointIsValid(index)
            {
                return index
            }
        }
        
        return nil
    }
    
    /// **Complexity:** O(shape)
    func nextValidPoint(beforePoint p: TempPointId, looping: Bool = true) -> TempPointId?
    {
        let shapeIndex = shapeForPoint(p)
        
        let points = allPoints(forShape: shapeIndex)
        
        let startingIndex: Int
        let weave = crdt.weave.weave()
        
        if case .pointSentinelStart = weave[Int(p)].value
        {
            startingIndex = 0
        }
        else if case .pointSentinelEnd = weave[Int(p)].value
        {
            startingIndex = points.count
        }
        else
        {
            startingIndex = points.index(of: p)!
        }
        
        for i0 in 0..<points.count
        {
            var i = startingIndex - 1 - i0
            
            if !looping && i < 0
            {
                return nil
            }
            
            i = (((i % points.count) + points.count) % points.count)
            
            let index = points[i]
            
            if pointIsValid(index)
            {
                return index
            }
        }
        
        return nil
    }

    /// **Complexity:** O(shape)
    func isFirstPoint(_ p: TempPointId) -> Bool
    {
        return nextValidPoint(beforePoint: p, looping: false) == nil
    }

    /// **Complexity:** O(shape)
    func isLastPoint(_ p: TempPointId) -> Bool
    {
        return nextValidPoint(afterPoint: p, looping: false) == nil
    }

    /// **Complexity:** O(shape)
    func firstPoint(inShape s: TempShapeId) -> TempPointId?
    {
        let start = startSentinel(forShape: s)
        
        return nextValidPoint(afterPoint: start)
    }

    /// **Complexity:** O(shape)
    func lastPoint(inShape s: TempShapeId) -> TempPointId?
    {
        let end = endSentinel(forShape: s)
        
        return nextValidPoint(beforePoint: end)
    }

    /// **Complexity:** O(weave)
    func shapes() -> AnyCollection<TempShapeId>
    {
        let weave = crdt.weave.weave().enumerated().lazy
        
        // PERF: I'm not sure to what extent lazy works in this stack, but whatever
        let filter = weave.filter
        {
            if case .shape = $0.1.value
            {
                return true
                
            }
            else
            {
                return false
                
            }
        }.lazy
        
        let filterIds = filter.map
        {
            return WeaveIndex($0.offset)
        }.lazy
        
        return AnyCollection(filterIds)
    }
    
    /// **Complexity:** O(shape)
    func shape(forPoint p: TempPointId) -> TempPointId
    {
        return shapeForPoint(p)
    }
    
    /// **Complexity:** O(shape)
    func points(forShape s: TempShapeId) -> AnyCollection<TempPointId>
    {
        let points = allPoints(forShape: s)
        
        // PERF: I'm not sure to what extent lazy works in this stack, but whatever
        let validPoints = points.filter { self.pointIsValid($0) }.lazy
        
        return AnyCollection(validPoints)
    }

    /// **Complexity:** O(weave)
    func addShape(atX x: CGFloat, y: CGFloat) -> TempPointId
    {
        let shapeParent: TempShapeId
        
        if let theLastShape = lastShape()
        {
            shapeParent = theLastShape
        }
        else
        {
            shapeParent = 0
        }
        
        let shape = crdt.weave.addAtom(withValue: .shape, causedBy: crdt.weave.weave()[Int(shapeParent)].id, atTime: Clock(CACurrentMediaTime() * 1000))!
        let root = crdt.weave.addAtom(withValue: .null, causedBy: shape.0, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)!
        let startSentinel = crdt.weave.addAtom(withValue: .pointSentinelStart, causedBy: root.0, atTime: Clock(CACurrentMediaTime() * 1000))!
        let endSentinel = crdt.weave.addAtom(withValue: .pointSentinelEnd, causedBy: startSentinel.0, atTime: Clock(CACurrentMediaTime() * 1000))!
        let firstPoint = crdt.weave.addAtom(withValue: .point(pos: NSMakePoint(x, y)), causedBy: startSentinel.0, atTime: Clock(CACurrentMediaTime() * 1000))!
        
        updateAttributes(rounded: arc4random_uniform(2) == 0, forPoint: firstPoint.1)
        
        return firstPoint.1
    }
    
    /// **Complexity:** O(weave)
    func updateShape(_ s: TempShapeId, withDelta delta: NSPoint)
    {
        let weave = crdt.weave.weave()
        
        let datum = DrawDatum.opTranslate(delta: delta)
        
        if let lastOp = lastOperation(forShape: s, ofType: .opTranslate)
        {
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: weave[Int(lastOp)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
        else
        {
            let r = root(forShape: s)
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: weave[Int(r)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
    }

    /// **Complexity:** O(weave)
    func updateShapePoint(_ p: TempPointId, withDelta delta: NSPoint)
    {
        updateShapePoints((start: p, end: p), withDelta: delta)
    }

    /// **Complexity:** O(weave)
    func updateShapePoints(_ points: (start: TempPointId, end: TempPointId), withDelta delta: NSPoint)
    {
        assert(shapeForPoint(points.start) == shapeForPoint(points.end), "start and end do not share same shape")
        assert(points.start <= points.end, "start and end are not correctly ordered")
        
        let weave = crdt.weave.weave()
        
        let datum = DrawDatum.opTranslate(delta: delta)
        
        if let lastOp = lastOperation(forPoint: points.start, ofType: .opTranslate)
        {
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: weave[Int(lastOp)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true, withReference: weave[Int(points.end)].id)
        }
        else
        {
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: weave[Int(points.start)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true, withReference: weave[Int(points.end)].id)
        }
    }
    
    /// **Complexity:** O(weave)
    func deleteShapePoint(_ p: TempPointId)
    {
        let _ = crdt.weave.deleteAtom(crdt.weave.weave()[Int(p)].id, atTime: Clock(CACurrentMediaTime() * 1000))
    }

    /// **Complexity:** O(weave)
    func addShapePoint(afterPoint pointId: TempPointId, withBounds bounds: NSRect? = nil) -> TempPointId
    {
        let minLength: Scalar = 10
        let maxLength: Scalar = 30
        let maxCCAngle: Scalar = 70
        let maxCAngle: Scalar = 20
        let offset: CGFloat = 4

        let weave = crdt.weave.weave()
        
        let pointIndex = pointId
        let shapeIndex = shapeForPoint(pointIndex)
        
        assert(pointIsValid(pointIndex))

        let length = minLength + Scalar(arc4random_uniform(UInt32(maxLength - minLength)))

        let point = rawValueForPoint(pointIndex)
        
        let previousPoint = nextValidPoint(beforePoint: pointId)
        let nextPoint = nextValidPoint(afterPoint: pointId, looping: false)

        let pointIsOnlyPoint = shapeCount(shapeIndex) == 1
        let pointIsEndPoint = isLastPoint(pointId)
        let pointIsInsertion = !pointIsOnlyPoint && !pointIsEndPoint

        var newPoint: NSPoint

        addNewPoint: do
        {
            let angle: Scalar
            var vec: Vector2

            if pointIsOnlyPoint
            {
                let fakePreviousPoint: NSPoint = NSMakePoint(point.x - CGFloat(length), point.y)
                
                angle = Scalar(arc4random_uniform(360))
                vec = Vector2(point) - Vector2(fakePreviousPoint)
            }
            else if pointIsEndPoint
            {
                let previousPointValue = rawValueForPoint(previousPoint!)
                
                angle = -maxCAngle + Scalar(arc4random_uniform(UInt32(maxCAngle + maxCCAngle)))
                vec = Vector2(point) - Vector2(previousPointValue)
            }
            else
            {
                let nextPointValue = rawValueForPoint(nextPoint!)
                
                angle = -maxCAngle + Scalar(arc4random_uniform(UInt32(maxCAngle + maxCCAngle)))
                vec = Vector2(nextPointValue) - Vector2(point)
            }

            vec = vec.normalized() * length
            vec = vec.rotated(by: angle * ((2*Scalar.pi)/360))

            let tempNewPoint = NSMakePoint(point.x + CGFloat(vec.x), point.y + CGFloat(vec.y))
            if let b = bounds
            {
//                let t = transform(forOperations: operations(forShape: shapeIndex)).inverted()
//                let tBounds = b.applying(t)
//
//                newPoint = NSMakePoint(min(max(tempNewPoint.x, tBounds.minX + offset), tBounds.maxX - offset),
//                                       min(max(tempNewPoint.y, tBounds.minY + offset), tBounds.maxY - offset))
                newPoint = tempNewPoint
            }
            else
            {
                newPoint = tempNewPoint
            }
        }

        mutate: do
        {
            if pointIsInsertion
            {
                let nextPointValue = rawValueForPoint(nextPoint!)

                //a dot normalized b
                let vOld = Vector2(nextPointValue) - Vector2(point)
                let vNew = Vector2(newPoint) - Vector2(point)
                let vProj = (vOld.normalized() * vNew.dot(vOld.normalized()))

                let endPoint = endSentinel(forShape: shapeIndex)
                
                updateShapePoints((start: nextPoint!, end: endPoint), withDelta: NSPoint(vProj))
            }

            let newAtom = crdt.weave.addAtom(withValue: DrawDatum.point(pos: newPoint), causedBy: weave[Int(pointId)].id, atTime: Clock(CACurrentMediaTime() * 1000))!
            updateAttributes(rounded: arc4random_uniform(2) == 0, forPoint: newAtom.1)
            
            return newAtom.1
        }
    }

    /// **Complexity:** O(shape)
    func attributes(forShape s: TempShapeId) -> (NSColor)
    {
        if let op = lastOperation(forShape: s, ofType: .attrColor)
        {
            if case .attrColor(let color) = crdt.weave.weave()[Int(op)].value
            {
                return NSColor(red: color.rf, green: color.gf, blue: color.bf, alpha: color.af)
            }
            else
            {
                assert(false, "no attribute value found in attribute atom")
                return NSColor.gray
            }
        }
        else
        {
            // default
            return NSColor.gray
        }
    }

    /// **Complexity:** O(point)
    func attributes(forPoint p: TempPointId) -> (Bool)
    {
        if let op = lastOperation(forPoint: p, ofType: .attrRound)
        {
            if case .attrRound(let round) = crdt.weave.weave()[Int(op)].value
            {
                return round
            }
            else
            {
                assert(false, "no attribute value found in attribute atom")
                return false
            }
        }
        else
        {
            // default
            return false
        }
    }

    /// **Complexity:** O(weave)
    func updateAttributes(color: NSColor, forShape s: TempShapeId)
    {
        let weave = crdt.weave.weave()
        
        if let op = lastOperation(forShape: s, ofType: .attrColor)
        {
            let colorStruct = DrawDatum.ColorTuple(r: color.redComponent, g: color.greenComponent, b: color.blueComponent, a: color.alphaComponent)
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrColor(colorStruct), causedBy: weave[Int(op)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
        else
        {
            let rootIndex = root(forShape: s)
            
            let colorStruct = DrawDatum.ColorTuple(r: color.redComponent, g: color.greenComponent, b: color.blueComponent, a: color.alphaComponent)
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrColor(colorStruct), causedBy: weave[Int(rootIndex)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
    }

    /// **Complexity:** O(weave)
    func updateAttributes(rounded: Bool, forPoint p: TempPointId)
    {
        let weave = crdt.weave.weave()
        
        if let op = lastOperation(forPoint: p, ofType: .attrRound)
        {
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrRound(rounded), causedBy: weave[Int(op)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
        else
        {
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrRound(rounded), causedBy: weave[Int(p)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
    }
    
    ////////////////////////////////
    // MARK: - CT-Specific Queries -
    ////////////////////////////////
    
    // excluding sentinels
    /// **Complexity:** O(shape)
    func shapeData(s: TempShapeId) -> [(range: CountableClosedRange<WeaveIndex>, transform: CGAffineTransform, deleted: Bool)]
    {
        let weave = crdt.weave.weave()
        
        assertType(s, .shape)
        
        var i = Int(s + 1)
        var shapeTransform = CGAffineTransform.identity
        var points: [(range: CountableClosedRange<WeaveIndex>, transform: CGAffineTransform, deleted: Bool)] = []
        
        getShapeTransform: do
        {
            while i < weave.count
            {
                if atomDelimitsPoint(WeaveIndex(i))
                {
                    break getShapeTransform
                }
                else if atomDelimitsShape(WeaveIndex(i))
                {
                    break getShapeTransform
                }
                
                if case .opTranslate(let delta) = weave[i].value
                {
                    shapeTransform = shapeTransform.concatenating(CGAffineTransform(translationX: delta.x, y: delta.y))
                }
                
                i += 1
            }
        }
        
        iteratePoints: do
        {
            var transformedRanges: [(t: CGAffineTransform, until: AtomId)] = []
            var runningPointData: (start: WeaveIndex, deleted: Bool)! = nil
            
            func commitPoint(withEndIndex: WeaveIndex)
            {
                if runningPointData == nil
                {
                    return
                }
                
                commit: do
                {
                    if weave[Int(runningPointData.start)].value.pointSentinel
                    {
                        break commit //don't add sentinels to return array, but still use them for processing
                    }
                    
                    var transform = CGAffineTransform.identity
                    
                    transform = transform.concatenating(shapeTransform)
                    
                    for t in transformedRanges
                    {
                        transform = transform.concatenating(t.t)
                    }
                    
                    points.append((runningPointData.start...(withEndIndex - 1), transform, runningPointData.deleted))
                }
                
                clear: do
                {
                    for i in (0..<transformedRanges.count).reversed()
                    {
                        let t = transformedRanges[i]
                        
                        if t.until == weave[Int(runningPointData.start)].id
                        {
                            transformedRanges.remove(at: i)
                        }
                    }
                    
                    runningPointData = nil
                }
            }
            
            func startNewPoint(withStartIndex: WeaveIndex)
            {
                assert(runningPointData == nil)
                runningPointData = (withStartIndex, false)
            }
            
            while i < weave.count
            {
                if atomDelimitsShape(WeaveIndex(i)) //AB: this one has to go first
                {
                    commitPoint(withEndIndex: WeaveIndex(i))
                    i += 1 //why not
                    break iteratePoints
                }
                else if atomDelimitsPoint(WeaveIndex(i))
                {
                    commitPoint(withEndIndex: WeaveIndex(i))
                    startNewPoint(withStartIndex: WeaveIndex(i))
                    i += 1
                    continue
                }
                
                if case .opTranslate(let delta) = weave[i].value
                {
                    transformedRanges.append((CGAffineTransform(translationX: delta.x, y: delta.y), weave[i].reference == NullAtomId ? weave[Int(runningPointData.start)].id : weave[i].reference))
                }
                if weave[i].type == .delete
                {
                    runningPointData.deleted = true
                }
                
                i += 1
            }
        }
        
        return points
    }
    
    // Complexity: O(N Tail) + O(Shape)
    /// **Complexity:** O(shape) + O(weave tail)
    func lastShape() -> TempShapeId?
    {
        let weave = crdt.weave.weave()
        
        for i in (0..<weave.count).reversed()
        {
            if case .shape = weave[i].value
            {
                return WeaveIndex(i)
            }
        }
        
        return nil
    }
    
    // excluding sentinels
    /// **Complexity:** O(shape)
    func allPoints(forShape s: TempShapeId) -> [TempPointId]
    {
        let indexArray = shapeData(s: s).map { $0.range.lowerBound }
        
        return Array(indexArray)
    }
    
    /// **Complexity:** O(1)
    func root(forShape s: TempShapeId) -> WeaveIndex
    {
        assertType(s, .shape)
        
        return s + 1
    }
    
    /// **Complexity:** O(shape)
    func startSentinel(forShape s: TempShapeId) -> TempPointId
    {
        let weave = crdt.weave.weave()
        
        assertType(s, .shape)
        
        for i in Int(s + 1)..<weave.count
        {
            if atomDelimitsShape(WeaveIndex(i))
            {
                break
            }
            
            if case .pointSentinelStart = weave[i].value
            {
                return WeaveIndex(i)
            }
        }
        
        assert(false)
        return WeaveIndex(NullIndex)
    }
    
    /// **Complexity:** O(shape)
    func endSentinel(forShape s: TempShapeId) -> TempPointId
    {
        let weave = crdt.weave.weave()
        
        assertType(s, .shape)
        
        for i in Int(s + 1)..<weave.count
        {
            if atomDelimitsShape(WeaveIndex(i))
            {
                break
            }
            
            if case .pointSentinelEnd = weave[i].value
            {
                return WeaveIndex(i)
            }
        }
        
        assert(false)
        return WeaveIndex(NullIndex)
    }
    
    /// **Complexity:** O(shape)
    func lastOperation(forShape s: TempShapeId, ofType t: DrawDatum.Id) -> WeaveIndex?
    {
        let weave = crdt.weave.weave()
        
        assertType(s, .shape)
        
        var lastIndex: Int = -1
        
        for i in Int(s + 1)..<weave.count
        {
            if atomDelimitsShape(WeaveIndex(i))
            {
                break
            }
            if atomDelimitsPoint(WeaveIndex(i))
            {
                break
            }
            
            if weave[i].value.id == t
            {
                lastIndex = i
            }
        }
        
        return (lastIndex == -1 ? nil : WeaveIndex(lastIndex))
    }
    
    /// **Complexity:** O(point)
    func lastOperation(forPoint p: TempPointId, ofType t: DrawDatum.Id) -> WeaveIndex?
    {
        let weave = crdt.weave.weave()
        
        assertType(p, .point)
        
        var lastIndex: Int = -1
        
        for i in Int(p + 1)..<weave.count
        {
            if atomDelimitsShape(WeaveIndex(i))
            {
                break
            }
            if atomDelimitsPoint(WeaveIndex(i))
            {
                break
            }
            
            if weave[i].value.id == t
            {
                lastIndex = i
            }
        }
        
        return (lastIndex == -1 ? nil : WeaveIndex(lastIndex))
    }
    
    /// **Complexity:** O(shape)
    func pointData(_ p: TempPointId) -> (range: CountableClosedRange<WeaveIndex>, transform: CGAffineTransform, deleted: Bool)
    {
        let pointShape = shapeForPoint(p)
        let points = shapeData(s: pointShape)
        
        for point in points
        {
            if point.range.lowerBound == p
            {
                return point
            }
        }
        
        assert(false)
        return (0...0, CGAffineTransform.identity, false)
    }
    
    /// **Complexity:** O(shape)
    func pointIsValid(_ p: TempPointId) -> Bool
    {
        let data = pointData(p)
        
        return !data.deleted
    }
    
    /// **Complexity:** O(1)
    func rawValueForPoint(_ p: TempPointId) -> NSPoint
    {
        let weave = crdt.weave.weave()
        
        assertType(p, .point)
        
        if case .point(let pos) = weave[Int(p)].value
        {
            return pos
        }
        
        assert(false)
        return NSPoint.zero
    }
    
    /// **Complexity:** O(shape)
    func shapeForPoint(_ p: TempPointId) -> WeaveIndex
    {
        let weave = crdt.weave.weave()
        
        assert(weave[Int(p)].value.point)
        
        for i in (0..<Int(p)).reversed()
        {
            if weave[i].value.id == .shape
            {
                return WeaveIndex(i)
            }
        }
        
        assert(false, "could not find shape for point")
        return WeaveIndex(NullIndex)
    }
    
    /// **Complexity:** O(shape)
    func transformForPoint(_ p: TempPointId) -> CGAffineTransform
    {
        let data = pointData(p)

        return data.transform
    }
    
    // AB: in our tree structure, shapes and points are both grouped together into causal blocks, with predictable
    // children; therefore, we can delimit atoms and shapes efficiently and deterministically
    
    /// **Complexity:** O(1)
    private func atomDelimitsPoint(_ i: WeaveIndex) -> Bool
    {
        let atom = crdt.weave.weave()[Int(i)]
        
        if atom.value.point
        {
            return true
        }
        else if case .shape = atom.value
        {
            return true
        }
        else if atom.type == .end
        {
            return true
        }
        else
        {
            return false
        }
    }
    
    /// **Complexity:** O(1)
    private func atomDelimitsShape(_ i: WeaveIndex) -> Bool
    {
        let atom = crdt.weave.weave()[Int(i)]
        
        if case .shape = atom.value
        {
            return true
        }
        else if atom.type == .end
        {
            return true
        }
        else
        {
            return false
        }
    }
    
    /// **Complexity:** O(1)
    private func assertType(_ i: WeaveIndex, _ t: DrawDatum.Id)
    {
        assert({
            let a = crdt.weave.weave()[Int(i)]
            
            if a.value.id == t
            {
                return true
            }
            else
            {
                return false
            }
        }(), "atom has incorrect type")
    }
}
