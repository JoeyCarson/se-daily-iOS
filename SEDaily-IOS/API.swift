//
//  API.swift
//  SEDaily-IOS
//
//  Created by Craig Holliday on 6/27/17.
//  Copyright © 2017 Koala Tea. All rights reserved.
//

import UIKit
import Alamofire
import RealmSwift
import SwiftyJSON
import Fabric
import Crashlytics

extension API {
    enum Headers {
        static let contentType = "Content-Type"
        static let authorization = "Authorization"
        static let x_www_form_urlencoded = "application/x-www-form-urlencoded"
        static let bearer = "Bearer "
    }
    
    enum Endpoints {
        static let posts = "/posts"
        static let recommendations = "/posts/recommendations"
        static let login = "/auth/login"
        static let register = "/auth/register"
        static let upvote = "/upvote"
        static let downvote = "/downvote"
    }
    
    enum Types {
        static let new = "new"
        static let top = "top"
        static let recommended = "recommended"
    }
    
    enum TagIds {
        static let business = "1200"
    }
    
    enum Params {
        static let bearer = "Bearer"
        static let lastUpdatedBefore = "lastUpdatedBefore"
        static let createdAtBefore = "createdAtBefore"
        static let active = "active"
        static let platform = "platform"
        static let deviceToken = "deviceToken"
        static let accessToken = "accessToken"
        static let type = "type"
        static let username = "username"
        static let password = "password"
        static let token = "token"
        static let tags = "tags"
        static let categories = "categories"
        static let search = "search"
    }
}

class API {
    let rootURL: String = "https://software-enginnering-daily-api.herokuapp.com/api";
    
    static let sharedInstance: API = API()
    private init() {}
}

extension API {
    // MARK: Auth
    func login(username: String, password: String, completion: @escaping (_ success: Bool?) -> Void) {
        let urlString = rootURL + Endpoints.login
        
        let _headers : HTTPHeaders = [Headers.contentType:Headers.x_www_form_urlencoded]
        var params = [String: String]()
        params[Params.username] = username
        params[Params.password] = password
        
        typealias model = PodcastModel
        
        Alamofire.request(urlString, method: .post, parameters: params, encoding: URLEncoding.httpBody , headers: _headers).responseJSON { response in
            switch response.result {
            case .success:
                let jsonResponse = response.result.value as! NSDictionary
                
                if let message = jsonResponse["message"] {
                    Helpers.alertWithMessage(title: Helpers.Alerts.error, message: String(describing: message), completionHandler: nil)
                    completion(false)
                    Tracker.logLoginError(string: String(describing: message))
                    return
                }
                
                if let token = jsonResponse["token"] {
                    let user = User()
                    user.email = username
                    user.token = token as? String
                    user.save()
                    
                    NotificationCenter.default.post(name: .loginChanged, object: nil)
                    completion(true)
                }
            case .failure(let error):
                log.error(error)

                Helpers.alertWithMessage(title: Helpers.Alerts.error, message: error.localizedDescription, completionHandler: nil)
                Tracker.logLoginError(error: error)
                completion(false)
            }
        }
    }
    
    func register(username: String, password: String, completion: @escaping (_ success: Bool?) -> Void) {
        let urlString = rootURL + Endpoints.register
        
        let _headers : HTTPHeaders = [Headers.contentType:Headers.x_www_form_urlencoded]
        var params = [String: String]()
        params[Params.username] = username
        params[Params.password] = password
        
        typealias model = PodcastModel
        
        Alamofire.request(urlString, method: .post, parameters: params, encoding: URLEncoding.httpBody , headers: _headers).responseJSON { response in
            switch response.result {
            case .success:
                let jsonResponse = response.result.value as! NSDictionary
                
                if let message = jsonResponse["message"] {
                    log.error(message)
                    
                    Helpers.alertWithMessage(title: Helpers.Alerts.error, message: String(describing: message), completionHandler: nil)
                    Tracker.logRegisterError(string: String(describing: message))
                    completion(false)
                    return
                }
                
                if let token = jsonResponse["token"] {
                    let user = User()
                    user.email = username
                    user.token = token as? String
                    user.save()
                    
                    NotificationCenter.default.post(name: .loginChanged, object: nil)
                    completion(true)
                }
            case .failure(let error):
                log.error(error)
                
                Helpers.alertWithMessage(title: Helpers.Alerts.error, message: error.localizedDescription, completionHandler: nil)
                Tracker.logRegisterError(error: error)
                completion(false)
            }
        }
    }

}

