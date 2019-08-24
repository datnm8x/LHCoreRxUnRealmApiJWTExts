//
//  UserModel.swift
//  Example
//
//  Created by Dat Ng on 6/7/19.
//  Copyright © 2019 datnm (laohac83x@gmail.com). All rights reserved.
//

import Foundation
import LHCoreRxRealmApiJWTExts
import RealmSwift
import Unrealm
import RxSwift
import SwiftyJSON

class UserModel: LHCoreRealmable {
    var itemId: Int64 = 0
    
    static func == (lhs: UserModel, rhs: UserModel) -> Bool {
        return lhs.id == rhs.id
    }
    
    var id: Int64 = 0
    var email: String?
    var first_name: String?
    var last_name: String?
    var avatar: String?
    
    static func primaryKey() -> String? {
        return "id"
    }
    
    required init() { }
    
    convenience init(json: JSON) {
        self.init()
        
        self.id = json[ApiKeys.id].int64Value
        self.itemId = json[ApiKeys.id].int64Value
        self.email = json[ApiKeys.email].string
        self.first_name = json[ApiKeys.first_name].string
        self.last_name = json[ApiKeys.last_name].string
        self.avatar = json[ApiKeys.links][ApiKeys.avatar][ApiKeys.href].string
    }
}

class UserInfo: NSObject {
    var id: Int64 = 0
    var email: String?
    var first_name: String?
    var last_name: String?
    var avatar: String?
    
    required convenience init(json: JSON) {
        self.init()
        
        self.id = json[ApiKeys.id].int64Value
        self.email = json[ApiKeys.email].string
        self.first_name = json[ApiKeys.first_name].string
        self.last_name = json[ApiKeys.last_name].string
        self.avatar = json[ApiKeys.links][ApiKeys.avatar][ApiKeys.href].string
    }
}
