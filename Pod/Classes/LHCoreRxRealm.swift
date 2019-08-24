//
//  LHCoreRxRealmApiJWTExts.swift
//  LHCoreRxRealmApiJWTExts iOS
//
//  Created by Dat Ng on 6/5/19.
//  Copyright © 2019 datnm (laohac83x@gmail.com). All rights reserved.
//

import Foundation
import RealmSwift
import RxSwift

public extension Realm {
    class var tryInstance: Realm? {
        do {
            return try Realm()
        } catch { return nil }
    }
    
    @discardableResult
    class func tryWrite(realm: Realm? = nil, _ blockWrite: @escaping (_ realm: Realm) -> Void) -> Realm? {
        guard let realm = realm else {
            do {
                let mRealm = try Realm()
                do {
                    try mRealm.write({
                        blockWrite(mRealm)
                    })
                    return mRealm
                } catch {
                    return nil
                }
            } catch {
                return nil
            }
        }
        
        do {
            try realm.write({
                blockWrite(realm)
            })
            return realm
        } catch {
            return nil
        }
    }
    
    class func write(realm: Realm? = nil, _ block: @escaping (_ realm: Realm) -> Void) throws {
        if let realm = realm {
            do {
                try realm.write({
                    block(realm)
                })
            } catch let error { throw error }
        } else {
            do {
                let mRealm = try Realm()
                
                do {
                    try mRealm.write({
                        block(mRealm)
                    })
                } catch let error { throw error }
            } catch let error {
                throw error
            }
        }
    }
}

public final class LHCoreRealmConfig: NSObject {
    // you need increase this in the each relase, if you change realm models object db
    public static var schemaVersion: UInt64 = 1
    
    public static func setDefaultConfigurationMigration(_ migrationBlock: MigrationBlock? = nil) {
        let config = Realm.Configuration(
            // Set the new schema version. This must be greater than the previously used
            // version (if you've never set a schema version before, the version is 0).
            schemaVersion: schemaVersion,
            
            // Set the block which will be called automatically when opening a Realm with
            // a schema version lower than the one set above
            migrationBlock: migrationBlock)
        
        Realm.Configuration.defaultConfiguration = config
    }
}

public extension Results {
    var array: [Element]? {
        return self.count > 0 ? self.map { $0 } : nil
    }
}
