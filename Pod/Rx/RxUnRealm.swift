//
//  RxUnRealm Extension
//
//  Created by Dat Ng on 6/5/19.
//  Copyright © 2019 datnm (laohac83x@gmail.com). All rights reserved.
//

import Foundation
import RealmSwift
import Unrealm
import RxSwift

public enum RxUnrealmError: Error {
    case objectDeleted
    case unknown
}

// MARK: Realm Collections type extensions

/**
 `NotificationEmitter` is a protocol to allow for Realm's collections to be handled in a generic way.
 
 All collections already include a `addNotificationBlock(_:)` method - making them conform to `NotificationEmitter` just makes it easier to add Rx methods to them.
 
 The methods of essence in this protocol are `asObservable(...)`, which allow for observing for changes on Realm's collections.
 */
public protocol NotificationEmitter {
    associatedtype ElementType: RealmableBase
    
    /**
     Returns a `NotificationToken`, which while retained enables change notifications for the current collection.
     
     - returns: `NotificationToken` - retain this value to keep notifications being emitted for the current collection.
     */
    func observe(_ block: @escaping (RealmCollectionChange<Self>) -> Void) -> NotificationToken
    
    func toArray() -> [ElementType]
    
    func toCollection() -> Unrealm.Results<ElementType>
}

extension Unrealm.Results: NotificationEmitter {
    public typealias ElementType = Element

    public func toArray() -> [ElementType] {
        return Array(self)
    }
    
    public func toCollection() -> Unrealm.Results<ElementType> {
        return self
    }
}

/**
 `RealmChangeset` is a struct that contains the data about a single realm change set.
 
 It includes the insertions, modifications, and deletions indexes in the data set that the current notification is about.
 */
public struct RealmChangeset {
    /// the indexes in the collection that were deleted
    public let deleted: [Int]
    
    /// the indexes in the collection that were inserted
    public let inserted: [Int]
    
    /// the indexes in the collection that were modified
    public let updated: [Int]
}

public extension ObservableType where Element: NotificationEmitter {
    /**
     Returns an `Observable<Element>` that emits each time the collection data changes.
     The observable emits an initial value upon subscription.
     
     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting `Observable` should emit its first element synchronously (e.g. better for UI bindings)
     
     - returns: `Observable<Element>`, e.g. when called on `Results<Model>` it will return `Observable<Results<Model>>`, on a `List<User>` it will return `Observable<List<User>>`, etc.
     */
    static func collection(from collection: Element, synchronousStart: Bool = true)
        -> Observable<Element> {
            return Observable.create { observer in
                if synchronousStart {
                    observer.onNext(collection)
                }
                
                let token = collection.observe { changeset in
                    
                    let value: Element
                    
                    switch changeset {
                    case let .initial(latestValue):
                        guard !synchronousStart else { return }
                        value = latestValue
                        
                    case .update(let latestValue, _, _, _):
                        value = latestValue
                        
                    case let .error(error):
                        observer.onError(error)
                        return
                    }
                    
                    observer.onNext(value)
                }
                
                return Disposables.create {
                    token.invalidate()
                }
            }
    }
    
    /**
     Returns an `Observable<Array<Element.Element>>` that emits each time the collection data changes. The observable emits an initial value upon subscription.
     The result emits an array containing all objects from the source collection.
     
     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting Observable should emit its first element synchronously (e.g. better for UI bindings)
     
     - returns: `Observable<Array<Element.Element>>`, e.g. when called on `Results<Model>` it will return `Observable<Array<Model>>`, on a `List<User>` it will return `Observable<Array<User>>`, etc.
     */
    static func array(from collection: Element, synchronousStart: Bool = true)
        -> Observable<[Element.ElementType]> {
            return Observable.collection(from: collection, synchronousStart: synchronousStart)
                .map { $0.toArray() }
    }
    
