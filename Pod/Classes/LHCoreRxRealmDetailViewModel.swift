//
//  LHCoreRxRealmDetailViewModel.swift
//  Example
//
//  Created by Dat Ng on 6/10/19.
//  Copyright © 2019 datnm (laohac83x@gmail.com). All rights reserved.
//

import Foundation
import RealmSwift
import SwiftyJSON
import RxSwift
import RxCocoa

public struct LHCoreDetailModel {
    public enum State: Equatable {
        public static func == (lhs: LHCoreDetailModel.State, rhs: LHCoreDetailModel.State) -> Bool {
            switch (lhs, rhs) {
            case (.requesting, .requesting), (.ideal, .ideal):
                return true
            case (.error(let lError), .error(let rError)):
                return (lError as NSError).isEqual(rError as NSError)
            default:
                return false
            }
        }
        
        case requesting
        case ideal
        case error(Error)
    }
    
    public enum StateResult<T> {
        case ideal(T?)
        case requesting
    }
    
    public enum StateResultWithOptions<T, O> {
        case ideal(T, O?)
        case requesting
    }
}

public enum ObjectPrimaryKey {
    case int64(Int64)
    case string(String)
    
    public var int64Value: Int64 {
        switch self {
        case .int64(let idValue): return idValue
        case .string(_): return -1
        }
    }
    
    public var stringValue: String {
        switch self {
        case .int64(_): return "-1"
        case .string(let idValue): return idValue
        }
    }
}

// type: for model with many categories, you can filter than easier
public protocol LHCoreRxRealmFindItemByPrimaryKey {
    associatedtype T: LHCoreRealmable
    static func findItemByPrimaryKey(_ primaryKey: ObjectPrimaryKey, modelOption: Int) -> Observable<LHCoreDetailModel.StateResult<T>>
    static func fetchWithPrimaryKey(_ itemPrimaryKey: ObjectPrimaryKey, modelOption: Int) -> Observable<T>
}

open class LHCoreRxRealmDetailViewModel<T: LHCoreRxRealmFindItemByPrimaryKey> {
    public let itemPrimaryKey: ObjectPrimaryKey
    fileprivate var mItem: T? = nil
    fileprivate var modelOption: Int = 0
    
    public let disposeBag = DisposeBag()
    public let state = BehaviorRelay<LHCoreDetailModel.State>(value: .ideal)
    public var indicatorViewHidden: Observable<Bool>?
    public var noDataFirstViewHidden: Observable<Bool>?
    public var retryViewHidden: Observable<Bool>?
    public var networkErrorBannerHidden: Observable<Bool>?
    
    //use to show message error on network state banner
    var currentError: NSError?
    public var item: T? { return self.mItem }
    
    public init(itemPrimaryKey: ObjectPrimaryKey, modelOption: Int = 0) {
        assert(Thread.isMainThread)
        
        self.itemPrimaryKey = itemPrimaryKey
        self.modelOption = modelOption
        
        commonInit()
    }
    
    public init(id: Int64, modelOption: Int = 0) {
        assert(Thread.isMainThread)
        
        self.itemPrimaryKey = ObjectPrimaryKey.int64(id)
        self.modelOption = modelOption
        
        commonInit()
    }
    
    public init(primaryKey: String, modelOption: Int = 0) {
        assert(Thread.isMainThread)
        
        self.itemPrimaryKey = ObjectPrimaryKey.string(primaryKey)
        self.modelOption = modelOption
        
        commonInit()
    }
    
    internal func commonInit() {
        indicatorViewHidden = state.asObservable().map { [unowned self] state -> Bool in
            switch state {
            case .requesting where self.item == nil: return false
            default: return true
            }}.distinctUntilChanged()
        
        noDataFirstViewHidden = state.asObservable().map { [unowned self] state -> Bool in
            switch state {
            case .ideal where self.item == nil: return false
            default: return true
            }}
            .distinctUntilChanged()
        
        retryViewHidden = state.asObservable().map { [unowned self] state -> Bool in
            switch state {
            case .error where self.item == nil : return false
            default: return true
            }
            }
            .distinctUntilChanged()
        
        networkErrorBannerHidden = state.asObservable().map { [unowned self] state -> Bool in
            if case .error = state, self.item != nil { return false } else { return true }
            }
            .distinctUntilChanged()
        
        var itemPrimaryValue: Any?
        switch itemPrimaryKey {
        case .int64(let idValue): itemPrimaryValue = idValue
        case .string(let idValue): itemPrimaryValue = idValue
        }
        T.T.objectChanged(T.T.self, forPrimary: itemPrimaryValue).subscribe(onNext: { [weak self] (changed) in
            switch changed {
            case .deleted:
                self?.mItem = nil
                self?.state.accept(.ideal)
            case .change(_):
                self?.state.accept(.ideal)
            case .error(let error):
                self?.state.accept(.error(error))
            }
        }, onError: { [weak self] (error) in
            self?.state.accept(.error(error))
        }).disposed(by: disposeBag)
    }
    
