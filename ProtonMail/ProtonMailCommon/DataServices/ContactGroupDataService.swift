//
//  ContactGroupDataService.swift
//  ProtonMail - Created on 2018/8/20.
//
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of ProtonMail.
//
//  ProtonMail is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonMail is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonMail.  If not, see <https://www.gnu.org/licenses/>.


import Foundation
import CoreData
import Groot
import PromiseKit

let sharedContactGroupsDataService = ContactGroupsDataService()

class ContactGroupsDataService {
    /**
     Create a new contact group on the server and save it in core data
     
     - Parameters:
     - name: The name of the contact group
     - color: The color of the contact group
     */
    func createContactGroup(name: String, color: String) -> Promise<String>
    {
        return Promise {
            seal in
            
            let api = CreateLabelRequest<CreateLabelRequestResponse>(name: name, color: color, exclusive: false, type: 2)
            api.call() {
                task, response, hasError in
                if hasError, let error = response?.error {
                    seal.reject(error)
                } else {
                    if let newContactGroup = response?.label,
                        let ID = newContactGroup["ID"] as? String {
                        // save
                        PMLog.D("[Contact Group addContactGroup API] result = \(newContactGroup)")
                        sharedLabelsDataService.addNewLabel(newContactGroup)
                        seal.fulfill(ID)
                    } else {
                        seal.reject(NSError.unableToParseResponse(response))
                    }
                }
            }
        }
    }
    
    /**
     Edit a contact group on the server and edit it in core data
     
     - Parameters:
     - name: The name of the contact group
     - color: The color of the contact group
     */
    func editContactGroup(groupID: String, name: String, color: String) -> Promise<Void>
    {
        return Promise {
            seal in
            
            let eventAPI = UpdateLabelRequest<UpdateLabelRequestResponse>(id: groupID, name: name, color: color)
            
            eventAPI.call() {
                task, response, hasError in
                if hasError, let error = response?.error {
                    seal.reject(error)
                } else {
                    if let updatedContactGroup = response?.label {
                        PMLog.D("[Contact Group editContactGroup API] result = \(String(describing: updatedContactGroup))")
                        sharedLabelsDataService.addNewLabel(updatedContactGroup)
                        seal.fulfill(())
                    } else {
                        seal.reject(NSError.unableToParseResponse(response))
                    }
                }
            }
        }
    }
    
    /**
     Delete a contact group on the server and delete it in core data
     
     - Parameters:
     - name: The name of the contact group
     */
    func deleteContactGroup(groupID: String) -> Promise<Void>
    {
        return Promise {
            seal in
            
            let eventAPI = DeleteLabelRequest<DeleteLabelRequestResponse>(lable_id: groupID)
            
            eventAPI.call() {
                task, response, hasError in
                
                if hasError, let error = response?.error {
                    seal.reject(error)
                } else {
                    if let returnedCode = response?.returnedCode {
                        PMLog.D("[Contact Group deleteContactGroup API] result = \(String(describing: returnedCode))")
                        
                        // successfully deleted on the server
                        let context = sharedCoreDataService.mainManagedObjectContext
                        context.performAndWait {
                            () -> Void in
                            let label = Label.labelForLableID(groupID, inManagedObjectContext: context)
                            if let label = label {
                                context.delete(label)
                            }
                        }
                        
                        do {
                            try context.save()
                            seal.fulfill(())
                            return
                        } catch {
                            PMLog.D("deleteContactGroup updating error: \(error)")
                            seal.reject(error)
                            return
                        }
                    } else {
                        PMLog.D("[Contact Group deleteContactGroup API] error = \(String(describing: task)) \(String(describing: response)) \(hasError)")
                        seal.reject(NSError.unableToParseResponse(response))
                    }
                }
            }
        }
    }
    