    /**
     Returns an `Observable<(Element, RealmChangeset?)>` that emits each time the collection data changes. The observable emits an initial value upon subscription.
     
     When the observable emits for the first time (if the initial notification is not coalesced with an update) the second tuple value will be `nil`.
     
     Each following emit will include a `RealmChangeset` with the indexes inserted, deleted or modified.
     
     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting Observable should emit its first element synchronously (e.g. better for UI bindings)
     
     - returns: `Observable<(AnyRealmCollection<Element.Element>, RealmChangeset?)>`
     */
    static func changeset(from collection: Element, synchronousStart: Bool = true)
        -> Observable<(Unrealm.Results<Element.ElementType>, RealmChangeset?)> {
            return Observable.create { observer in
                if synchronousStart {
                    observer.onNext((collection.toCollection(), nil))
                }
                
                let token = collection.toCollection().observe { changeset in
                    
                    switch changeset {
                    case let .initial(value):
                        guard !synchronousStart else { return }
                        observer.onNext((value, nil))
                    case let .update(value, deletes, inserts, updates):
                        observer.onNext((value, RealmChangeset(deleted: deletes, inserted: inserts, updated: updates)))
                    case let .error(error):
                        observer.onError(error)
                        return
                    }
                }
                
                return Disposables.create {
                    token.invalidate()
                }
            }
    }
    
    /**
     Returns an `Observable<(Array<Element.Element>, RealmChangeset?)>` that emits each time the collection data changes. The observable emits an initial value upon subscription.
     
     This method emits an `Array` containing all the realm collection objects, this means they all live in the memory. If you're using this method to observe large collections you might hit memory warnings.
     
     When the observable emits for the first time (if the initial notification is not coalesced with an update) the second tuple value will be `nil`.
     
     Each following emit will include a `RealmChangeset` with the indexes inserted, deleted or modified.
     
     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting Observable should emit its first element synchronously (e.g. better for UI bindings)
     
     - returns: `Observable<(Array<Element.Element>, RealmChangeset?)>`
     */
    static func arrayWithChangeset(from collection: Element, synchronousStart: Bool = true)
        -> Observable<([Element.ElementType], RealmChangeset?)> {
            return Observable.changeset(from: collection)
                .map { ($0.toArray(), $1) }
    }
}

public extension Observable {
    /**
     Returns an `Observable<(Realm, Realm.Notification)>` that emits each time the Realm emits a notification.
     
     The Observable you will get emits a tuple made out of:
     
     * the realm that emitted the event
     * the notification type: this can be either `.didChange` which occurs after a refresh or a write transaction ends,
     or `.refreshRequired` which happens when a write transaction occurs from a different thread on the same realm file
     
     For more information look up: [Realm.Notification](https://realm.io/docs/swift/latest/api/Enums/Notification.html)
     
     - parameter realm: A Realm instance
     - returns: `Observable<(Realm, Realm.Notification)>`, which you can subscribe to
     */
    static func from(realm: Realm) -> Observable<(Realm, Realm.Notification)> {
        return Observable<(Realm, Realm.Notification)>.create { observer in
            let token = realm.observe { (notification: Realm.Notification, realm: Realm) in
                observer.onNext((realm, notification))
            }
            
            return Disposables.create {
                token.invalidate()
            }
        }
    }
}

// MARK: Realm type extensions

extension Realm: ReactiveCompatible {}

extension Reactive where Base: Realm {
    /**
     Returns bindable sink wich adds object sequence to the current Realm
     
     - parameter: update - if set to `true` it will override existing objects with matching primary key
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<S>`, which you can use to subscribe an `Observable` to
     */
    public func add<S: Sequence>(update: Bool = false, onError: ((S?, Error) -> Void)? = nil)
        -> AnyObserver<S> where S.Iterator.Element: Realmable {
            return UnrealmObserver(realm: base) { realm, elements, error in
                guard let realm = realm else {
                    onError?(nil, error ?? RxUnrealmError.unknown)
                    return
                }
                
                do {
                    try realm.write {
                        realm.add(elements, update: update)
                    }
                } catch let e {
                    onError?(elements, e)
                }
                }
                .asObserver()
    }
    
    /**
     Returns bindable sink wich adds an object to Realm
     
     - parameter: update - if set to `true` it will override existing objects with matching primary key
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<O>`, which you can use to subscribe an `Observable` to
     */
    public func add<O: Realmable>(update: Bool = false,
                               onError: ((O?, Error) -> Void)? = nil) -> AnyObserver<O> {
        return UnrealmObserver(realm: base) { realm, element, error in
            guard let realm = realm else {
                onError?(nil, error ?? RxUnrealmError.unknown)
                return
            }
            
            do {
                try realm.write {
                    realm.add(element, update: update)
                }
            } catch let e {
                onError?(element, e)
            }
            }.asObserver()
    }
    
