//
//  CloudKit.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
import CloudKit

// 4. cursor pos
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
        var subscription: CKSubscription!
        var token: CKServerChangeToken?
        
        var pdb: CKDatabase
        var sdb: CKDatabase
        
        var fileCache: [FileID:FileMetadata] = [:]
        
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
                pdb.fetchAllRecordZones
                { z,e in
                    if let error = e
                    {
                        block(error)
                    }
                    else
                    {
                        for zone in z ?? []
                        {
                            if zone.zoneID.zoneName == Network.ZoneName
                            {
                                print("Retrieved existing zone, continuing...")
                                self.recordZone = zone.zoneID
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
                                        self.refresh()
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
            let cache = self
            
            let option = CKFetchRecordZoneChangesOptions()
            option.previousServerChangeToken = token
            let query = CKFetchRecordZoneChangesOperation(recordZoneIDs: [cache.recordZone], optionsByRecordZoneID: [cache.recordZone:option])
            
            var allChanges: [String] = []
            
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
                    block(allChanges, nil)
                }
            }
            query.recordChangedBlock =
            { record in
                let metadata = FileMetadata(fromRecord: record)
                cache.fileCache[record.recordID.recordName] = metadata
                allChanges.append(record.recordID.recordName)
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
            
            pdb.add(query)
        }
    }
    
    public struct FileMetadata
    {
        let name: String
        let id: CKRecordID
        let owner: CKRecordID? //TODO:
        let creationDate: Date
        let modificationDate: Date
        let metadata: Data
        let dataId: CKAsset //TODO:
        
        init(fromRecord r: CKRecord)
        {
            name = r[Network.FileNameField] as? String ?? "null"
            id = r.recordID
            owner = r.creatorUserRecordID
            creationDate = r.creationDate ?? NSDate.distantPast
            modificationDate = r.modificationDate ?? NSDate.distantPast
            dataId = r[Network.FileDataField] as! CKAsset
            
            let data = NSMutableData()
            let archiver = NSKeyedArchiver(forWritingWith: data)
            archiver.requiresSecureCoding = true
            r.encodeSystemFields(with: archiver)
            archiver.finishEncoding()
            metadata = data as Data
        }
        
        var record: CKRecord
        {
            let unarchiver = NSKeyedUnarchiver(forReadingWith: metadata)
            unarchiver.requiresSecureCoding = true
            let record = CKRecord(coder: unarchiver)!
            unarchiver.finishDecoding()
         
            record[Network.FileNameField] = name as CKRecordValue
            record[Network.FileDataField] = name as CKRecordValue
            
            return record
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
    
    public func metadata(_ id: FileID) -> FileMetadata?
    {
        guard let cache = self.cache else
        {
            return nil
        }
        
        return cache.fileCache[id]
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
    
    public func getFile(_ id: FileID, _ block: (((FileMetadata,Data)?)->()))
    {
        guard let cache = self.cache else
        {
            block(nil)
            return
        }

        if let file = cache.fileCache[id]
        {
            // TODO: when does the cache get cleared
            print("URL: \(file.dataId.fileURL)")
            let data = FileManager.default.contents(atPath: file.dataId.fileURL.path)!
            block((file, data))
        }
        else
        {
            block(nil)
        }
    }
    
    // TODO: escaping?
    public func create(file: Data, named: String, _ block: @escaping (FileMetadata,Error?)->())
    {
        guard let cache = self.cache else
        {
            block(FileMetadata(fromRecord: CKRecord(recordType: Network.FileType)), NetworkError.offline)
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
                DispatchQueue.main.async { block(FileMetadata(fromRecord: CKRecord(recordType: Network.FileType)), error) }
            }
            else
            {
                let record = r!
                let metadata = FileMetadata(fromRecord: record)
                
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
                                    cache.pdb.fetch(withRecordID: k as! CKRecordID)
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
                                            let metadata = FileMetadata(fromRecord: r!)
                                            print(metadata.dataId.fileURL)
                                            print("Conflict record changetag: \(updatedRecord.recordChangeTag ?? "")")
                                            
                                            onMain(true)
                                            {
                                                cache.fileCache[metadata.id.recordName] = metadata
                                                
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
                    let metadata = FileMetadata(fromRecord: record)
                    print("New record changetag: \(record.recordChangeTag ?? "")")

                    onMain(true)
                    {
                        cache.fileCache[metadata.id.recordName] = metadata

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
    
    func receiveNotification(_ notification: CKNotification)
    {
        guard let cache = self.cache else
        {
            precondition(false, "received CloudKit notification before cache was initialized")
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
            
            cache.refresh
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
