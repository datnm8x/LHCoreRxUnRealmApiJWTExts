//
//  LHCoreRxRealmListViewModel.swift
//  LHCoreRxRealmApiJWTExts iOS
//
//  Created by Dat Ng on 5/30/19.
//  Copyright © 2019 datnm (laohac83x@gmail.com). All rights reserved.
//

import Foundation
import UIKit
import SwiftyJSON
import RealmSwift
import Unrealm
import RxSwift
import RxCocoa

public protocol LHCoreRealmable: Realmable {
    var itemId: Int64 { get set }
}

public struct LHCoreRxRealmListOption {
    public var sortBy: [SortDescriptor] = [SortDescriptor(keyPath: "id")]
    public var filter: String?
    public var startPage: Int64 = 0
    public var pageSize: Int = LHCoreApiDefault.pageSize
    public var pagingType: LHCoreListModel.PagingType = .byPageNumber
    
    public init(sortBy: [SortDescriptor] = [SortDescriptor(keyPath: "id")], filter: String? = nil, startPage: Int64 = 0, pageSize: Int = LHCoreApiDefault.pageSize, pagingType: LHCoreListModel.PagingType = .byPageNumber) {
        self.sortBy = sortBy
        self.filter = filter?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        self.pageSize = pageSize
        self.startPage = startPage
        self.pagingType = pagingType
    }
    
    internal var filterTrimmed: String { return self.filter?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? "" }
    internal var hasFilter: Bool { return filterTrimmed != "" }
}

// MARK: LHCoreRxRealmListViewModel ================================
open class LHCoreRxRealmListViewModel<T: LHCoreRealmable> {
    public typealias TableCellBuilder = (_ item: T, _ tblView: UITableView, _ at: IndexPath) -> UITableViewCell?
    public typealias CollectionCellBuilder = (_ item: T, _ colView: UICollectionView, _ at: IndexPath) -> UICollectionViewCell?
    
    public typealias RxFetchFunction = (_ pagingParam: LHCoreListModel.PagingParam<T>) -> Observable<LHCoreListModel.ResultState<T>>
    public typealias RxSearchFunction = (_ pagingParam: LHCoreListModel.PagingParam<T>, _ keyword: String) -> Observable<LHCoreListModel.ResultState<T>>
    
    public let fetchFunction: RxFetchFunction
    public let searchFunction: RxSearchFunction?
    
    public let dataSource: LHCoreListViewDataSource<T> = LHCoreListViewDataSource<T>()
    internal var listType: LHCoreListModel.ViewType = .table
    internal var option: LHCoreRxRealmListOption = LHCoreRxRealmListOption()
    internal var pagingParam: LHCoreListModel.PagingParam<T> = LHCoreListModel.PagingParam<T>()
    
    public let requestState = BehaviorRelay<LHCoreListModel.RequestState>(value: .none)
    public let didRequestHandler = BehaviorRelay<(LHCoreListModel.RequestType, LHCoreListModel.ResultState<T>)>(value: (.refresh, LHCoreListModel.ResultState<T>.successInitial))
    
    public let disposeBag: DisposeBag = DisposeBag()
    internal var disposeBagFetch: DisposeBag?
    internal let userScrollAction = BehaviorRelay<Bool>(value: false)
    internal var disposeBagBindDataSource: DisposeBag?
    internal var disposeBagAutoLoadMore: DisposeBag?
    internal weak var pListView: UIScrollView?
    internal var isSearchMode: Bool = false
    internal var searchKeyword: String = ""
    
    public var isRequesting: Bool { return disposeBagFetch != nil && requestState.value != .none }
    internal var resultNotificationToken: NotificationToken?
    public let resultsChange = BehaviorRelay<RealmCollectionChange<Unrealm.Results<T>>?>(value: nil)
    internal var realmParams: (sortBy: [SortDescriptor], filter: String?) = (sortBy: [SortDescriptor(keyPath: "id")], filter: nil)
    internal var result: Unrealm.Results<T>
    public var items: Unrealm.Results<T> { return result }
    internal var resultCount: Int { return result.count }
    public let totalcount: BehaviorRelay<Int> = BehaviorRelay<Int>(value: Int.max)
    
    open var layoutType: LHCoreListModel.LayoutType = .one_section {
        didSet {
            if layoutType != oldValue {
                self.reloadLayout()
            }
        }
    }
    
    open var enableAutoLoadmore: Bool = true {
        didSet {
            if enableAutoLoadmore != oldValue {
                self.subcribeForAuToLoadMore()
            }
        }
    }
    
    internal var hasMoreData: Bool {
        switch option.pagingType {
        case .byPageNumber:
            return totalcount.value > resultCount
            
        case .byLastItem:
            return pagingParam.lastItemId != nil
        }
    }
    