    public func fetch(completion: ((NSError?) -> Void)? = nil) {
        assert(Thread.isMainThread)
        
        T.findItemByPrimaryKey(itemPrimaryKey, modelOption: self.modelOption).subscribe(
            onNext: { [weak self] result in
                MainScheduler.ensureExecutingOnScheduler()
                
                switch result {
                case .requesting:
                    self?.state.accept(.requesting)
                case .ideal(let item):
                    self?.mItem = item as? T
                    self?.state.accept(.ideal)
                    completion?(nil)
                }
            },
            onError: { [weak self] mError in
                MainScheduler.ensureExecutingOnScheduler()
                
                let error = mError as NSError
                self?.currentError = error
                
                if error.isUnauthorizedError {
                    // UnAuthenticate error, logout ??
                    self?.mItem = nil
                    self?.state.accept(.error(error))
                } else {
                    self?.state.accept(.error(error))
                }
                completion?(error)
        })
            .disposed(by: self.disposeBag)
    }
    
    public func refresh(completion: ((NSError?) -> Void)? = nil) {
        if case .requesting = state.value {
            completion?(nil)
        } else {
            self.fetch(completion: completion)
        }
    }
    
    func resetError() {
        state.accept(.ideal)
    }
}

public extension LHCoreRxRealmFindItemByPrimaryKey where Self: Object {
    static func findItemByPrimaryKey(_ primaryKey: ObjectPrimaryKey, modelOption: Int) -> Observable<LHCoreDetailModel.StateResult<Self>> {
        return Observable.create({ (observable: AnyObserver<LHCoreDetailModel.StateResult<Self>>) -> Disposable in
            // Get Local data
            if let realm = Realm.tryInstance {
                switch primaryKey {
                case .int64(let idValue):
                    if let item = realm.object(ofType: Self.self, forPrimaryKey: NSNumber(value: idValue)) {
                        assert(Thread.isMainThread)
                        observable.onNext(.ideal(item))
                    }
                    
                case .string(let idValue):
                    if let item = realm.object(ofType: Self.self, forPrimaryKey: idValue) {
                        assert(Thread.isMainThread)
                        observable.onNext(.ideal(item))
                    }
                }
                
                observable.onNext(.requesting)
            } else {
                observable.onNext(.requesting)
            }
            
            return self.fetchWithPrimaryKey(primaryKey, modelOption: modelOption).observeOn(MainScheduler.instance).subscribe(
                onNext: { _ in
                    MainScheduler.ensureExecutingOnScheduler()
                    
                    do {
                        let realm = try Realm()
                        realm.refresh()
                        
                        switch primaryKey {
                        case .int64(let idValue):
                            if let item = realm.object(ofType: Self.self, forPrimaryKey: NSNumber(value: idValue)) {
                                observable.onNext(.ideal(item))
                                observable.onCompleted()
                            } else {
                                // FXIME: empty data, not found
                                observable.onNext(.ideal(nil))
                                observable.onCompleted()
                            }
                            
                        case .string(let idValue):
                            if let item = realm.object(ofType: Self.self, forPrimaryKey: idValue) {
                                observable.onNext(.ideal(item))
                                observable.onCompleted()
                            } else {
                                // FXIME: empty data, not found
                                observable.onNext(.ideal(nil))
                                observable.onCompleted()
                            }
                        }
                    } catch let error {
                        observable.onError(error)
                    }
            },
                onError: {
                    MainScheduler.ensureExecutingOnScheduler()
                    observable.onError($0)
            })
        })
    }
}