extension API {
    //MARK: Getters
    func getPosts(type: String, createdAtBefore beforeDate: String = "", tags: String = "-1", categoires: String = "", completion: @escaping (_ hasChanges: Bool) -> Void) {
        let urlString = rootURL + Endpoints.posts
        
        var params = [String: String]()
        params[Params.type] = type
        params[Params.createdAtBefore] = beforeDate
        // @TODO: Allow for an array and join the array
        if (tags != "-1") {
            params[Params.tags] = tags
        }
        
        if (categoires != "-1") {
            params[Params.categories] = categoires
        }

        let user = User.getActiveUser()
        guard let userToken = user.token else { return }
        let _headers : HTTPHeaders = [
            Headers.authorization:Headers.bearer + userToken,
        ]
        
        typealias model = PodcastModel

        Alamofire.request(urlString, method: .get, parameters: params, headers: _headers).responseArray { (response: DataResponse<[model]>) in
            
            // Variable to check if this function returns changes
            var hasChanges = false
            
            switch response.result {
            case .success:
                let modelsArray = response.result.value
                guard let array = modelsArray else { return }

                if array.isEmpty {
                    completion(hasChanges)
                }
                for item in array {
                    hasChanges = true
                    
                    let realm = try! Realm()
                    let existingItem = realm.object(ofType: model.self, forPrimaryKey: item.key)
                    
                    if item.key != existingItem?.key {
                        switch type {
                        case API.Types.top:
                            item.isTop = true
                        case API.Types.new:
                            item.isNew = true
                        default:
                            break
                        }
                        item.save()
                    }
                    else {
                        // Just update the existing item
                        let recommended = existingItem!.isRecommended
                        
                        existingItem?.updateFrom(item: item)
                        
                        existingItem?.update(isRecommended: recommended)
                        
                        switch type {
                        case API.Types.top:
                            existingItem?.update(isTop: true)
                        case API.Types.new:
                            existingItem?.update(isNew: true)
                        default:
                            break
                        }
                    }
                }
                completion(hasChanges)
            case .failure(let error):
                log.error(error)
                Tracker.logGeneralError(error: error)
                completion(false)
            }
        }
    }
    
    func getRecommendedPosts(createdAtBefore beforeDate: String = "", completion: @escaping (_ hasChanges: Bool) -> Void) {
        let urlString = rootURL + Endpoints.recommendations
        
        let user = User.getActiveUser()
        guard let userToken = user.token else { return }
        let _headers : HTTPHeaders = [
            Headers.authorization:Headers.bearer + userToken,
        ]

        typealias model = PodcastModel
        
        // Variable to check if this function returns changes
        var hasChanges = false
        
        Alamofire.request(urlString, method: .get, parameters: nil, headers: _headers).responseArray { (response: DataResponse<[model]>) in
            
            switch response.result {
                
            case .success:
                let modelsArray = response.result.value
                guard let array = modelsArray else { return }

                if array.isEmpty {
                    completion(hasChanges)
                }
                
                for item in array {
                    hasChanges = true
                    // Check if Achievement Model already exists
                    let realm = try! Realm()
                    let existingItem = realm.object(ofType: model.self, forPrimaryKey: item.key)
                    
                    if item.key != existingItem?.key {
                        item.isRecommended = true
                        item.save()
                    }
                    else {
                        // Just update the existing item
                        existingItem?.updateFrom(item: item)
                        existingItem?.update(isRecommended: true)
                    }
                }
                completion(hasChanges)
                break
            case .failure(let error):
                log.error(error)
                Tracker.logGeneralError(error: error)
                completion(false)
                break
            }
        }
    }
    
    func getPostsWith(searchTerm: String, createdAtBefore beforeDate: String = "", completion: @escaping (_ posts: [PodcastModel]?) -> Void) {
        let urlString = rootURL + Endpoints.posts
        
        var params = [String: String]()
        params[Params.search] = searchTerm
        params[Params.createdAtBefore] = beforeDate
        
        let user = User.getActiveUser()
        guard let userToken = user.token else { return }
        let _headers : HTTPHeaders = [
            Headers.authorization:Headers.bearer + userToken,
            ]
        
        typealias model = PodcastModel
        
        Alamofire.request(urlString, method: .get, parameters: params, headers: _headers).responseArray { (response: DataResponse<[model]>) in
            switch response.result {
            case .success:
                let modelsArray = response.result.value
                guard let array = modelsArray else {
                    completion(nil)
                    return
                }
                completion(array)
            case .failure(let error):
                log.error(error)
                Tracker.logGeneralError(error: error)
                completion(nil)
            }
        }
    }
}