    public convenience init(fetchFunc: @escaping RxFetchFunction, option: LHCoreRxRealmListOption = LHCoreRxRealmListOption(),
                            searchFunc: RxSearchFunction? = nil, cellBuilder: @escaping TableCellBuilder)
    {
        self.init(fetchFunc: fetchFunc, option: option, searchFunc: searchFunc, tableCellBuilder: cellBuilder, collectionCellBuilder: nil)
        self.listType = .table
    }
    
    public convenience init(fetchFunc: @escaping RxFetchFunction, option: LHCoreRxRealmListOption = LHCoreRxRealmListOption(),
                            searchFunc: RxSearchFunction? = nil, collectionCellBuilder: @escaping CollectionCellBuilder)
    {
        self.init(fetchFunc: fetchFunc, option: option, searchFunc: searchFunc, tableCellBuilder: nil, collectionCellBuilder: collectionCellBuilder)
        self.listType = .collection
    }
    
    internal init(fetchFunc: @escaping RxFetchFunction, option: LHCoreRxRealmListOption = LHCoreRxRealmListOption(),
                  searchFunc: RxSearchFunction?, tableCellBuilder: TableCellBuilder?, collectionCellBuilder: CollectionCellBuilder?) {
        MainScheduler.ensureExecutingOnScheduler()
        
        self.option = option
        self.fetchFunction = fetchFunc
        self.searchFunction = searchFunc
        
        do {
            let realm = try Realm()
            let rlmResult = option.hasFilter ?
                realm.objects(T.self).sorted(by: option.sortBy) :
                realm.objects(T.self).filter(option.filterTrimmed).sorted(by: option.sortBy)
            
            let countResult = rlmResult.count
            self.totalcount.accept(countResult)
            pagingParam.pageSize = option.pageSize
            pagingParam.nextPage = option.startPage
            pagingParam.lastItem = nil
            pagingParam.lastItemId = 0
            
            self.result = rlmResult
            // resultNotification
            resultNotificationToken = self.result.observe { [weak self] (rlmCollectionChange) in
                self?.resultsChange.accept(rlmCollectionChange)
            }
        } catch let error {
            fatalError(error.localizedDescription)
        }
        
        dataSource.tblCellBuilder = tableCellBuilder
        dataSource.colCellBuilder = collectionCellBuilder
        dataSource.delegate = self
    }
    
    public func bindDataSource(table: UITableView?, refreshControl: UIRefreshControl? = nil) {
        guard let tblView = table, self.listType == .table else { return }
        
        self.pListView = tblView
        tblView.dataSource = self.dataSource
        tblView.reloadData()
        let mDisposeBag = DisposeBag()
        self.disposeBagBindDataSource = mDisposeBag
        
        resultsChange.asDriver().drive(onNext: { [weak self] (realmChange) in
            guard let realmChanged = realmChange else { return }
            switch realmChanged {
            case .initial(_):
                break
                
            case .update(_, let deletions, let insertions, let modifications):
                if deletions.count > 0 || insertions.count > 0 || modifications.count > 0 {
                    self?.doReloadListView()
                }
                break
                
            case .error(_):
                break
            }
        }).disposed(by: mDisposeBag)
        
        refreshControl?.rx.controlEvent(.valueChanged).asObservable().subscribe({ [weak self] _ in
            self?.refreshData()
        }).disposed(by: mDisposeBag)
        
        self.requestState.asObservable().subscribe(onNext: { (requestState) in
            var isRequesting = false
            switch requestState {
            case .requesting(_):
                isRequesting = true
            default: break
            }
            
            UIApplication.shared.isNetworkActivityIndicatorVisible = isRequesting
            
            if isRequesting == false {
                DispatchQueue.main.async(execute: {
                    refreshControl?.endRefreshing()
                })
            }
        }).disposed(by: mDisposeBag)
        
        self.subcribeForAuToLoadMore()
    }
    
    public func unBindDataSource() {
        self.disposeBagBindDataSource = nil
        self.disposeBagAutoLoadMore = nil
    }
    
    public func bindDataSource(collection: UICollectionView?, refreshControl: UIRefreshControl? = nil) {
        guard let clView = collection, self.listType == .collection else { return }
        
        self.pListView = clView
        clView.dataSource = self.dataSource
        clView.reloadData()
        let mDisposeBag = DisposeBag()
        self.disposeBagBindDataSource = mDisposeBag
        
        resultsChange.asDriver().drive(onNext: { [weak self] (realmChange) in
            guard let realmChanged = realmChange else { return }
            switch realmChanged {
            case .initial(_):
                break
                
            case .update(_, let deletions, let insertions, let modifications):
                if deletions.count > 0 || insertions.count > 0 || modifications.count > 0 {
                    self?.doReloadListView()
                }
                break
                
            case .error(_):
                break
            }
        }).disposed(by: mDisposeBag)
        
        refreshControl?.rx.controlEvent(.valueChanged).asObservable().subscribe({ [weak self] _ in
            self?.refreshData()
        }).disposed(by: mDisposeBag)
        
        self.requestState.asObservable().subscribe(onNext: { (requestState) in
            var isRequesting = false
            switch requestState {
            case .requesting(_):
                isRequesting = true
            default: break
            }
            
            UIApplication.shared.isNetworkActivityIndicatorVisible = isRequesting
            
            if isRequesting == false {
                DispatchQueue.main.async(execute: {
                    refreshControl?.endRefreshing()
                })
            }
        }).disposed(by: mDisposeBag)
        
        self.subcribeForAuToLoadMore()
    }
    
