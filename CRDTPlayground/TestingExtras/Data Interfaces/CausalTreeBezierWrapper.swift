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
 linked to it. Points can be caused only by other points as well as their shape's root atom, for the first point
 in a shape; their weave order is their connection order. Operations can be caused only by other operations in their
 type group as well as a point atom or root atom, for the first operation in a chain. Operation types are currently
 divided into transformations (move) and deletions. Operations must be priority atoms. The same goes for attributes,
 which can be thought of as register-type operations; the last weave value in a chain is taken as the definitive one.
 Each attribute is considered its own type group; attributes of different types shall not mix causally. Finally, since
 we'll be traversing chains of operations quite frequently, we want to make sure that we can find the end of a chain in
 O(number of operations in chain) time and not O(N) time, which is what would be required if we do the usual awareness
 and causal block derivation dance. For this, each operation, attribute, and point (?) shall have a reference to its
 originating shape. */

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
//     (in terms of user-facing stuff, that is: under the hood the CT preserves everything anyway)
class CausalTreeBezierWrapper
{
    private unowned var crdt: CausalTreeBezierT
    
    //var shapes: [[NSPoint]] = []
    //var shapeAttributes: [(NSColor)] = [] //color
    //var pointAttributes: [[(Bool)]] = [] //roundness
    //var shapeOperations: [[Operation]] = [] //translation
    
    init(crdt: CausalTreeBezierT) {
        self.crdt = crdt
    }
    
    // this is in addition to the low-level CT validation b/c our rules are more strict on this higher level
    func validate() -> Bool
    {
        // top level: shapes and null nodes
        // operation chains are all the same type
        // operations are priority
        // operations are only parented to shapes, points, or null atoms
        return false
    }
    
    // Complexity: O(N)
    func shapesCount() -> Int
    {
        let weave = crdt.weave.weave()
        
        var total = 0
        
        for a in weave
        {
            if case .shape = a.value
            {
                total += 1
            }
        }
        
        return total
    }
    
    func shapeCount(_ s: Int, withInvalid: Bool = false) -> Int
    {
        if withInvalid
        {
            return shapes[s].count
        }
        else
        {
            var t = 0
            for i in 0..<shapes[s].count
            {
                if pointIsValid(i, forShape: s)
                {
                    t += 1
                }
            }
            return t
        }
    }
    
    func pointValue(_ p: Int, forShape s: Int) -> NSPoint?
    {
        if pointIsValid(p, forShape: s)
        {
            let t = transform(forOperations: operations(forShape: s))
            return shapes[s][p].applying(t)
        }
        else
        {
            return nil
        }
    }
    
    func pointIsValid(_ p: Int, forShape s: Int) -> Bool
    {
        return !shapes[s][p].x.isNaN && !shapes[s][p].y.isNaN
    }
    
