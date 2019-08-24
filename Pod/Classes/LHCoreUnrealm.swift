//
//  LHCoreRxUnrealm.swift
//  LHCoreRxRealmApiJWTExts iOS
//
//  Created by Dat Ng on 8/23/19.
//  Copyright © 2019 Lao Hac. All rights reserved.
//

import Foundation
import RealmSwift
import Unrealm
import RxSwift

public extension Realmable {
    static func findById(_ id: Int64, realm: Realm? = nil) -> Self? {
        guard let realm = realm else {
            do {
                let realm = try Realm()
                return realm.object(ofType: self, forPrimaryKey: NSNumber(value: id))
            } catch { return nil }
        }
        
        return realm.object(ofType: self, forPrimaryKey: NSNumber(value: id))
    }
    
    static func findByPrimaryKey(_ primaryKey: String, realm: Realm? = nil) -> Self? {
        guard let realm = realm else {
            do {
                let realm = try Realm()
                return realm.object(ofType: self, forPrimaryKey: primaryKey)
            } catch { return nil }
        }
        
        return realm.object(ofType: self, forPrimaryKey: primaryKey)
    }
    
    static func deleteById(_ id: Int64, realm: Realm? = nil) {
        if let item = self.findById(id, realm: realm) {
            (realm ?? Realm.tryInstance)?.delete(item)
        }
    }
    
    static func deleteByPrimaryKey(_ primaryKey: String, realm: Realm? = nil) {
        if let item = self.findByPrimaryKey(primaryKey, realm: realm) {
            (realm ?? Realm.tryInstance)?.delete(item)
        }
    }
    
    func discardChanges() {
        self.realm?.cancelWrite()
    }
}

// MARK: Realm Object type extensions
public enum RxUnrealmError: Error {
    case objectDeleted
    case unknown
}

public extension Observable where Element: Realmable {
    /**
     Returns an `Observable<Object>` that emits each time the object changes. The observable emits an initial value upon subscription.
     
     - parameter object: A Realm Object to observe
     - parameter emitInitialValue: whether the resulting `Observable` should emit its first element synchronously (e.g. better for UI bindings)
     - parameter properties: changes to which properties would triger emitting a .next event
     - returns: `Observable<Object>` will emit any time the observed object changes + one initial emit upon subscription
     */
    
    static func from(object: Element, emitInitialValue: Bool = true,
                     properties: [String]? = nil) -> Observable<Element> {
        return Observable<Element>.create { observer in
            if emitInitialValue {
                observer.onNext(object)
            }
            
            let token = object.observe { change in
                switch change {
                case let .change(changedProperties):
                    if let properties = properties, !changedProperties.contains { return properties.contains($0.name) } {
                        // if change property isn't an observed one, just return
                        return
                    }
                    observer.onNext(object)
                case .deleted:
                    observer.onError(RxUnrealmError.objectDeleted)
                case let .error(error):
                    observer.onError(error)
                }
            }
            
            return Disposables.create {
                token.invalidate()
            }
        }
    }
    
    /**
     Returns an `Observable<PropertyChange>` that emits the object `PropertyChange`s.
     
     - parameter object: A Realm Object to observe
     - returns: `Observable<PropertyChange>` will emit any time a change is detected on the object
     */
    
    static func propertyChanges(object: Element) -> Observable<PropertyChange> {
        return Observable<PropertyChange>.create { observer in
            let token = object.observe { change in
                switch change {
                case let .change(changes):
                    for change in changes {
                        observer.onNext(change)
                    }
                case .deleted:
                    observer.onError(RxUnrealmError.objectDeleted)
                case let .error(error):
                    observer.onError(error)
                }
            }
            
            return Disposables.create {
                token.invalidate()
            }
        }
    }
    
    static func objectChange(object: Element) -> Observable<ObjectChange> {
        return Observable<ObjectChange>.create { observer in
            let token = object.observe { change in
                observer.onNext(change)
            }
            
            return Disposables.create {
                token.invalidate()
            }
        }
    }
    
}

public extension Unrealm.Results {
    var array: [Element]? {
        return self.count > 0 ? self.map { $0 } : nil
    }
}

public extension Realmable {
    @discardableResult
    static func objectChanged<T: Realmable>(_ type: T.Type, forPrimary: Any?) -> Observable<ObjectChange> {
        var findObject: T?
        if let pIntValue = forPrimary as? Int64 {
            findObject = T.findById(pIntValue)
        } else if let pStringValue = forPrimary as? String {
            findObject = T.findByPrimaryKey(pStringValue)
        }
        
        guard let object = findObject else {
            return Observable<ObjectChange>.create { observer in
                observer.onError(NSError(domain: "\(self)", code: -3, userInfo: ["message": "object not found"]))
                
                return Disposables.create()
            }
        }
        return Observable.objectChange(object: object)
    }
}
