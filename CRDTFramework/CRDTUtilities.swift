//
//  CRDTUtilities.swift
//  CRDTPlayground
//
//  Created by Alexei Baboulevitch on 2017-9-5.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation

extension UUID: DefaultInitializable {}
extension String: DefaultInitializable {}

extension SiteId: Zeroable
{
    public static var zero = SiteId(0)
}

extension UUID: Zeroable
{
    public static var zero = UUID(uuid: uuid_t((0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
}

extension UUID: Comparable
{
    // PERF: is comparing UUID strings quick enough?
    public static func <(lhs: UUID, rhs: UUID) -> Bool
    {
        return lhs.uuidString < rhs.uuidString
    }
    public static func <=(lhs: UUID, rhs: UUID) -> Bool
    {
        return lhs.uuidString <= rhs.uuidString
    }
    public static func >=(lhs: UUID, rhs: UUID) -> Bool
    {
        return lhs.uuidString >= rhs.uuidString
    }
    public static func >(lhs: UUID, rhs: UUID) -> Bool
    {
        return lhs.uuidString > rhs.uuidString
    }
    public static func ==(lhs: UUID, rhs: UUID) -> Bool
    {
        return lhs.uuidString == rhs.uuidString
    }
}

extension UUID: CRDTSiteUUIDT {}
extension SiteId: CRDTSiteUUIDT {}