    internal func subcribeForAuToLoadMore() {
        self.disposeBagAutoLoadMore = nil
        guard let mListView = self.pListView, enableAutoLoadmore else { return }
        
        let pDisposeBag = DisposeBag()
        self.disposeBagAutoLoadMore = pDisposeBag
        
        mListView.rx.willBeginDragging.asObservable().subscribe(onNext: { [weak self] _ in
            self?.userScrollAction.accept(true)
        }).disposed(by: pDisposeBag)
        
        mListView.rx.didScrollToBottom.asObservable().subscribe(onNext: { [weak self] isScrollToBottom in
            guard let strongSelf = self, isScrollToBottom, strongSelf.isRequesting == false, strongSelf.userScrollAction.value, strongSelf.enableAutoLoadmore else { return }
            
            if strongSelf.hasMoreData {
                strongSelf.userScrollAction.accept(false)
                DispatchQueue.main.async {
                    strongSelf.fetchMoreData()
                }
            }
        }).disposed(by: pDisposeBag)
        
        mListView.rx.didEndDragging.asObservable().subscribe(onNext: { [weak self] decelerating in
            if !decelerating {
                self?.userScrollAction.accept(false)
            }
        }).disposed(by: pDisposeBag)
        
        mListView.rx.didEndDecelerating.asObservable().subscribe(onNext: { [weak self] _ in
            self?.userScrollAction.accept(false)
        }).disposed(by: pDisposeBag)
    }
    
    deinit {
        resultNotificationToken?.invalidate()
    }
}

public extension LHCoreRxRealmListViewModel {
    func item(atIndex: Int?) -> T? {
        guard let mIndex = atIndex else { return nil }
        return mIndex >= result.count ? nil : result[mIndex]
    }
    
    func item(at: IndexPath?) -> T? {
        guard let indexPath = at else { return nil }
        var indexItem = indexPath.row
        if self.listType == .table {
            indexItem = self.layoutType == .one_section ? indexPath.row : indexPath.section
        } else {
            indexItem = self.layoutType == .one_section ? indexPath.item : indexPath.section
        }
        
        return self.item(atIndex: indexItem)
    }
    
    func deleteItem(atIndex: Int?) -> T? {
        if let object = self.item(atIndex: atIndex) {
            Realm.tryWrite({ (realm) in
                realm.delete(object)
            })
            let total_Count = self.totalcount.value - 1
            self.totalcount.accept((total_Count < 0) ? 0 : total_Count)
            return object
        } else {
            return nil
        }
    }
    
    func deleteItemId(_ itemId: Int64) -> T? {
        if let deleteItem = T.findById(itemId) {
            Realm.tryWrite({ (realm) in
                realm.delete(deleteItem)
            })
            let total_Count = self.totalcount.value - 1
            self.totalcount.accept((total_Count < 0) ? 0 : total_Count)
            return deleteItem
        } else {
            return nil
        }
    }
    
    func refreshData() {
        disposeBagFetch = nil
        if !isSearchMode {
            isSearchMode = false
            searchKeyword = ""
        }
        doFetchData(isSearching: isSearchMode, requestType: .refresh)
    }
    
    func fetchMoreData() {
        guard hasMoreData else { return }
        
        doFetchData(isSearching: isSearchMode, requestType: .fetch)
    }
    
    func resetSearch() {
        self.isSearchMode = false
        self.refreshData()
    }
    
    func beginSearch(_ keyword: String) {
        self.searchKeyword = keyword //Save cache for loadmore
        self.isSearchMode = true
        self.refreshData()
    }
}

extension LHCoreRxRealmListViewModel {
    internal func reloadLayout() {
        doReloadListView()
    }
    
    internal func doReloadListView() {
        DispatchQueue.main.async { [weak self] in
            if let tblView = self?.pListView as? UITableView {
                tblView.reloadData()
            } else if let colView = self?.pListView as? UICollectionView {
                colView.reloadData()
            }
        }
    }
    