    /**
     Returns bindable sink wich deletes objects in sequence from Realm.
     
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<S>`, which you can use to subscribe an `Observable` to
     */
    public func delete<S: Sequence>(onError: ((S?, Error) -> Void)? = nil)
        -> AnyObserver<S> where S.Iterator.Element: Realmable {
            return UnrealmObserver(realm: base, binding: { realm, elements, error in
                guard let realm = realm else {
                    onError?(nil, error ?? RxUnrealmError.unknown)
                    return
                }
                
                do {
                    try realm.write {
                        realm.delete(elements)
                    }
                } catch let e {
                    onError?(elements, e)
                }
            }).asObserver()
    }
    
    /**
     Returns bindable sink wich deletes objects in sequence from Realm.
     
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<O>`, which you can use to subscribe an `Observable` to
     */
    public func delete<O: Realmable>(onError: ((O?, Error) -> Void)? = nil) -> AnyObserver<O> {
        return UnrealmObserver(realm: base, binding: { realm, element, error in
            guard let realm = realm else {
                onError?(nil, error ?? RxUnrealmError.unknown)
                return
            }
            
            do {
                try realm.write {
                    realm.delete(element)
                }
            } catch let e {
                onError?(element, e)
            }
        }).asObserver()
    }
}

extension Reactive where Base: Realm {
    /**
     Returns bindable sink wich adds object sequence to a Realm
     
     - parameter: configuration (by default uses `Realm.Configuration.defaultConfiguration`)
     to use to get a Realm for the write operations
     - parameter: update - if set to `true` it will override existing objects with matching primary key
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<S>`, which you can use to subscribe an `Observable` to
     */
    public static func add<S: Sequence>(configuration: Realm.Configuration = Realm.Configuration.defaultConfiguration,
                                        update: Bool = false,
                                        onError: ((S?, Error) -> Void)? = nil) -> AnyObserver<S> where S.Iterator.Element: Realmable {
        return UnrealmObserver(configuration: configuration) { realm, elements, error in
            guard let realm = realm else {
                onError?(nil, error ?? RxUnrealmError.unknown)
                return
            }
            
            do {
                try realm.write {
                    realm.add(elements, update: update)
                }
            } catch let e {
                onError?(elements, e)
            }
            }.asObserver()
    }
    
    /**
     Returns bindable sink which adds an object to a Realm
     
     - parameter: configuration (by default uses `Realm.Configuration.defaultConfiguration`)
     to use to get a Realm for the write operations
     - parameter: update - if set to `true` it will override existing objects with matching primary key
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<O>`, which you can use to subscribe an `Observable` to
     */
    public static func add<O: Realmable>(configuration: Realm.Configuration = Realm.Configuration.defaultConfiguration,
                                      update: Bool = false,
                                      onError: ((O?, Error) -> Void)? = nil) -> AnyObserver<O> {
        return UnrealmObserver(configuration: configuration) { realm, element, error in
            guard let realm = realm else {
                onError?(nil, error ?? RxUnrealmError.unknown)
                return
            }
            
            do {
                try realm.write {
                    realm.add(element, update: update)
                }
            } catch let e {
                onError?(element, e)
            }
            }.asObserver()
    }
    
    /**
     Returns bindable sink, which deletes objects in sequence from Realm.
     
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<S>`, which you can use to subscribe an `Observable` to
     */
    public static func delete<S: Sequence>(onError: ((S?, Error) -> Void)? = nil)
        -> AnyObserver<S> where S.Iterator.Element: Realmable {
            return AnyObserver { event in
                
                guard let elements = event.element,
                    var generator = elements.makeIterator() as S.Iterator?,
                    let first = generator.next(),
                    let realm = first.realm else {
                        onError?(nil, RxUnrealmError.unknown)
                        return
                }
                
                do {
                    try realm.write {
                        realm.delete(elements)
                    }
                } catch let e {
                    onError?(elements, e)
                }
            }
    }
    
    /**
     Returns bindable sink, which deletes object from Realm
     
     - parameter: onError - closure to implement custom error handling
     - returns: `AnyObserver<O>`, which you can use to subscribe an `Observable` to
     */
    public static func delete<O: Realmable>(onError: ((O?, Error) -> Void)? = nil) -> AnyObserver<O> {
        return AnyObserver { event in
            
            guard let element = event.element, let realm = element.realm else {
                onError?(nil, RxUnrealmError.unknown)
                return
            }
            
            do {
                try realm.write {
                    realm.delete(element)
                }
            } catch let e {
                onError?(element, e)
            }
        }
    }
}

public extension Reactive where Base: Realmable {
    
}


