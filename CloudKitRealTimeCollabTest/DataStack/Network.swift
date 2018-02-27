//
//  CloudKit.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

//https://developer.apple.com/library/content/samplecode/CloudKitShare/Introduction/Intro.html#//apple_ref/doc/uid/TP40017580-Intro-DontLinkElementID_2

import Foundation
import CloudKit

// 7. file closing
// 8. order of ops cleanup, e.g. controllers, state machine
// 9. zip/async perf tweaks
// copy ckasset data to temp storage

// owns synced CloudKit objects and their caches, working at data (binary) layer
class Network
{
    public static let FileChangedNotification = NSNotification.Name(rawValue: "FileChangedNotification")
    public static let FileChangedNotificationIDsKey = "ids"
    
    public enum NetworkError: Error
    {
        case offline
        case couldNotLogIn
        case nonExistentFile
        case mergeSupplanted
        case mergeConflict
        case noSharedZone
        case doesNotWorkInSharedDatabase
        case other
    }
    
    public typealias FileID = String
    
    public static let FileType = "File"
    public static let ZoneName = "Files"
    public static let SubscriptionName = "FilesSubscription"
    public static let SharedSubscriptionName = "SharedFilesSubscription"
    
    public static let FileNameField = "name"
    public static let FileDataField = "crdt"
    
    private class Cache
    {
        var shared: Bool
        
        var recordZones: [CKRecordZoneID]!
        var subscription: CKSubscription!
        
        var tokens: [CKRecordZoneID:CKServerChangeToken] = [:]
        var fileCache: [CKRecordZoneID:[FileID:FileCache]] = [:]
        
        var db: CKDatabase
        
        private var mergeOperationsQueue: OperationQueue
        
        init(shared: Bool)
        {
            self.shared = shared
            
            self.db = (shared ? CKContainer.default().sharedCloudDatabase : CKContainer.default().privateCloudDatabase)
            
            self.mergeOperationsQueue = OperationQueue()
            self.mergeOperationsQueue.qualityOfService = .userInitiated
        }
        
