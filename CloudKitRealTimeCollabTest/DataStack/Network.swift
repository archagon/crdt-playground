//
//  CloudKit.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
import CloudKit

// 5. perf + log spam
// 5. shared db
// 6. subscribe to file list
// 7. file closing
// 8. order of ops cleanup, e.g. controllers, state machine
// 9. zip/async perf tweaks
// copy ckasset data to temp storage
// TODO: why did .owner = newOwner without remap work elsewhere?

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
    }
    
    public typealias FileID = String
    
    public static let FileType = "File"
    public static let ZoneName = "Files"
    public static let SubscriptionName = "FilesSubscription"
    
    public static let FileNameField = "name"
    public static let FileDataField = "crdt"
    
    private class Cache
    {
        var recordZone: CKRecordZoneID!
        var sharedRecordZone: CKRecordZoneID?
        var subscription: CKSubscription!
        var token: CKServerChangeToken?
        
        var pdb: CKDatabase
        var sdb: CKDatabase
        
        var fileCache: [FileID:FileCache] = [:]
        
        init()
        {
            self.pdb = CKContainer.default().privateCloudDatabase
            self.sdb = CKContainer.default().sharedCloudDatabase
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
                // TODO: do this on demand?
                let szones = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
                szones.database = sdb
                szones.fetchRecordZonesCompletionBlock =
                { zones, error in
                    if let error = error
                    {
                        print("Shared zone error: \(error)")
                        //block(error)
                    }
                    else
                    {
                        for zone in zones ?? [:]
                        {
                            if zone.0.zoneName == Network.ZoneName
                            {
                                print("Retrieved shared zone, continuing...")
                                self.sharedRecordZone = zone.0
                                //block(nil)
                                return
                            }
                        }
                    }
                }
                
                let pzones = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
                pzones.database = pdb
                pzones.fetchRecordZonesCompletionBlock =
                { zones, error in
                    if let error = error
                    {
                        block(error)
                    }
                    else
                    {
                        for zone in zones ?? [:]
                        {
                            if zone.0.zoneName == Network.ZoneName
                            {
                                print("Retrieved existing zone, continuing...")
                                self.recordZone = zone.0
                                block(nil)
                                return
                            }
                        }
                        
                        createNewZone: do
                        {
                            let zone = CKRecordZone(zoneName: Network.ZoneName)
                            
                            self.pdb.save(zone)
                            { z,e in
                                if let error = e
                                {
                                    block(error)
                                }
                                else
                                {
                                    print("Created zone, continuing...")
                                    self.recordZone = z!.zoneID
                                    block(nil)
                                    return
                                }
                            }
                        }
                    }
                }
                
                pzones.addDependency(szones)
                
                let queue = OperationQueue()
                queue.addOperations([szones, pzones], waitUntilFinished: false)
            }
            
            func subscribe(_ block: @escaping (Error?)->())
            {
                //pdb.fetchAllSubscriptions
                //{ subs,e in
                //    for sub in subs ?? []
                //    {
                //        print("Deleting \(sub.subscriptionID)")
                //        self.pdb.delete(withSubscriptionID: sub.subscriptionID) { s,e in }
                //    }
                //}
                //return;
                
                pdb.fetch(withSubscriptionID: Network.SubscriptionName)
                { s,e in
                    if let error = e as? CKError, error.code == CKError.unknownItem
                    {
                        let subscription = CKRecordZoneSubscription(zoneID: self.recordZone, subscriptionID: Network.SubscriptionName)
                        let notification = CKNotificationInfo()
                        notification.alertBody = "files changed"
                        subscription.notificationInfo = notification

                        self.pdb.save(subscription)
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
                                        self.refresh(shared: true)
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
        
        func refresh(shared: Bool, _ block: @escaping ([Network.FileID]?,Error?)->())
        {
            precondition(!shared || self.sharedRecordZone != nil)
            
            let cache = self
            
            let option = CKFetchRecordZoneChangesOptions()
            option.previousServerChangeToken = token
            let query = CKFetchRecordZoneChangesOperation(recordZoneIDs: [(shared ? cache.sharedRecordZone! : cache.recordZone)], optionsByRecordZoneID: [(shared ? cache.sharedRecordZone! : cache.recordZone):option])
            
            var allChanges: [String] = []
            var recordsAwaitingShare = Set<CKRecord>()
            var pendingShares = [String:CKShare]()
            
            query.recordZoneChangeTokensUpdatedBlock =
            { zone,token,data in
                print("Fetching record info, received token: \(token?.description ?? "(null)")")
                cache.token = token
            }
            query.recordZoneFetchCompletionBlock =
            { zone,token,data,_,e in
                if let error = e
                {
                    block(nil, error)
                }
                else
                {
                    print("Fetched record info, received token: \(token?.description ?? "(null)")")
                    cache.token = token
                    for record in recordsAwaitingShare
                    {
                        if let share = pendingShares[record.share!.recordID.recordName]
                        {
                            cache.fileCache[record.recordID.recordName]!.associateShare(share)
                        }
                        else
                        {
                            assert(false, "no share found for shared record")
                        }
                    }
                    block(allChanges, nil)
                }
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
                    cache.fileCache[record.recordID.recordName] = metadata
                    allChanges.append(record.recordID.recordName)
                    
                    if record.share != nil
                    {
                        recordsAwaitingShare.insert(record)
                    }
                }
            }
            query.recordWithIDWasDeletedBlock =
            { record,str in
                cache.fileCache.removeValue(forKey: record.recordName)
                allChanges.append(record.recordName)
            }
            query.fetchRecordZoneChangesCompletionBlock =
            { e in
                print("What is this all about?")
            }
            
            if shared
            {
                sdb.add(query)
            }
            else
            {
                pdb.add(query)
            }
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
    
    private var cache: Cache?
    
    private enum MergeStatus
    {
        case empty
        case enqueued(data: Data, block: (Error?)->())
        case running
        case runningAndEnqueued(data: Data, block: (Error?)->())
    }
    
    private var needToMerge: [FileID:MergeStatus] = [:] //always access this var on main!!
    private var mergeOperationsQueue: OperationQueue
    
    public init()
    {
        self.mergeOperationsQueue = OperationQueue()
        self.mergeOperationsQueue.qualityOfService = .userInitiated
        
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
        precondition(self.cache == nil)
        
        let cache = Cache()
        cache.load
        { e in
            if let error = e
            {
                onMain { block(error) }
            }
            else
            {
                self.cache = cache
                onMain { block(nil) }
            }
        }
    }
    
    public func ids() -> [FileID]
    {
        guard let cache = self.cache else
        {
            return []
        }
        
        return Array<FileID>(cache.fileCache.keys)
    }
    
    public func metadata(_ id: FileID) -> FileCache?
    {
        guard let cache = self.cache else
        {
            return nil
        }
        
        return cache.fileCache[id]
    }
    
    // gross, but we need this for use with UICloudSharingController
    public func associateShare(_ share: CKShare?, withId id: FileID)
    {
        guard let cache = self.cache else
        {
            return
        }
        
        cache.fileCache[id]?.associateShare(share)
        // TODO: ensure that record has nil share
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
        guard let cache = self.cache else
        {
            block(nil)
            return
        }

        if let file = cache.fileCache[id]
        {
            // TODO: when does the cache get cleared
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
        guard let cache = self.cache else
        {
            block(FileCache(fromRecord: CKRecord(recordType: Network.FileType)), NetworkError.offline)
            return
        }
        
        let record = CKRecord(recordType: Network.FileType, zoneID: cache.recordZone)
        record[Network.FileNameField] = named as CKRecordValue
        
        let name = "\(named)-\(file.hashValue).crdt"
        let fileUrl = URL.init(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(name))
        try! file.write(to: fileUrl)
        record[Network.FileDataField] = CKAsset(fileURL: fileUrl)
        
        cache.pdb.save(record)
        { r,e in
            defer
            {
                // TODO: we don't delete this b/c it's necessary for the cache; maybe on quit?
                //try! FileManager.default.removeItem(at: fileUrl)
            }
            
            if let error = e
            {
                DispatchQueue.main.async { block(FileCache(fromRecord: CKRecord(recordType: Network.FileType)), error) }
            }
            else
            {
                let record = r!
                let metadata = FileCache(fromRecord: record)
                
                onMain(true)
                {
                    cache.fileCache[metadata.id.recordName] = metadata
                
                    block(metadata, nil)
                }
            }
        }
    }
    
    private func pumpMergeQueue(forId id: FileID, finishedRunning: Bool = false)
    {
        // TODO: PERF: make this run on another thread
        func runMerge(data: Data, block: @escaping (Error?)->())
        {
            guard let cache = self.cache else
            {
                block(NetworkError.offline)
                return
            }
            
            print("Queuing merge record: \(id.hashValue)")

            guard let metadata = cache.fileCache[id] else
            {
                block(NetworkError.nonExistentFile)
                return
            }

            let record = metadata.record
            
            let name = "\(id).crdt"
            let fileUrl = URL.init(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(name))
            try! data.write(to: fileUrl)
            record[Network.FileDataField] = CKAsset(fileURL: fileUrl)

            print("Adding merge with old record changetag: \(record.recordChangeTag ?? "")")

            let mergeOp = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            mergeOp.perRecordProgressBlock =
            { r,p in
                print("Making progress on record \(r.recordChangeTag ?? ""): \(p)")
            }
            mergeOp.database = (metadata.remoteShared ? cache.sdb : cache.pdb)
            print("Sending to shared: \(metadata.remoteShared)")
            mergeOp.savePolicy = .ifServerRecordUnchanged
            mergeOp.qualityOfService = .userInitiated
            mergeOp.modifyRecordsCompletionBlock =
            { saved,deleted,e in
                defer
                {
                    // TODO: we don't delete this b/c it's necessary for the cache; maybe on quit?
                    //try? FileManager.default.removeItem(at: fileUrl)

                    self.pumpMergeQueue(forId: id, finishedRunning: true)
                }

                if let error = e
                {
                    onMain(true)
                    {
                        self.needToMerge[id] = nil
                        
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
                                    guard let cache = self.cache else
                                    {
                                        block(NetworkError.offline)
                                        return
                                    }
                                    
                                    // necessary b/c err2 does not actually contain asset
                                    (metadata.remoteShared ? cache.sdb : cache.pdb).fetch(withRecordID: k as! CKRecordID)
                                    { r,e in
                                        if let error = e
                                        {
                                            onMain(true)
                                            {
                                                block(error)
                                            }
                                        }
                                        else
                                        {
                                            let metadata = FileCache(fromRecord: r!)
                                            print(metadata.data.fileURL)
                                            print("Conflict record changetag: \(updatedRecord.recordChangeTag ?? "")")
                                            
                                            onMain(true)
                                            {
                                                let share = cache.fileCache[metadata.id.recordName]?.associatedShare
                                                cache.fileCache[metadata.id.recordName] = metadata
                                                cache.fileCache[metadata.id.recordName]!.associateShare(share)
                                                
                                                block(NetworkError.mergeConflict)
                                                
                                                return
                                            }
                                        }
                                    }
                                }
                            }
                        }
                            
                        uncaughtError: do
                        {
                            block(error)
                        }
                    }
                }
                else
                {
                    let record = saved!.first!
                    let metadata = FileCache(fromRecord: record)
                    print("New record changetag: \(record.recordChangeTag ?? "")")

                    onMain(true)
                    {
                        let share = cache.fileCache[metadata.id.recordName]?.associatedShare
                        cache.fileCache[metadata.id.recordName] = metadata
                        cache.fileCache[metadata.id.recordName]!.associateShare(share)

                        block(nil)
                    }
                }
            }
            
            self.mergeOperationsQueue.addOperation(mergeOp)
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
        guard let _ = self.cache else
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
        guard let cache = self.cache else
        {
            block(NetworkError.offline)
            return
        }
        
        guard let metadata = cache.fileCache[id] else
        {
            block(NetworkError.nonExistentFile)
            return
        }
        
        cache.pdb.delete(withRecordID: metadata.id)
        { _,e in
            onMain(true)
            {
                if e == nil
                {
                    cache.fileCache.removeValue(forKey: id)
                }
            
                block(e)
            }
        }
    }
    
    func share(_ id: FileID, _ block: @escaping (Error?)->())
    {
        guard let cache = self.cache else
        {
            block(NetworkError.offline)
            return
        }
        
        guard let metadata = cache.fileCache[id] else
        {
            block(NetworkError.nonExistentFile)
            return
        }
        
        let record: CKRecord? = metadata.record
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
                    cache.fileCache[id] = FileCache(fromRecord: saved![recordIndex], withShare: (saved![shareIndex] as! CKShare))
                    
                    block(nil)
                }
            }
        }

        cache.pdb.add(op)
    }
    
    func receiveNotification(_ notification: CKNotification)
    {
        guard let cache = self.cache else
        {
            //precondition(false, "received CloudKit notification before cache was initialized")
            return
        }
        
        if notification.notificationType == .recordZone
        {
            guard let zoneNotification = notification as? CKRecordZoneNotification else
            {
                precondition(false, "record zone type notification is not actually a record zone notification object")
                return
            }
            
            guard let zone = zoneNotification.recordZoneID else
            {
                return
            }
            
            print("Received changes for zone \(zone), refreshing...")
            
            cache.refresh(shared: zone == cache.sharedRecordZone)
            { c,e in
                if let error = e
                {
                    print("Sync error: \(error)")
                }
                else if c?.count ?? 0 > 0
                {
                    onMain
                    {
                        NotificationCenter.default.post(name: Network.FileChangedNotification, object: nil, userInfo: [Network.FileChangedNotificationIDsKey:c!])
                    }
                }
            }
        }
    }
}
