//
//  CloudKit.swift
//  CloudKitRealTimeCollabTest
//
//  Created by Alexei Baboulevitch on 2017-10-20.
//  Copyright © 2017 Alexei Baboulevitch. All rights reserved.
//

import Foundation
import CloudKit

// owns synced CloudKit objects and their caches, working at data (binary) layer
class Network
{
    public enum NetworkError: Error
    {
        case offline
        case couldNotLogIn
        case updatingNonexistentFile
    }
    
    public typealias FileID = CKRecordID
    
    public static let FileType = "File"
    public static let FileNameField = "name"
    public static let FileDataField = "crdt"
    
    private class Cache
    {
        var pdb: CKDatabase
        var sdb: CKDatabase
        
        var fileCache: [FileID:FileMetadata] = [:]
        
        init()
        {
            self.pdb = CKContainer.default().privateCloudDatabase
            self.sdb = CKContainer.default().sharedCloudDatabase
        }
    }
    
    public struct FileMetadata
    {
        let name: String
        let id: FileID
        let owner: CKRecordID? //TODO:
        let creationDate: Date
        let modificationDate: Date
        let dataId: CKAsset //TODO:
        
        init(fromRecord r: CKRecord)
        {
            name = r[Network.FileNameField] as? String ?? "null"
            id = r.recordID
            owner = r.creatorUserRecordID
            creationDate = r.creationDate ?? NSDate.distantPast
            modificationDate = r.modificationDate ?? NSDate.distantPast
            dataId = r[Network.FileDataField] as! CKAsset
        }
        
        var record: CKRecord
        {
            let record = CKRecord(recordType: Network.FileType)
            record[Network.FileNameField] = name as CKRecordValue
            return record
        }
    }
    
    private var cache: Cache?
    
    public init()
    {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.CKAccountChanged, object: self, queue: nil)
        { n in
            self.updateLogin
            { e in
                assert(false)
                // TODO: what to do here?
            }
        }
    }
    
    public func updateLogin(_ block: @escaping (Error?)->())
    {
        CKContainer.default().accountStatus
        { s,e in
            if s == .available
            {
                self.cache = Cache()
                
                DispatchQueue.main.async { block(nil) }
            }
            else
            {
                self.cache = nil
                
                if let error = e
                {
                    DispatchQueue.main.async { block(error) }
                }
                else
                {
                    DispatchQueue.main.async { block(NetworkError.couldNotLogIn) }
                }
            }
        }
    }
    
    // TODO: notify of changes
    public func syncCache(_ block: @escaping (Error?)->())
    {
        guard let cache = self.cache else
        {
            block(NetworkError.offline)
            return
        }
        
        let sort = NSSortDescriptor(key: "modificationDate", ascending: false)
        let filesQuery = CKQuery(recordType: Network.FileType, predicate: NSPredicate(value: true))
        filesQuery.sortDescriptors = [sort]

        cache.pdb.perform(filesQuery, inZoneWith: nil, completionHandler:
        { rs,e in
            if let error = e
            {
                DispatchQueue.main.async { block(error) }
            }
            else
            {
                var recordMap: [FileID:FileMetadata] = [:]
                for record in rs!
                {
                    let metadata = FileMetadata(fromRecord: record)
                    recordMap[metadata.id] = metadata
                }
                
                cache.fileCache = recordMap
                
                DispatchQueue.main.async { block(nil) }
            }
        })
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
        
        let record = CKRecord(recordType: Network.FileType)
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
                
                cache.fileCache[metadata.id] = metadata
                
                DispatchQueue.main.async { block(metadata, nil) }
            }
        }
    }
    
    // TODO: escaping?
    public func merge(_ id: FileID, _ data: Data, _ block: @escaping (Error?)->())
    {
        guard let cache = self.cache else
        {
            block(NetworkError.offline)
            return
        }
        
        guard let metadata = cache.fileCache[id] else
        {
            block(NetworkError.updatingNonexistentFile)
            return
        }
        
        let record = metadata.record
        
        let name = "\(id).crdt"
        let fileUrl = URL.init(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(name))
        try! data.write(to: fileUrl)
        record[Network.FileDataField] = CKAsset(fileURL: fileUrl)
        
        self.cache?.pdb.save(record, completionHandler:
        { r,e in
            defer
            {
                try! FileManager.default.removeItem(at: fileUrl)
            }
            
            if let error = e
            {
                DispatchQueue.main.async { block(error) }
            }
            else
            {
                DispatchQueue.main.async { block(nil) }
            }
        })
    }
    
//    func deleteFile(_ fileId: FileID)
//    {
//        if self.user == nil
//        {
//            return
//        }
//    }
}