    internal func doFetchData(isSearching: Bool = false, requestType: LHCoreListModel.RequestType = .fetch) {
        guard disposeBagFetch == nil else {
            self.didRequestHandler.accept((requestType, LHCoreListModel.ResultState<T>.error(NSError(domain: String(describing: self), code: LHCoreErrorCodes.hasRequesting, userInfo: nil))))
            return
        }
        
        if requestType == .fetch, hasMoreData == false {
            self.didRequestHandler.accept((requestType, LHCoreListModel.ResultState<T>.error(NSError(domain: String(describing: self), code: LHCoreErrorCodes.noMoreData, userInfo: nil))))
            return
        }
        
        let pDisposeBag = DisposeBag()
        self.disposeBagFetch = pDisposeBag
        
        // proccess page index
        if requestType == .refresh {
            pagingParam.lastItem = nil
            pagingParam.lastItemId = 0
            pagingParam.nextPage = option.startPage
        }
        
        self.requestState.accept(.requesting(requestType))
        
        self.sendRequestFetchData(isSearching: isSearching, requestType: requestType)
            .subscribeOn(LHCoreRxAPIService.bkgScheduler)
            .map { [unowned self] result -> LHCoreListModel.ResultState<T> in
                if isSearching, self.isSearchMode == false {
                    // user canceled searching already
                    throw NSError(domain: "\(self)", code: LHCoreErrorCodes.userCancel, userInfo: ["message": "User did cancelled"])
                }
                
                switch result {
                case .success(let listResult):
                    Realm.tryWrite({ (realm) in
                        if requestType == .refresh {
                            let newItemIds = listResult.items.map({ (item) -> Int64 in
                                return item.itemId
                            })
                            if let oldObjects = (self.realmParams.filter == nil ? realm.objects(T.self) : realm.objects(T.self).filter(self.realmParams.filter!)).array?.filter({ (item) -> Bool in
                                return newItemIds.contains(item.itemId) == false && item.itemId != LHCoreApiDefault.nonItemId
                            }) {
                                realm.delete(oldObjects)
                            }
                        }
                        realm.add(listResult.items, update: true)
                    })
                    self.totalcount.accept(listResult.totalcount)
                    
                case .error(_):
                    break
                }
                
                return result
            }
            .observeOn(MainScheduler.instance)
            .subscribe(
                onNext: { [unowned self] result in
                    MainScheduler.ensureExecutingOnScheduler()
                    
                    switch result {
                    case .success(let listResult):
                        if requestType == .refresh {
                            self.pagingParam.lastItem = nil
                            self.pagingParam.lastItemId = 0
                            
                        }
                        self.pagingParam.nextPage += 1
                        if self.option.pagingType == .byLastItem {
                            if listResult.items.count < self.option.pageSize {
                                self.pagingParam.lastItem = nil
                                self.pagingParam.lastItemId = LHCoreApiDefault.nonItemId
                            } else {
                                self.pagingParam.lastItem = self.items.last
                                self.pagingParam.lastItemId = self.items.last?.itemId ?? self.option.startPage
                            }
                        }
                        
                    case .error(let error):
                        #if DEBUG
                        print("\(self)->\(isSearching ? "SearchData": "FetchData")->error: ", error)
                        #endif
                    }
                    self.didRequestHandler.accept((requestType, result))
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  [weak self] in
                        self?.requestState.accept(.none)
                        self?.disposeBagFetch = nil
                    }
                },
                onError: { [unowned self] error in
                    MainScheduler.ensureExecutingOnScheduler()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  [weak self] in
                        self?.requestState.accept(.none)
                        self?.disposeBagFetch = nil
                    }
                    
                    self.didRequestHandler.accept((requestType, LHCoreListModel.ResultState<T>.error(error)))
            })
            .disposed(by: pDisposeBag)
    }
    
    internal func sendRequestFetchData(isSearching: Bool = false, requestType: LHCoreListModel.RequestType = .fetch) -> Observable<LHCoreListModel.ResultState<T>> {
        if isSearching {
            guard let apiSearchFunction = self.searchFunction else {
                return Observable.create { observer in
                    observer.on(.error(NSError(domain: String(describing: self), code: LHCoreErrorCodes.noFunction, userInfo: nil)))
                    return Disposables.create()
                }
            }
            return apiSearchFunction(pagingParam, self.searchKeyword)
        } else {
            return fetchFunction(pagingParam)
        }
    }
}

extension LHCoreRxRealmListViewModel: LHCoreListViewDataSourceProtocol {
    internal func numberOfSections() -> Int {
        return self.layoutType == .one_section ? 1 : self.resultCount
    }
    
    internal func numberOfRowsInSection(_ section: Int) -> Int {
        return self.layoutType == .one_section ? self.resultCount : 1
    }
    
    internal func itemForCell(at: IndexPath) -> Any? {
        return self.item(at: at)
    }
}
