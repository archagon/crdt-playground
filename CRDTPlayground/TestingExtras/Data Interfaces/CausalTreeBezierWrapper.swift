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
    // NEXT: THESE MUST NOT BE STORED, as they are prone to change on merge from remote
    typealias ShapeId = AtomId
    typealias PointId = AtomId
    
    private unowned var crdt: CausalTreeBezierT
    
    init(crdt: CausalTreeBezierT) {
        self.crdt = crdt
    }
    
    // this is in addition to the low-level CT validation b/c our rules are more strict on this higher level
    func validate() -> Bool
    {
        // top level: shapes and null nodes, with shape-node-shape-node structure
        // null nodes have point chain w/start and end sentinels
        // nothing attaches to end sentinel; end sentinel attaches to start sentinel
        // operation chains are all the same type
        // operations are priority
        // operations are only parented to shapes, points, or null atoms
        // deletion references must be within the same shape
        // value types don't interfere with built-in types
        return false
    }
    
    // Complexity: O(N)
    func shapesCount() -> Int
    {
        return Int(shapes().count)
    }
    
    // Complexity: O(N) to find index, then O(Shape)
    func shapeCount(_ s: ShapeId, withInvalid: Bool = false) -> Int
    {
        let shapeIndex = crdt.weave.atomWeaveIndex(s)!
        let points = allPoints(forShape: shapeIndex)
        
        return points.reduce(0, { p,v in (withInvalid || self.pointIsValid(v)) ? p + 1 : p })
    }
    
    // Complexity: O(N) to find index, then O(Shape)
    func pointValue(_ p: PointId) -> NSPoint?
    {
        let pIndex = crdt.weave.atomWeaveIndex(p)!
        
        if pointIsValid(pIndex)
        {
            let pos = rawValueForPoint(pIndex)
            
            let tPoint = transformForPoint(pIndex)
            
            return pos.applying(tPoint)
        }
        else
        {
            return nil
        }
    }

    // Complexity: O(N) to find index, then O(Shape)
    func nextValidPoint(afterPoint p: PointId, looping: Bool = true) -> PointId?
    {
        let pointIndex = crdt.weave.atomWeaveIndex(p)!
        let shapeIndex = shapeForPoint(pointIndex)
        
        let points = allPoints(forShape: shapeIndex)
        
        let startingIndex: Int
        let weave = crdt.weave.weave()
        
        if case .pointSentinelStart = weave[Int(pointIndex)].value
        {
            startingIndex = 0 - 1
        }
        else if case .pointSentinelEnd = weave[Int(pointIndex)].value
        {
            startingIndex = points.count - 1
        }
        else
        {
            startingIndex = points.index(of: pointIndex)!
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
                return weave[Int(index)].id
            }
        }
        
        return nil
    }
    
    // Complexity: O(N) to find index, then O(Shape)
    func nextValidPoint(beforePoint p: PointId, looping: Bool = true) -> PointId?
    {
        let pointIndex = crdt.weave.atomWeaveIndex(p)!
        let shapeIndex = shapeForPoint(pointIndex)
        
        let points = allPoints(forShape: shapeIndex)
        
        let startingIndex: Int
        let weave = crdt.weave.weave()
        
        if case .pointSentinelStart = weave[Int(pointIndex)].value
        {
            startingIndex = 0
        }
        else if case .pointSentinelEnd = weave[Int(pointIndex)].value
        {
            startingIndex = points.count
        }
        else
        {
            startingIndex = points.index(of: pointIndex)!
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
                return weave[Int(index)].id
            }
        }
        
        return nil
    }

    // Complexity: O(N) to find index, then O(Shape)
    func isFirstPoint(_ p: PointId) -> Bool
    {
        return nextValidPoint(beforePoint: p, looping: false) == nil
    }

    // Complexity: O(N) to find index, then O(Shape)
    func isLastPoint(_ p: PointId) -> Bool
    {
        return nextValidPoint(afterPoint: p, looping: false) == nil
    }

    // Complexity: O(N) to find index, then O(S)
    func firstPoint(inShape s: ShapeId) -> PointId?
    {
        let shapeIndex = crdt.weave.atomWeaveIndex(s)!
        let start = startSentinel(forShape: shapeIndex)
        let weave = crdt.weave.weave()
        let startId = weave[Int(start)].id
        
        return nextValidPoint(afterPoint: startId)
    }

    // Complexity: O(N) to find index, then O(S)
    func lastPoint(inShape s: ShapeId) -> PointId?
    {
        let shapeIndex = crdt.weave.atomWeaveIndex(s)!
        let end = endSentinel(forShape: shapeIndex)
        let weave = crdt.weave.weave()
        let endId = weave[Int(end)].id
        
        return nextValidPoint(beforePoint: endId)
    }

    // Complexity: O(N)
    func shapes() -> AnyCollection<ShapeId>
    {
        let weave = crdt.weave.weave()
        
        // PERF: I'm not sure to what extent lazy works in this stack, but whatever
        let filter = weave.filter({ if case .shape = $0.value { return true } else { return false } }).lazy
        let shapeIds = filter.map({ $0.id }).lazy
        
        return AnyCollection(shapeIds)
    }
    
    // Complexity: O(N) to find index, then O(S)
    func shape(forPoint p: PointId) -> ShapeId
    {
        let pointIndex = crdt.weave.atomWeaveIndex(p)!
        let shapeIndex = shapeForPoint(pointIndex)
        
        return crdt.weave.weave()[Int(shapeIndex)].id
    }
    
    // Complexity: O(N) to find index, then O(S)
    func points(forShape s: ShapeId) -> AnyCollection<PointId>
    {
        let shapeIndex = crdt.weave.atomWeaveIndex(s)!
        let weave = crdt.weave.weave()
        let points = allPoints(forShape: shapeIndex)
        
        // PERF: I'm not sure to what extent lazy works in this stack, but whatever
        let validPoints = points.filter { self.pointIsValid($0) }.lazy
        let validPointIds = validPoints.map { weave[Int($0)].id }.lazy
        
        return AnyCollection(validPointIds)
    }

    // Complexity: O(N)
    func addShape(atX x: CGFloat, y: CGFloat) -> ShapeId
    {
        let shapeParent: ShapeId
        
        if let theLastShape = lastShape()
        {
            shapeParent = crdt.weave.weave()[Int(theLastShape)].id
        }
        else
        {
            shapeParent = AtomId(site: ControlSite, index: 0)
        }
        
        let shape = crdt.weave.addAtom(withValue: .shape, causedBy: shapeParent, atTime: Clock(CACurrentMediaTime() * 1000))!
        let root = crdt.weave.addAtom(withValue: .null, causedBy: shape, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)!
        let startSentinel = crdt.weave.addAtom(withValue: .pointSentinelStart, causedBy: root, atTime: Clock(CACurrentMediaTime() * 1000))!
        let endSentinel = crdt.weave.addAtom(withValue: .pointSentinelEnd, causedBy: startSentinel, atTime: Clock(CACurrentMediaTime() * 1000))!
        let firstPoint = crdt.weave.addAtom(withValue: .point(pos: NSMakePoint(x, y)), causedBy: startSentinel, atTime: Clock(CACurrentMediaTime() * 1000))!
        
        updateAttributes(rounded: arc4random_uniform(2) == 0, forPoint: firstPoint)
        
        return shape
    }
    
    // Complexity: O(N)
    func updateShape(_ s: ShapeId, withDelta delta: NSPoint)
    {
        let shapeStartIndex = crdt.weave.atomWeaveIndex(s)!
        let weave = crdt.weave.weave()
        
        let datum = DrawDatum.opTranslate(delta: delta)
        
        if let lastOp = lastOperation(forShape: shapeStartIndex, ofType: .opTranslate)
        {
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: weave[Int(lastOp)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
        else
        {
            let r = root(forShape: shapeStartIndex)
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: weave[Int(r)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
    }

    // Complexity: O(N)
    func updateShapePoint(_ p: PointId, withDelta delta: NSPoint)
    {
        updateShapePoints((start: p, end: p), withDelta: delta)
    }

    // Complexity: O(N)
    func updateShapePoints(_ points: (start: PointId, end: PointId), withDelta delta: NSPoint)
    {
        assert(shapeForPoint(crdt.weave.atomWeaveIndex(points.start)!) == shapeForPoint(crdt.weave.atomWeaveIndex(points.end)!), "start and end do not share same shape")
        assert(crdt.weave.atomWeaveIndex(points.start)! <= crdt.weave.atomWeaveIndex(points.end)!, "start and end are not correctly ordered")
        
        let pointStartIndex = crdt.weave.atomWeaveIndex(points.start)!
        let weave = crdt.weave.weave()
        
        let datum = DrawDatum.opTranslate(delta: delta)
        
        if let lastOp = lastOperation(forPoint: pointStartIndex, ofType: .opTranslate)
        {
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: weave[Int(lastOp)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true, withReference: points.end)
        }
        else
        {
            let _ = crdt.weave.addAtom(withValue: datum, causedBy: points.start, atTime: Clock(CACurrentMediaTime() * 1000), priority: true, withReference: points.end)
        }
    }
    
    // Complexity: O(N)
    func deleteShapePoint(_ p: PointId)
    {
        let _ = crdt.weave.deleteAtom(p, atTime: Clock(CACurrentMediaTime() * 1000))
    }

    // Complexity: O(N)
    func addShapePoint(afterPoint pointId: PointId, withBounds bounds: NSRect? = nil) -> PointId
    {
        let minLength: Scalar = 10
        let maxLength: Scalar = 30
        let maxCCAngle: Scalar = 70
        let maxCAngle: Scalar = 20
        let offset: CGFloat = 4

        let weave = crdt.weave.weave()
        
        let pointIndex = crdt.weave.atomWeaveIndex(pointId)!
        let shapeIndex = shapeForPoint(pointIndex)
        let shapeId = weave[Int(shapeIndex)].id
        
        assert(pointIsValid(pointIndex))

        let length = minLength + Scalar(arc4random_uniform(UInt32(maxLength - minLength)))

        let point = rawValueForPoint(pointIndex)
        
        let previousPoint = nextValidPoint(beforePoint: pointId)
        let nextPoint = nextValidPoint(afterPoint: pointId, looping: false)

        let pointIsOnlyPoint = shapeCount(shapeId) == 1
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
                let previousPointIndex = crdt.weave.atomWeaveIndex(previousPoint!)
                let previousPointValue = rawValueForPoint(previousPointIndex!)
                
                angle = -maxCAngle + Scalar(arc4random_uniform(UInt32(maxCAngle + maxCCAngle)))
                vec = Vector2(point) - Vector2(previousPointValue)
            }
            else
            {
                let nextPointIndex = crdt.weave.atomWeaveIndex(nextPoint!)
                let nextPointValue = rawValueForPoint(nextPointIndex!)
                
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
                let nextPointIndex = crdt.weave.atomWeaveIndex(nextPoint!)
                let nextPointValue = rawValueForPoint(nextPointIndex!)

                //a dot normalized b
                let vOld = Vector2(nextPointValue) - Vector2(point)
                let vNew = Vector2(newPoint) - Vector2(point)
                let vProj = (vOld.normalized() * vNew.dot(vOld.normalized()))

                let endPoint = endSentinel(forShape: shapeIndex)
                
                updateShapePoints((start: nextPoint!, end: weave[Int(endPoint)].id), withDelta: NSPoint(vProj))
            }

            let newAtom = crdt.weave.addAtom(withValue: DrawDatum.point(pos: newPoint), causedBy: pointId, atTime: Clock(CACurrentMediaTime() * 1000))!
            updateAttributes(rounded: arc4random_uniform(2) == 0, forPoint: newAtom)
            
            return newAtom
        }
    }

    // Complexity: O(N) to find index, then O(S)
    func attributes(forShape s: ShapeId) -> (NSColor)
    {
        let shapeIndex = crdt.weave.atomWeaveIndex(s)!
        
        if let op = lastOperation(forShape: shapeIndex, ofType: .attrColor)
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

    // Complexity: O(N) to find index, then O(S)
    func attributes(forPoint p: PointId) -> (Bool)
    {
        let pointIndex = crdt.weave.atomWeaveIndex(p)!
        
        if let op = lastOperation(forPoint: pointIndex, ofType: .attrRound)
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

    // Complexity: O(N)
    func updateAttributes(color: NSColor, forShape s: ShapeId)
    {
        let shapeIndex = crdt.weave.atomWeaveIndex(s)!
        
        let weave = crdt.weave.weave()
        
        if let op = lastOperation(forShape: shapeIndex, ofType: .attrColor)
        {
            let colorStruct = DrawDatum.ColorTuple(r: color.redComponent, g: color.greenComponent, b: color.blueComponent, a: color.alphaComponent)
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrColor(colorStruct), causedBy: weave[Int(op)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
        else
        {
            let rootIndex = root(forShape: shapeIndex)
            
            let colorStruct = DrawDatum.ColorTuple(r: color.redComponent, g: color.greenComponent, b: color.blueComponent, a: color.alphaComponent)
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrColor(colorStruct), causedBy: weave[Int(rootIndex)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
    }

    // Complexity: O(N)
    func updateAttributes(rounded: Bool, forPoint p: PointId)
    {
        let pointIndex = crdt.weave.atomWeaveIndex(p)!
        
        let weave = crdt.weave.weave()
        
        if let op = lastOperation(forPoint: pointIndex, ofType: .attrRound)
        {
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrRound(rounded), causedBy: weave[Int(op)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
        else
        {
            let _ = crdt.weave.addAtom(withValue: DrawDatum.attrRound(rounded), causedBy: weave[Int(pointIndex)].id, atTime: Clock(CACurrentMediaTime() * 1000), priority: true)
        }
    }
    
    ////////////////////////////////
    // MARK: - CT-Specific Queries -
    ////////////////////////////////
    
    // excluding sentinels
    // Complexity: O(Shape)
    func shapeData(s: WeaveIndex) -> [(range: CountableClosedRange<WeaveIndex>, transform: CGAffineTransform, deleted: Bool)]
    {
        let weave = crdt.weave.weave()
        let sId = weave[Int(s)].id
        
        assertType(sId, .shape)
        
        var i = Int(s + 1)
        var shapeTransform = CGAffineTransform.identity
        var points: [(range: CountableClosedRange<WeaveIndex>, transform: CGAffineTransform, deleted: Bool)] = []
        
        getShapeTransform: do
        {
            while i < weave.count
            {
                if atomDelimitsPoint(weave[i].id)
                {
                    break getShapeTransform
                }
                else if atomDelimitsShape(weave[i].id)
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
                if atomDelimitsShape(weave[i].id) //AB: this one has to go first
                {
                    commitPoint(withEndIndex: WeaveIndex(i))
                    i += 1 //why not
                    break iteratePoints
                }
                else if atomDelimitsPoint(weave[i].id)
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
    func lastShape() -> WeaveIndex?
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
    // Complexity: O(Shape)
    func allPoints(forShape s: WeaveIndex) -> [WeaveIndex]
    {
        let indexArray = shapeData(s: s).map { $0.range.lowerBound }
        
        return Array(indexArray)
    }
    
    // Complexity: O(Shape)
    func root(forShape s: WeaveIndex) -> WeaveIndex
    {
        return s + 1
    }
    
    // Complexity: O(Shape)
    func startSentinel(forShape s: WeaveIndex) -> WeaveIndex
    {
        let weave = crdt.weave.weave()
        let sId = weave[Int(s)].id
        
        assertType(sId, .shape)
        
        for i in Int(s + 1)..<weave.count
        {
            if atomDelimitsShape(weave[i].id)
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
    
    // Complexity: O(Shape)
    func endSentinel(forShape s: WeaveIndex) -> WeaveIndex
    {
        let weave = crdt.weave.weave()
        let sId = weave[Int(s)].id
        
        assertType(sId, .shape)
        
        for i in Int(s + 1)..<weave.count
        {
            if atomDelimitsShape(weave[i].id)
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
    
    // Complexity: O(Shape)
    func lastOperation(forShape s: WeaveIndex, ofType t: DrawDatum.Id) -> WeaveIndex?
    {
        let weave = crdt.weave.weave()
        let sId = weave[Int(s)].id
        
        assertType(sId, .shape)
        
        var lastIndex: Int = -1
        
        for i in Int(s + 1)..<weave.count
        {
            if atomDelimitsShape(weave[i].id)
            {
                break
            }
            if atomDelimitsPoint(weave[i].id)
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
    
    // Complexity: O(Shape)
    func lastOperation(forPoint p: WeaveIndex, ofType t: DrawDatum.Id) -> WeaveIndex?
    {
        let weave = crdt.weave.weave()
        let pId = weave[Int(p)].id
        
        assertType(pId, .point)
        
        var lastIndex: Int = -1
        
        for i in Int(p + 1)..<weave.count
        {
            if atomDelimitsShape(weave[i].id)
            {
                break
            }
            if atomDelimitsPoint(weave[i].id)
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
    
    // Complexity: O(Shape)
    func pointData(_ p: WeaveIndex) -> (range: CountableClosedRange<WeaveIndex>, transform: CGAffineTransform, deleted: Bool)
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
    
    // Complexity: O(Shape)
    private func pointIsValid(_ p: WeaveIndex) -> Bool
    {
        let data = pointData(p)
        
        return !data.deleted
    }
    
    private func rawValueForPoint(_ p: WeaveIndex) -> NSPoint
    {
        let weave = crdt.weave.weave()
        let pId = weave[Int(p)].id
        
        assertType(pId, .point)
        
        if case .point(let pos) = weave[Int(p)].value
        {
            return pos
        }
        
        assert(false)
        return NSPoint.zero
    }
    
    // Complexity: O(Shape)
    private func shapeForPoint(_ p: WeaveIndex) -> WeaveIndex
    {
        let weave = crdt.weave.weave()
        let pId = weave[Int(p)].id
        
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
    
    func transformForPoint(_ p: WeaveIndex) -> CGAffineTransform
    {
        let data = pointData(p)

        return data.transform
    }
    
    // AB: in our tree structure, shapes and points are both grouped together into causal blocks, with predictable
    //     children; therefore, we can delimit atoms and shapes efficiently and deterministically
    
    private func atomDelimitsPoint(_ a: AtomId) -> Bool
    {
        let atom = crdt.weave.atomForId(a)!
        
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
    
    private func atomDelimitsShape(_ a: AtomId) -> Bool
    {
        let atom = crdt.weave.atomForId(a)!
        
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
    
    private func assertType(_ a: AtomId, _ t: DrawDatum.Id)
    {
        assert({
            if crdt.weave.atomForId(a)!.value.id == t
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