    func nextValidPoint(afterPoint p: Int, forShape s: Int, looping: Bool = true) -> Int?
    {
        let fullShapeCount = shapeCount(s, withInvalid: true)
        
        for i0 in 0..<fullShapeCount
        {
            var i = p + 1 + i0
            
            if !looping && i >= fullShapeCount
            {
                return nil
            }
            
            i = (((i % fullShapeCount) + fullShapeCount) % fullShapeCount)
            
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func nextValidPoint(beforePoint p: Int, forShape s: Int, looping: Bool = true) -> Int?
    {
        let fullShapeCount = shapeCount(s, withInvalid: true)
        
        for i0 in 0..<fullShapeCount
        {
            var i = p - 1 - i0
            
            if !looping && i < 0
            {
                return nil
            }
            
            i = (((i % fullShapeCount) + fullShapeCount) % fullShapeCount)
            
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func isFirstPoint(_ p: Int, inShape s: Int) -> Bool
    {
        return nextValidPoint(beforePoint: p, forShape: s, looping: false) == nil
    }
    
    func isLastPoint(_ p: Int, inShape s: Int) -> Bool
    {
        return nextValidPoint(afterPoint: p, forShape: s, looping: false) == nil
    }
    
    func firstPoint(inShape s: Int) -> Int?
    {
        for i in 0..<shapes[s].count
        {
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func lastPoint(inShape s: Int) -> Int?
    {
        for i in (0..<shapes[s].count).reversed()
        {
            if pointIsValid(i, forShape: s)
            {
                return i
            }
        }
        
        return nil
    }
    
    func points(forShape s: Int) -> AnyCollection<Int>
    {
        // PERF: I'm not sure to what extent lazy works in this stack, but whatever
        let countArray = Array<Int>(0..<shapes[s].count).lazy
        let filteredArray = countArray.filter { i in self.pointIsValid(i, forShape: s) }
        let lazyArray = filteredArray.lazy
        
        return AnyCollection(lazyArray)
    }
    
    func addShape(atX x: CGFloat, y: CGFloat) -> Int
    {
        let randX = x
        let randY = y
        
        shapes.append([NSMakePoint(randX, randY)])
        shapeAttributes.append((randomColor()))
        pointAttributes.append([arc4random_uniform(2) == 0])
        shapeOperations.append([])
        assert(shapes.count == shapeAttributes.count)
        assert(shapes.count == pointAttributes.count)
        assert(shapes.count == shapeOperations.count)
        
        return shapes.count - 1
    }
    
    func updateShapePoint(_ p: Int, inShape s: Int, withDelta delta: NSPoint)
    {
        let value = NSMakePoint(shapes[s][p].x + delta.x, shapes[s][p].y + delta.y)
        
        updateShapePoint(p, inShape: s, withValue: value)
    }
    
    func updateShapePoints(_ points: CountableClosedRange<Int>, inShape s: Int, withDelta delta: NSPoint)
    {
        for p in points
        {
            updateShapePoint(p, inShape: s, withDelta: delta)
        }
    }
    
    private func updateShapePoint(_ p: Int, inShape: Int, withValue: NSPoint)
    {
        shapes[inShape][p] = withValue
    }
    
    func addShapePoint(toShape: Int, afterPoint: Int, withBounds bounds: NSRect? = nil) -> (Int, Int)
    {
        assert(pointIsValid(afterPoint, forShape: toShape))
        
        let minLength: Scalar = 10
        let maxLength: Scalar = 30
        let maxCCAngle: Scalar = 70
        let maxCAngle: Scalar = 20
        let offset: CGFloat = 4
        
        let shapeIndex = toShape
        let pointIndex = afterPoint
        
        let point = shapes[shapeIndex][pointIndex]
        assert(pointIsValid(pointIndex, forShape: shapeIndex))
        let length = minLength + Scalar(arc4random_uniform(UInt32(maxLength - minLength)))
        
        let previousPointIndex = nextValidPoint(beforePoint: pointIndex, forShape: shapeIndex)
        let nextPointIndex = nextValidPoint(afterPoint: pointIndex, forShape: shapeIndex, looping: false)
        
        let pointIsOnlyPoint = shapeCount(toShape) == 1
        let pointIsEndPoint = isLastPoint(afterPoint, inShape: toShape)
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
                let previousPoint = shapes[shapeIndex][previousPointIndex!]
                angle = -maxCAngle + Scalar(arc4random_uniform(UInt32(maxCAngle + maxCCAngle)))
                vec = Vector2(point) - Vector2(previousPoint)
            }
            else
            {
                let nextPoint = shapes[shapeIndex][nextPointIndex!]
                angle = -maxCAngle + Scalar(arc4random_uniform(UInt32(maxCAngle + maxCCAngle)))
                vec = Vector2(nextPoint) - Vector2(point)
            }
            
            vec = vec.normalized() * length
            vec = vec.rotated(by: angle * ((2*Scalar.pi)/360))
            
            let tempNewPoint = NSMakePoint(point.x + CGFloat(vec.x), point.y + CGFloat(vec.y))
            if let b = bounds
            {
                let t = transform(forOperations: operations(forShape: shapeIndex)).inverted()
                let tBounds = b.applying(t)
                
                newPoint = NSMakePoint(min(max(tempNewPoint.x, tBounds.minX + offset), tBounds.maxX - offset),
                                       min(max(tempNewPoint.y, tBounds.minY + offset), tBounds.maxY - offset))
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
                let nextPoint = shapes[shapeIndex][nextPointIndex!]
                
                //a dot normalized b
                let vOld = Vector2(nextPoint) - Vector2(point)
                let vNew = Vector2(newPoint) - Vector2(point)
                let vProj = (vOld.normalized() * vNew.dot(vOld.normalized()))
                
                let lastIndex = lastPoint(inShape: shapeIndex)!
                
                // TODO: sentinel
                updateShapePoints(nextPointIndex!...lastIndex, inShape: shapeIndex, withDelta: NSPoint(vProj))
            }
            
            shapes[shapeIndex].insert(newPoint, at: pointIndex + 1)
            pointAttributes[shapeIndex].insert(arc4random_uniform(2) == 0, at: pointIndex + 1)
        }
        
        return (shapeIndex, pointIndex + 1)
    }
    
    func deleteShapePoint(_ p: Int, fromShape s: Int) -> (Int,Int)?
    {
        updateShapePoint(p, inShape: s, withValue: NSMakePoint(CGFloat.nan, CGFloat.nan))
        
        if let prevPoint = nextValidPoint(beforePoint: p, forShape: s)
        {
            return (s,prevPoint)
        }
        else
        {
            return nil
        }
    }
    
    func attributes(forShape s: Int) -> (NSColor)
    {
        return shapeAttributes[s]
    }
    
    func attributes(forPoint p: Int, inShape s: Int) -> (Bool)
    {
        return pointAttributes[s][p]
    }
    
    func operations(forShape s: Int) -> [Operation]
    {
        return shapeOperations[s]
    }
    
    func transform(forOperations ops: [Operation]) -> CGAffineTransform
    {
        var transform = CGAffineTransform.identity
        for o in ops
        {
            switch o
            {
            case .translate(let delta):
                transform = transform.concatenating(CGAffineTransform(translationX: delta.x, y: delta.y))
            }
        }
        return transform
    }
    
    func updateAttributes(color: NSColor, forShape s: Int)
    {
        shapeAttributes[s] = (color)
    }
    
    func updateAttributes(rounded: Bool, forPoint p: Int, inShape s: Int)
    {
        pointAttributes[s][p] = (rounded)
    }
    
    func addOperation(_ o: Operation, toShape s: Int)
    {
        if shapeOperations[s].isEmpty
        {
            shapeOperations[s].append(o)
        }
        else
        {
            let lastOperation = shapeOperations[s].last!
            
            switch o
            {
            case .translate(let d1):
                switch lastOperation
                {
                case .translate(let d2):
                    // consolidate adjascent translations
                    shapeOperations[s][shapeOperations[s].count - 1] = .translate(delta: NSMakePoint(d1.x + d2.x, d1.y + d2.y))
                }
            }
        }
    }
}