// MARK: - MVVM Getters
extension API {
    func getPosts(type: String = "",
                  createdAtBefore beforeDate: String = "",
                  tags: String = "-1",
                  categories: String = "",
                  onSucces: @escaping ([Podcast]) -> Void,
                  onFailure: @escaping (APIError?) -> Void) {
        typealias model = Podcast
        
        var urlString = self.rootURL + API.Endpoints.posts
        if type == PodcastTypes.recommended.rawValue {
            urlString = self.rootURL + Endpoints.recommendations
        }
        
        // Params
        var params = [String: String]()
        params[Params.type] = type
        if beforeDate != "" {
            params[Params.createdAtBefore] = beforeDate
        }
        
        // @TODO: Allow for an array and join the array
        if (tags != "") {
            params[Params.tags] = tags
        }
        
        if (categories != "") {
            params[Params.categories] = categories
        }
        
        let user = User.getActiveUser()
        guard let userToken = user.token else { return }
        let _headers : HTTPHeaders = [
            Headers.authorization:Headers.bearer + userToken,
            ]

        Alamofire.request(urlString, method: .get, parameters: params, headers: _headers).responseJSON { response in
            switch response.result {
            case .success:
                guard let responseData = response.data else {
                    // Handle error here
                    print("response has no data")
                    onFailure(.NoResponseDataError)
                    return
                }
                
                var data: [model] = []
                let this = JSON(responseData)
                for (_, subJson):(String, JSON) in this {
                    guard let jsonData = try? subJson.rawData() else { continue }
                    let newObject = try? JSONDecoder().decode(model.self, from: jsonData)
                    if var newObject = newObject {
                        newObject.type = type
                        data.append(newObject)
                    }
                }
                onSucces(data)
            case .failure(let error):
                log.error(error.localizedDescription)
                onFailure(.GeneralFailure)
            }
        }
    }
}

extension API {
    func upvotePodcast(podcastId: String, completion: @escaping (_ success: Bool?, _ active: Bool?) -> Void) {
        let urlString = rootURL + Endpoints.posts + "/" + podcastId + Endpoints.upvote
        
        let user = User.getActiveUser()
        guard let userToken = user.token else { return }
        let _headers : HTTPHeaders = [
            Headers.authorization:Headers.bearer + userToken,
            Headers.contentType:Headers.x_www_form_urlencoded
        ]

        typealias model = PodcastModel
        
        Alamofire.request(urlString, method: .post, parameters: nil, encoding: URLEncoding.httpBody , headers: _headers).responseJSON { response in
            switch response.result {
            case .success:
                let jsonResponse = response.result.value as! NSDictionary

                if let message = jsonResponse["message"] {
                    Helpers.alertWithMessage(title: Helpers.Alerts.error, message: String(describing: message), completionHandler: nil)
                    completion(false, nil)
                    return
                }
                
                if let active = jsonResponse["active"] as? Bool {
                    completion(true, active)
                }
            case .failure(let error):
                log.error(error)
                Tracker.logGeneralError(error: error)
                Helpers.alertWithMessage(title: Helpers.Alerts.error, message: error.localizedDescription, completionHandler: nil)
                completion(false, nil)
            }
        }
    }
    
    func downvotePodcast(podcastId: String, completion: @escaping (_ success: Bool?, _ active: Bool?) -> Void) {
        let urlString = rootURL + Endpoints.posts + "/" + podcastId + Endpoints.downvote
        
        let user = User.getActiveUser()
        guard let userToken = user.token else { return }
        let _headers : HTTPHeaders = [
            Headers.authorization:Headers.bearer + userToken,
            Headers.contentType:Headers.x_www_form_urlencoded
        ]
        
        typealias model = PodcastModel
        
        Alamofire.request(urlString, method: .post, parameters: nil, encoding: URLEncoding.httpBody , headers: _headers).responseJSON { response in
            switch response.result {
            case .success:
                let jsonResponse = response.result.value as! NSDictionary

                if let message = jsonResponse["message"] {
                    Helpers.alertWithMessage(title: Helpers.Alerts.error, message: String(describing: message), completionHandler: nil)
                    completion(false, nil)
                    return
                }
                if let active = jsonResponse["active"] as? Bool {
                    completion(true, active)
                }
            case .failure(let error):
                log.error(error)
                Tracker.logGeneralError(error: error)
                Helpers.alertWithMessage(title: Helpers.Alerts.error, message: error.localizedDescription, completionHandler: nil)
                completion(false, nil)
            }
        }
    }
}

extension API {
    func createDefaultData() {
//        User.createDefault()
    }
    
//    func loadAllObjects() {
//        self.getEvents()
//        self.getPets()
//        self.getShelters()
//    }
//    
//    func loadLoggedInData() {
//        self.getFavorites()
//        self.getFollowingShelters()
//    }
//    
//    func reloadAllObjects() {
//        let realm = try! Realm()
//        try! realm.write {
//            realm.delete(EventModel.all())
//            realm.delete(PetModel.all())
//            realm.delete(ShelterModel.all())
//            realm.delete(UpdatesModel.all())
//        }
//        self.getEvents()
//        self.getPets()
//        self.getShelters()
//    }
}