        func load(_ topBlock: @escaping (Error?)->())
        {
            func login(_ block: @escaping (Error?)->())
            {
                CKContainer.default().accountStatus
                { s,e in
                    if s == .available
                    {
                        // TODO: restart operations queue
                        print("Logged in, continuing...")
                        block(nil)
                    }
                    else
                    {
                        // TODO: stop operations queue
                        if let error = e
                        {
                            block(error)
                        }
                        else
                        {
                            block(NetworkError.couldNotLogIn)
                        }
                    }
                }
            }
            
            func createZone(_ block: @escaping (Error?)->())
            {
                if self.shared
                {
                    // shared zones don't need to be created, they'll be pulled on refresh
                    block(nil)
                    return
                }
                
                let pzones = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
                pzones.database = db
                pzones.fetchRecordZonesCompletionBlock =
                { zones, error in
                    if let error = error
                    {
                        block(error)
                    }
                    else
                    {
                        var correctZones: [CKRecordZoneID] = []
                        
                        for zone in zones ?? [:]
                        {
                            if zone.0.zoneName == Network.ZoneName
                            {
                                correctZones.append(zone.0)
                                print("Retrieved \(self.shared ? "shared" : "existing") zone, continuing...")
                            }
                        }
                        
                        if correctZones.count > 0
                        {
                            self.recordZones = correctZones
                            block(nil)
                            return
                        }
                        
                        createNewZone: do
                        {
                            let zone = CKRecordZone(zoneName: Network.ZoneName)
                            
                            self.db.save(zone)
                            { z,e in
                                if let error = e
                                {
                                    block(error)
                                }
                                else
                                {
                                    print("Created zone, continuing...")
                                    self.recordZones = [z!.zoneID]
                                    block(nil)
                                    return
                                }
                            }
                        }
                    }
                }
                
                pzones.start()
            }
            
            func subscribe(_ block: @escaping (Error?)->())
            {
                //db.fetchAllSubscriptions
                //{ subs,e in
                //    if subs?.count ?? 0 == 0
                //    {
                //        print("No subscriptions to delete, continuing...")
                //        block(nil)
                //    }
                //
                //    for sub in subs ?? []
                //    {
                //        print("Deleting \(sub.subscriptionID)")
                //        self.db.delete(withSubscriptionID: sub.subscriptionID)
                //        { s,e in
                //            if let error = e
                //            {
                //                block(error)
                //            }
                //            else
                //            {
                //                print("Deleted all subscriptions, continuing...")
                //                block(nil)
                //            }
                //        }
                //    }
                //}
                //return;
                
                db.fetch(withSubscriptionID: (self.shared ? Network.SharedSubscriptionName : Network.SubscriptionName))
                { s,e in
                    if let error = e as? CKError, error.code == CKError.unknownItem
                    {
                        let subscription = (self.shared ? CKDatabaseSubscription(subscriptionID: Network.SharedSubscriptionName) : CKRecordZoneSubscription(zoneID: self.recordZones.first!, subscriptionID: Network.SubscriptionName))
                        
                        let notification = CKNotificationInfo()
                        notification.alertBody = (self.shared ? "shared changed" : "files changed")
                        subscription.notificationInfo = notification

                        self.db.save(subscription)
                        { s,e in
                            if let error = e
                            {
                                block(error)
                            }
                            else
                            {
                                print("Subscribed, continuing...")
                                self.subscription = s!
                                block(nil)
                            }
                        }
                    }
                    else if let error = e
                    {
                        block(error)
                    }
                    else
                    {
                        print("Retrieved existing subscription, continuing...")
                        self.subscription = s!
                        block(nil)
                    }
                }
            }
            
            loginSteps: do
            {
                login
                { e in
                    if let error = e
                    {
                        topBlock(error)
                    }
                    else
                    {
                        createZone
                        { e in
                            if let error = e
                            {
                                topBlock(error)
                            }
                            else
                            {
                                subscribe
                                { e in
                                    if let error = e
                                    {
                                        topBlock(error)
                                    }
                                    else
                                    {
                                        self.refresh
                                        { c,e in
                                            if let error = e
                                            {
                                                topBlock(error)
                                            }
                                            else
                                            {
                                                topBlock(nil)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        func refresh(_ block: @escaping ([Network.FileID]?,Error?)->())
        {
            var allChanges: Set<FileID> = Set()
            
            func getFiles(_ block: @escaping ([Network.FileID]?,Error?)->())
            {
                var options: [CKRecordZoneID:CKFetchRecordZoneChangesOptions] = [:]
                for zone in self.recordZones
                {
                    options[zone] = CKFetchRecordZoneChangesOptions()
                    options[zone]!.previousServerChangeToken = self.tokens[zone]
                }
                let query = CKFetchRecordZoneChangesOperation(recordZoneIDs: self.recordZones, optionsByRecordZoneID: options)
                
                var recordsAwaitingShare = Set<CKRecord>()
                var pendingShares = [String:CKShare]()
                
                query.recordZoneChangeTokensUpdatedBlock =
                { zone,token,data in
                    //print("Fetching record info, received token: \(token?.description ?? "(null)")")
                    self.tokens[zone] = token
                }
                query.recordZoneFetchCompletionBlock =
                { zone,token,data,_,e in
                    // per-zone completion block
                    //print("Fetched zone record info, received token: \(token?.description ?? "(null)")")
                    self.tokens[zone] = token
                }
                query.recordChangedBlock =
                { record in
                    if let record = record as? CKShare
                    {
                        pendingShares[record.recordID.recordName] = record
                    }
                    else
                    {
                        let metadata = FileCache(fromRecord: record)
                        
                        // if we refresh the shared db, the associated CKShare does not actually come in (?) so we have to use the previous one
                        if let share = record.share?.recordID.recordName, pendingShares[share] == nil
                        {
                            pendingShares[share] = self.fileCache[record.recordID.zoneID]?[record.recordID.recordName]?.associatedShare
                        }
                        
                        if self.fileCache[record.recordID.zoneID] == nil { self.fileCache[record.recordID.zoneID] = [:] }
                        self.fileCache[record.recordID.zoneID]![record.recordID.recordName] = metadata
                        allChanges.insert(record.recordID.recordName)
                        
                        if record.share != nil
                        {
                            recordsAwaitingShare.insert(record)
                        }
                    }
                }
                query.recordWithIDWasDeletedBlock =
                { record,str in
                    self.fileCache[record.zoneID]?.removeValue(forKey: record.recordName)
                    allChanges.insert(record.recordName)
                }
                query.fetchRecordZoneChangesCompletionBlock =
                { e in
                    if let error = e
                    {
                        block(nil, error)
                    }
                    else
                    {
                        for record in recordsAwaitingShare
                        {
                            if let share = pendingShares[record.share!.recordID.recordName]
                            {
                                self.fileCache[record.recordID.zoneID]![record.recordID.recordName]!.associateShare(share)
                            }
                            else
                            {
                                assert(false, "no share found for shared record")
                            }
                        }
                        block(Array(allChanges), nil)
                    }
                }
                
                db.add(query)
            }
        
            if self.shared
            {
                let pzones = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
                pzones.database = db
                pzones.fetchRecordZonesCompletionBlock =
                { zones, error in
                    if let error = error
                    {
                        block(nil, error)
                    }
                    else
                    {
                        let zones = zones ?? [:]
                        
                        var correctZones: [CKRecordZoneID] = []
            
                        for zone in zones
                        {
                            if zone.0.zoneName == Network.ZoneName
                            {
                                correctZones.append(zone.0)
                            }
                        }
            
                        let oldZones = Set(self.recordZones ?? [])
                        let newZones = Set(correctZones)
            
                        let deletedZones = oldZones.subtracting(newZones)
                        let createdZones = newZones.subtracting(oldZones)
            
                        deletedZones.forEach { _ in print("Deleted shared zone, continuing...") }
                        createdZones.forEach { _ in print("Inserted shared zone, continuing...") }
            
                        for zone in deletedZones
                        {
                            self.fileCache[zone]?.keys.forEach { allChanges.insert($0) }
                            self.tokens.removeValue(forKey: zone)
                            self.fileCache.removeValue(forKey: zone)
                        }
            
                        self.recordZones = Array(correctZones)
                        
                        getFiles(block)
                    }
                }
                
                pzones.start()
            }
            else
            {
                getFiles(block)
            }
        }
        
        func associateShare(_ share: CKShare?, withId id: FileID) -> Bool
        {
            for (k,v) in fileCache
            {
                if v[id] != nil
                {
                    fileCache[k]![id]!.associateShare(share)
                    return true
                }
            }
            
            return false
        }
        
        // TODO: escaping?
        func create(file: Data, named: String, _ block: @escaping (FileCache,Error?)->())
        {
            if self.shared
            {
                block(FileCache(fromRecord: CKRecord(recordType: Network.FileType)), NetworkError.doesNotWorkInSharedDatabase)
            }
            
            let record = CKRecord(recordType: Network.FileType, zoneID: recordZones.first!)
            record[Network.FileNameField] = named as CKRecordValue
            
            let name = "\(named)-\(file.hashValue).crdt"
            let fileUrl = URL.init(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(name))
            try! file.write(to: fileUrl)
            record[Network.FileDataField] = CKAsset(fileURL: fileUrl)
            
            db.save(record)
            { r,e in
                defer
                {
                    // TODO: we don't delete this b/c it's necessary for the cache; maybe on quit?
                    //try! FileManager.default.removeItem(at: fileUrl)
                }
                
                if let error = e
                {
                    onMain
                    {
                        block(FileCache(fromRecord: CKRecord(recordType: Network.FileType)), error)
                    }
                }
                else
                {
                    let record = r!
                    let metadata = FileCache(fromRecord: record)
                    
                    onMain(true)
                    {
                        // NEXT: modify cache always on main thread
                        if self.fileCache[record.recordID.zoneID] == nil { self.fileCache[record.recordID.zoneID] = [:] }
                        self.fileCache[self.recordZones.first!]![metadata.id.recordName] = metadata
                        
                        block(metadata, nil)
                    }
                }
            }
        }
        
        func delete(_ id: FileID, _ block: @escaping (Error?)->())
        {
            if self.shared
            {
                block(NetworkError.doesNotWorkInSharedDatabase)
                return
            }
            
            guard let record = allFiles()[id] else
            {
                block(NetworkError.nonExistentFile)
                return
            }
            
            db.delete(withRecordID: record.id)
            { _,e in
                onMain(true)
                {
                    if e == nil
                    {
                        self.fileCache[record.id.zoneID]?.removeValue(forKey: id)
                    }
                    
                    block(e)
                }
            }
        }
        
        func share(_ id: FileID, _ block: @escaping (Error?)->())
        {
            if self.shared
            {
                block(NetworkError.doesNotWorkInSharedDatabase)
                return
            }
            
            guard let metadata = allFiles()[id] else
            {
                block(NetworkError.nonExistentFile)
                return
            }
            
            let record: CKRecord! = metadata.record
            let origShare = metadata.newShare
            let records = [record!, origShare]
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: [])
            op.perRecordCompletionBlock =
            { r,e in
                // do nothing
            }
            op.modifyRecordsCompletionBlock =
            { saved,deleted,error in
                if let error = error
                {
                    onMain { block(error) }
                }
                else
                {
                    onMain
                    {
                        let shareIndex = (saved![0] is CKShare ? 0 : 1)
                        let recordIndex = (shareIndex == 0 ? 1 : 0)
                        
                        warning(self.fileCache[record.recordID.zoneID]?[id] != nil, "share file missing, file might have been deleted")
                        
                        self.fileCache[record.recordID.zoneID]?[id] = FileCache(fromRecord: saved![recordIndex], withShare: (saved![shareIndex] as! CKShare))
                        
                        block(nil)
                    }
                }
            }
            
            db.add(op)
        }
        
        // block might be called twice if pull needs to happen
        func merge(id: FileID, data: Data, block: @escaping (Bool,Error?)->())
        {
            guard let metadata = allFiles()[id] else
            {
                block(false, NetworkError.nonExistentFile)
                return
            }
            
            let record = metadata.record
            
            let name = "\(id).crdt"
            let fileUrl = URL.init(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(name))
            try! data.write(to: fileUrl)
            record[Network.FileDataField] = CKAsset(fileURL: fileUrl)
            
            print("Adding merge with old record changetag: \(record.recordChangeTag ?? "")")
            
            let mergeOp = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            var startTime: CFTimeInterval = 0
            mergeOp.perRecordProgressBlock =
            { r,p in
                if p == 1
                {
                    let time = CFAbsoluteTimeGetCurrent() - startTime
                    print("Making progress on record \(r.recordChangeTag ?? ""): \(String(format: "%.2f", p)) (\(String(format: "%.2f", time)) seconds)")
                }
                if p == 0
                {
                    startTime = CFAbsoluteTimeGetCurrent()
                }
            }
            mergeOp.database = db
            assert(metadata.remoteShared == shared)
            mergeOp.savePolicy = .ifServerRecordUnchanged
            mergeOp.qualityOfService = .userInitiated
            mergeOp.modifyRecordsCompletionBlock =
            { saved,deleted,e in
                if let error = e
                {
                    onMain(true)
                    {
                        block(true, error)
                        
                        // TODO: remote remove
                        if
                            let err = error as? CKError,
                            err.code == CKError.partialFailure,
                            let errDict = (err.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary)
                        {
                            for (k,v) in errDict
                            {
                                if
                                    (k as? CKRecordID)?.recordName == id,
                                    let err2 = v as? CKError,
                                    err2.code == CKError.serverRecordChanged,
                                    let updatedRecord = err2.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
                                {
                                    // necessary b/c err2 does not actually contain asset
                                    self.db.fetch(withRecordID: k as! CKRecordID)
                                    { r,e in
                                        if let error = e
                                        {
                                            onMain(true)
                                            {
                                                block(false, error)
                                                return
                                            }
                                        }
                                        else
                                        {
                                            let metadata = FileCache(fromRecord: r!)
                                            print(metadata.data.fileURL)
                                            print("Conflict record changetag: \(updatedRecord.recordChangeTag ?? "")")
                                            
                                            onMain(true)
                                            {
                                                let share = self.fileCache[metadata.id.zoneID]?[metadata.id.recordName]?.associatedShare
                                                self.fileCache[metadata.id.zoneID]![metadata.id.recordName] = metadata
                                                self.fileCache[metadata.id.zoneID]![metadata.id.recordName]!.associateShare(share)
                                                
                                                block(false, NetworkError.mergeConflict)
                                                return
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        uncaughtError: do
                        {
                            block(false, error)
                            return
                        }
                    }
                }
                else
                {
                    let record = saved!.first!
                    let metadata = FileCache(fromRecord: record)
                    
                    //print("New record changetag: \(record.recordChangeTag ?? "")")
                    
                    onMain(true)
                    {
                        let share = self.fileCache[metadata.id.zoneID]?[metadata.id.recordName]?.associatedShare
                        self.fileCache[metadata.id.zoneID]![metadata.id.recordName] = metadata
                        self.fileCache[metadata.id.zoneID]![metadata.id.recordName]!.associateShare(share)
                        
                        block(false, nil)
                        return
                    }
                }
            }
            
            self.mergeOperationsQueue.addOperation(mergeOp)
        }
        
        func allFiles() -> [FileID:FileCache]
        {
            return fileCache.values.reduce([FileID:FileCache]()) { result, dict in result.merging(dict, uniquingKeysWith: { $1 }) }
        }
    }
    
    public struct FileCache
    {
        let name: String
        let id: CKRecordID
        //let owner: CKRecordID? //TODO:
        let creationDate: Date
        let modificationDate: Date
        let data: CKAsset //TODO: move url
        let metadata: Data
        public private(set) var associatedShare: CKShare?
        
        var remoteShared: Bool
        {
            if let share = associatedShare
            {
                return share.currentUserParticipant != share.owner
            }
            else
            {
                return false
            }
        }
        
        init(fromRecord r: CKRecord, withShare share: CKShare? = nil)
        {
            self.name = r[Network.FileNameField] as? String ?? "null"
            self.id = r.recordID
            //self.owner = r.creatorUserRecordID
            self.creationDate = r.creationDate ?? NSDate.distantPast
            self.modificationDate = r.modificationDate ?? NSDate.distantPast
            self.data = r[Network.FileDataField] as! CKAsset
            
            let data = NSMutableData()
            let archiver = NSKeyedArchiver(forWritingWith: data)
            archiver.requiresSecureCoding = true
            r.encodeSystemFields(with: archiver)
            archiver.finishEncoding()
            self.metadata = data as Data
            
            self.associatedShare = share
        }
        
        mutating func associateShare(_ share: CKShare?)
        {
            self.associatedShare = share
        }
        
        var record: CKRecord
        {
            let unarchiver = NSKeyedUnarchiver(forReadingWith: metadata)
            unarchiver.requiresSecureCoding = true
            let record = CKRecord(coder: unarchiver)!
            unarchiver.finishDecoding()
         
            record[Network.FileNameField] = name as CKRecordValue
            record[Network.FileDataField] = data
            
            return record
        }
        
        var newShare: CKShare
        {
            let record = self.record
            let share = CKShare(rootRecord: record)
            
            share[CKShareTitleKey] = self.name as CKRecordValue
            share[CKShareTypeKey] = "net.archagon.crdt.ct.text" as CKRecordValue
            
            return share
        }
    }
    
    private var caches: (private: Cache, shared: Cache)?
    
    private enum MergeStatus
    {
        case empty
        case enqueued(data: Data, block: (Error?)->())
        case running
        case runningAndEnqueued(data: Data, block: (Error?)->())
    }
    
    private var needToMerge: [FileID:MergeStatus] = [:] //always access this var on main!!
    
    public init()
    {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.CKAccountChanged, object: self, queue: nil)
        { n in
//            self.updateLogin
//            { e in
                assert(false)
//                // TODO: what to do here?
//            }
        }
    }
    
    public func login(_ block: @escaping (Error?)->())
    {
        precondition(self.caches == nil)
        
        let cache = Cache(shared: false)
        cache.load
        { e in
            if let error = e
            {
                self.caches = nil
                onMain { block(error) }
            }
            else
            {
                let sharedCache = Cache(shared: true)
                sharedCache.load
                { e in
                    if let error = e
                    {
                        self.caches = nil
                        onMain { block(error) }
                    }
                    else
                    {
                        self.caches = (cache, sharedCache)
                        onMain { block(nil) }
                    }
                }
            }
        }
    }
    
    public func ids() -> [FileID]
    {
        guard let caches = self.caches else
        {
            return []
        }
        
        func sortedIds(_ cache: Cache?) -> [FileID]
        {
            guard let cache = cache else
            {
                return []
            }
            
            let ids = Array(cache.allFiles()).sorted
            { (pair1, pair2) -> Bool in
                let comparison = pair1.value.creationDate.compare(pair2.value.creationDate)
                return comparison == ComparisonResult.orderedAscending
            }
            
            return ids.map { $0.key }
        }
        
        return sortedIds(caches.shared) + sortedIds(caches.private)
    }
    
    public func metadata(_ id: FileID) -> FileCache?
    {
        guard let caches = self.caches else
        {
            return nil
        }
        
        return (caches.private.allFiles()[id] ?? caches.shared.allFiles()[id] ?? nil)
    }
    
    // gross, but we need this for use with UICloudSharingController
    public func associateShare(_ share: CKShare?, withId id: FileID)
    {
        guard let caches = self.caches else
        {
            return
        }
        
        if caches.private.associateShare(share, withId: id)
        {
            return
        }
        else if caches.shared.associateShare(share, withId: id)
        {
            return
        }
    }
    
    // TODO: escaping vs. nonescaping?
    // TODO: notify that cache updated
//    public func getFileIds(_ block: @escaping (([FileMetadata])->()))
//    {
//        if self.cache == nil
//        {
//            block([])
//        }
//
//        let sort = NSSortDescriptor(key: "modificationDate", ascending: false)
//        let filesQuery = CKQuery(recordType: Network.FileType, predicate: NSPredicate(value: true))
//        filesQuery.sortDescriptors = [sort]
//
//        self.cache?.pdb.perform(filesQuery, inZoneWith: nil, completionHandler:
//        { r, e in
//            print("\(r?.count ?? 0) records \(e != nil ? "error: \(e!)" : "retrieved")")
//            let recordMap = r?.map { FileMetadata(fromRecord: $0) }
//            DispatchQueue.main.async { block(recordMap ?? []) }
//        })
//    }
    
    public func getFile(_ id: FileID, _ block: (((FileCache,Data)?)->()))
    {
        guard let caches = self.caches else
        {
            block(nil)
            return
        }

        // TODO: when does the cache get cleared
        if let file = caches.private.allFiles()[id]
        {
            print("URL: \(file.data.fileURL)")
            let data = FileManager.default.contents(atPath: file.data.fileURL.path)!
            block((file, data))
        }
        else if let file = caches.shared.allFiles()[id]
        {
            print("URL: \(file.data.fileURL)")
            let data = FileManager.default.contents(atPath: file.data.fileURL.path)!
            block((file, data))
        }
        else
        {
            block(nil)
        }
    }
    
    // TODO: escaping?
    public func create(file: Data, named: String, _ block: @escaping (FileCache,Error?)->())
    {
        guard let caches = self.caches else
        {
            block(FileCache(fromRecord: CKRecord(recordType: Network.FileType)), NetworkError.offline)
            return
        }
        
        caches.private.create(file: file, named: named)
        { c,e in
            if let error = e
            {
                onMain
                {
                    block(c,error)
                }
            }
            else
            {
                onMain
                {
                    NotificationCenter.default.post(name: Network.FileChangedNotification, object: nil, userInfo: [Network.FileChangedNotificationIDsKey:[c.id.recordName]])
                    block(c,nil)
                }
            }
        }
    }
    
    private func pumpMergeQueue(forId id: FileID, finishedRunning: Bool = false)
    {
        // TODO: PERF: make this run on another thread
        func runMerge(data: Data, block: @escaping (Error?)->())
        {
            guard let caches = self.caches else
            {
                block(NetworkError.offline)
                return
            }
            
            print("Queuing merge record: \(id.hashValue)")

            let shared: Bool
            
            if let m = caches.private.allFiles()[id]
            {
                shared = false
            }
            else if let m = caches.shared.allFiles()[id]
            {
                shared = true
            }
            else
            {
                block(NetworkError.nonExistentFile)
                return
            }

            (shared ? caches.shared : caches.private).merge(id: id, data: data)
            { firstPartCompleteAndWaitingOnMerge, error in
                if firstPartCompleteAndWaitingOnMerge
                {
                }
                else
                {
                    onMain
                    {
                        block(error)
                     
                        // TODO: we don't delete this b/c it's necessary for the cache; maybe on quit?
                        //try? FileManager.default.removeItem(at: fileUrl)
                        
                        self.pumpMergeQueue(forId: id, finishedRunning: true)
                    }
                }
            }
        }
        
        onMain
        {
            let mergeCase = self.needToMerge[id] ?? .empty
            
            switch mergeCase {
            case .empty:
                return
            case .enqueued(let d, let b):
                self.needToMerge[id] = .running
                runMerge(data: d, block: b)
            case .running:
                if finishedRunning
                {
                    self.needToMerge[id] = .empty
                }
            case .runningAndEnqueued(let d, let b):
                if finishedRunning
                {
                    self.needToMerge[id] = .running
                    runMerge(data: d, block: b)
                }
            }
        }
    }
    
    // TODO: escaping?
    // no callback b/c multiple merges to the same file will overwrite each other, possibly skipping specific merges
    public func merge(_ id: FileID, _ data: Data, _ block: @escaping (Error?)->())
    {
        guard let _ = self.caches else
        {
            block(NetworkError.offline)
            return
        }
        
        onMain
        {
            let mergeCase = self.needToMerge[id] ?? .empty
            
            switch mergeCase {
            case .empty:
                self.needToMerge[id] = .enqueued(data:data, block:block)
            case .enqueued(_, let oldBlock):
                oldBlock(NetworkError.mergeSupplanted)
                self.needToMerge[id] = .enqueued(data:data, block:block)
            case .running:
                self.needToMerge[id] = .runningAndEnqueued(data:data, block:block)
            case .runningAndEnqueued(_, let oldBlock):
                oldBlock(NetworkError.mergeSupplanted)
                self.needToMerge[id] = .runningAndEnqueued(data:data, block:block)
            }
        }
        
        pumpMergeQueue(forId: id)
    }
    
    func delete(_ id: FileID, _ block: @escaping (Error?)->())
    {
        guard let caches = self.caches else
        {
            block(NetworkError.offline)
            return
        }
        
        var shared: Bool
        
        if let _ = caches.private.allFiles()[id]
        {
            shared = false
        }
        else if let _ = caches.shared.allFiles()[id]
        {
            shared = true
        }
        else
        {
            block(NetworkError.nonExistentFile)
            return
        }
        
        (shared ? caches.shared : caches.private).delete(id)
        { e in
            if let error = e
            {
                onMain
                {
                    block(error)
                }
            }
            else
            {
                onMain
                {
                    NotificationCenter.default.post(name: Network.FileChangedNotification, object: nil, userInfo: [Network.FileChangedNotificationIDsKey:[id]])
                    block(nil)
                }
                
            }
        }
    }
    
    func share(_ id: FileID, _ block: @escaping (Error?)->())
    {
        guard let caches = self.caches else
        {
            block(NetworkError.offline)
            return
        }
        
        caches.private.share(id, block)
    }
    
    func receiveNotification(_ notification: CKNotification, _ block: @escaping (Error?)->())
    {
        guard let caches = self.caches else
        {
            //precondition(false, "received CloudKit notification before cache was initialized")
            block(NetworkError.offline)
            return
        }
        
        // local change
        if notification.notificationType == .recordZone
        {
            guard let zoneNotification = notification as? CKRecordZoneNotification else
            {
                precondition(false, "record zone type notification is not actually a record zone notification object")
                block(NetworkError.other)
                return
            }
            
            //guard let zone = zoneNotification.recordZoneID else
            //{
            //    block(NetworkError.other)
            //    return
            //}
            
            print("Received changes for zone, refreshing...")
            
            caches.private.refresh
            { c,e in
                if let error = e
                {
                    onMain
                    {
                        block(error)
                    }
                }
                else if c?.count ?? 0 > 0
                {
                    onMain
                    {
                        NotificationCenter.default.post(name: Network.FileChangedNotification, object: nil, userInfo: [Network.FileChangedNotificationIDsKey:c!])
                        block(nil)
                    }
                }
            }
        }
            
        // shared change
        else if notification.notificationType == .database
        {
            guard let dbNotification = notification as? CKDatabaseNotification, dbNotification.databaseScope == .shared else
            {
                precondition(false, "database type notification is not actually a database notification object")
                block(NetworkError.other)
                return
            }
            
            print("Received database changes for database \(dbNotification.databaseScope), refreshing...")
                
            caches.shared.refresh
            { c,e in
                if let error = e
                {
                    onMain
                    {
                        block(error)
                    }
                }
                else if c?.count ?? 0 > 0
                {
                    onMain
                    {
                        NotificationCenter.default.post(name: Network.FileChangedNotification, object: nil, userInfo: [Network.FileChangedNotificationIDsKey:c!])
                        block(nil)
                    }
                }
            }
        }
    }
}