    func addEmailsToContactGroup(groupID: String,
                                 emailList: [Email]) -> Promise<Void>
    {
        return Promise {
            seal in
            
            // check
            if emailList.count == 0 {
                seal.fulfill(())
                return
            }
            
            let emails = emailList.map({
                (email: Email) -> String in
                return email.emailID
            })
            
            let eventAPI = ContactLabelAnArrayOfContactEmailsRequest(labelID: groupID, contactEmailIDs: emails)
            eventAPI.call() {
                task, response, hasError in
                if hasError, let error = response?.error {
                    seal.reject(error)
                } else {
                    if let emailIDs = response?.emailIDs {
                        // save
                        PMLog.D("[Contact Group addEmailsToContactGroup API] result = \(String(describing: response))")
                        
                        let context = sharedCoreDataService.mainManagedObjectContext
                        context.performAndWait {
                            let label = Label.labelForLableID(groupID, inManagedObjectContext: context)
                            
                            if let label = label,
                                var newSet = label.emails as? Set<Email> {
                                // insert those email objects that is in the response only
                                for emailID in emailIDs {
                                    for email in emailList {
                                        if email.emailID == emailID {
                                            newSet.insert(email)
                                            break
                                        }
                                    }
                                }
                                
                                label.emails = newSet as NSSet
                                
                                do {
                                    try context.save()
                                    seal.fulfill(())
                                } catch {
                                    PMLog.D("addEmailsToContactGroup updating error: \(error)")
                                    seal.reject(error)
                                }
                            } else {
                                PMLog.D("addEmailsToContactGroup error: can't get label or newSet")
                                seal.reject(ContactGroupEditError.InternalError)
                            }
                        }
                    } else {
                        seal.reject(NSError.unableToParseResponse(response))
                    }
                }
            }
        }
    }
    
    func removeEmailsFromContactGroup(groupID: String, emailList: [Email]) -> Promise<Void>
    {
        return Promise {
            seal in
            
            if emailList.count == 0 {
                seal.fulfill(())
                return
            }
            
            let emails = emailList.map({
                (email: Email) -> String in
                return email.emailID
            })
            let eventAPI = ContactUnlabelAnArrayOfContactEmailsRequest(labelID: groupID, contactEmailIDs: emails)
            
            eventAPI.call() {
                task, response, hasError in
                
                if hasError, let error = response?.error {
                    seal.reject(error)
                } else {
                    if let emailIDs = response?.emailIDs {
                        // save
                        PMLog.D("[Contact Group removeEmailsFromContactGroup API] result = \(String(describing: response))")
                        
                        let context = sharedCoreDataService.mainManagedObjectContext
                        context.performAndWait {
                            let label = Label.labelForLableID(groupID, inManagedObjectContext: context)
                            
                            // remove only the email objects in the response
                            if let label = label, var newSet = label.emails as? Set<Email> {
                                for emailID in emailIDs {
                                    for email in emailList {
                                        if email.emailID == emailID {
                                            newSet.remove(email)
                                            break
                                        }
                                    }
                                }
                                
                                label.emails = newSet as NSSet
                                
                                do {
                                    try context.save()
                                    seal.fulfill(())
                                } catch {
                                    PMLog.D("addEmailsToContactGroup updating error: \(error)")
                                    seal.reject(error)
                                }
                            } else {
                                PMLog.D("addEmailsToContactGroup error: can't get label or newSet")
                                seal.reject(ContactGroupEditError.InternalError)
                            }
                        }
                    } else {
                        seal.reject(NSError.unableToParseResponse(response))
                    }
                }
            }
        }
    }
    
    func getAllContactGroupVOs() -> [ContactGroupVO] {
        let labels = sharedLabelsDataService.getAllLabels(of: .contactGroup)
        
        var result: [ContactGroupVO] = []
        for label in labels {
            result.append(ContactGroupVO.init(ID: label.labelID,
                                              name: label.name,
                                              groupSize: label.emails.count,
                                              color: label.color))
        }
        
        return result
    }
}
