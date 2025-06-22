//
//  MongoDBService.swift
//  LlamaProctor
//
//  Created by Kevin Xiao on 6/21/25.
//

import Foundation
import MongoSwiftSync

class MongoDBService: ObservableObject {
    private let mongoURI: String
    private let databaseName = "LlamaProctorDB"
    private let collectionName = "students"
    private var client: MongoClient?
    private var database: MongoDatabase?
    private var collection: MongoCollection<BSONDocument>?
    
    init() {
        // Use the MongoDB Atlas connection string from Config
        self.mongoURI = Config.mongoDBURI
        
        // Debug: Print the URI with credentials masked for security
        let maskedURI = maskCredentials(in: mongoURI)
        print("MongoDB Service initialized with URI: \(maskedURI)")
        
        // Initialize MongoDB connection
        setupMongoDBConnection()
    }
    
    deinit {
        // Clean up MongoDB driver resources
        cleanupMongoSwift()
    }
    
    // MARK: - Helper Methods
    
    private func maskCredentials(in uri: String) -> String {
        // Mask username and password in the URI for security
        let pattern = "mongodb\\+srv://([^:]+):([^@]+)@"
        let maskedURI = uri.replacingOccurrences(of: pattern, with: "mongodb+srv://***:***@", options: .regularExpression)
        return maskedURI
    }
    
    // MARK: - MongoDB Connection Setup
    
    private func setupMongoDBConnection() {
        do {
            // Create MongoDB client
            client = try MongoClient(mongoURI)
            
            // Get database and collection
            database = client?.db(databaseName)
            collection = database?.collection(collectionName, withType: BSONDocument.self)
            
            print("✅ MongoDB connection established successfully")
            print("Database: \(databaseName)")
            print("Collection: \(collectionName)")
            
        } catch {
            print("❌ Failed to connect to MongoDB: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Student Document Management
    
    func upsertStudentDocument(
        id: String = "1",
        focusScore: Int,
        description: String,
        suggestion: String,
        classroom: String = "1",
        active: Bool = true,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard let collection = collection else {
            let error = NSError(domain: "MongoDBService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "MongoDB collection not available"])
            completion(false, error)
            return
        }
        
        let document: BSONDocument = [
            "id": BSON(stringLiteral: id),
            "focus-score": BSON(integerLiteral: focusScore),
            "description": BSON(stringLiteral: description),
            "suggestion": BSON(stringLiteral: suggestion),
            "classroom": BSON(stringLiteral: classroom),
            "active": BSON(booleanLiteral: active),
            "lastUpdated": BSON.datetime(Date())
        ]
        
        print("=== MONGODB OPERATION ===")
        print("Database: \(databaseName)")
        print("Collection: \(collectionName)")
        print("Document: \(document)")
        print("=========================")
        
        // Perform upsert operation on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create filter for upsert
                let filter: BSONDocument = ["id": BSON(stringLiteral: id)]
                
                // Perform upsert operation
                let options = ReplaceOptions(upsert: true)
                let result = try collection.replaceOne(filter: filter, replacement: document, options: options)
                
                DispatchQueue.main.async {
                    print("✅ Document upserted successfully")
                    print("Matched count: \(result?.matchedCount)")
                    print("Modified count: \(result?.modifiedCount)")
                    // Print upserted ID correctly
                    let upsertedIDString: String
                    if let upsertedID = result?.upsertedID, case let .objectID(objectId) = upsertedID {
                        upsertedIDString = objectId.hex
                    } else {
                        upsertedIDString = String(describing: result?.upsertedID ?? "N/A")
                    }
                    print("Upserted ID: \(upsertedIDString)")
                    
                    // Verify the document exists in the database
                    self.verifyDocumentExists(id: id) { exists, error in
                        if let error = error {
                            print("❌ Verification failed: \(error.localizedDescription)")
                            completion(false, error)
                            return
                        }
                        
                        if exists {
                            print("✅ Document successfully upserted and verified in database")
                            completion(true, nil)
                        } else {
                            print("❌ Document was not found in database after upsert")
                            let verificationError = NSError(domain: "MongoDBService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Document verification failed after upsert"])
                            completion(false, verificationError)
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    print("❌ MongoDB upsert failed: \(error.localizedDescription)")
                    completion(false, error)
                }
            }
        }
    }
    
    // MARK: - Document Verification
    
    private func verifyDocumentExists(id: String, completion: @escaping (Bool, Error?) -> Void) {
        guard let collection = collection else {
            let error = NSError(domain: "MongoDBService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "MongoDB collection not available"])
            completion(false, error)
            return
        }
        
        print("=== VERIFYING DOCUMENT ===")
        print("Checking if document with id '\(id)' exists in database")
        
        // Perform database query on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create filter to find document by id
                let filter: BSONDocument = ["id": BSON(stringLiteral: id)]
                
                // Query the database
                let document = try collection.findOne(filter)
                
                DispatchQueue.main.async {
                    if let document = document {
                        print("✅ Document with id '\(id)' found in database")
                        print("Document content: \(document)")
                        completion(true, nil)
                    } else {
                        print("❌ Document with id '\(id)' not found in database")
                        completion(false, nil)
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    print("❌ Verification query failed: \(error.localizedDescription)")
                    completion(false, error)
                }
            }
        }
    }
    
    func updateFocusScore(
        id: String = "1",
        llamaScore: Int,
        description: String,
        suggestion: String,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        // First, get the current document to calculate the new focus score
        getStudentDocument(id: id) { [weak self] currentDocument, error in
            guard let self = self else { return }
            
            if error != nil {
                // If document doesn't exist, create it with initial values
                let newFocusScore = self.calculateNewFocusScore(currentScore: 10, llamaScore: llamaScore)
                self.upsertStudentDocument(
                    id: id,
                    focusScore: newFocusScore,
                    description: description,
                    suggestion: suggestion,
                    completion: completion
                )
                return
            }
            
            // Calculate new focus score based on current score and Llama score
            let currentFocusScore = currentDocument?["focus-score"] as? Int ?? 10
            let newFocusScore = self.calculateNewFocusScore(currentScore: currentFocusScore, llamaScore: llamaScore)
            
            // Update the document
            self.upsertStudentDocument(
                id: id,
                focusScore: newFocusScore,
                description: description,
                suggestion: suggestion,
                completion: completion
            )
        }
    }
    
    private func calculateNewFocusScore(currentScore: Int, llamaScore: Int) -> Int {
        var newScore = currentScore
        
        if llamaScore <= 2 {
            newScore = max(0, currentScore - 1)
        } else if llamaScore >= 4 {
            newScore = min(10, currentScore + 1)
        }
        // If llamaScore is 3, keep the same score
        
        return newScore
    }
    
    func getStudentDocument(id: String = "1", completion: @escaping ([String: Any]?, Error?) -> Void) {
        guard let collection = collection else {
            let error = NSError(domain: "MongoDBService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "MongoDB collection not available"])
            completion(nil, error)
            return
        }
        
        print("=== MONGODB QUERY ===")
        print("Querying document with id: \(id)")
        print("=====================")
        
        // Perform database query on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create filter to find document by id
                let filter: BSONDocument = ["id": BSON(stringLiteral: id)]
                
                // Query the database
                let document = try collection.findOne(filter)
                
                DispatchQueue.main.async {
                    if let document = document {
                        // Convert BSONDocument to [String: Any] for compatibility
                        let documentDict = self.convertBSONDocumentToDictionary(document)
                        print("✅ Document found: \(documentDict)")
                        completion(documentDict, nil)
                    } else {
                        print("❌ Document not found")
                        completion(nil, nil)
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    print("❌ MongoDB query failed: \(error.localizedDescription)")
                    completion(nil, error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertBSONDocumentToDictionary(_ document: BSONDocument) -> [String: Any] {
        var result: [String: Any] = [:]
        
        for (key, value) in document {
            switch value {
            case .string(let string):
                result[key] = string
            case .int32(let int32):
                result[key] = Int(int32)
            case .int64(let int64):
                result[key] = Int(int64)
            case .double(let double):
                result[key] = double
            case .bool(let bool):
                result[key] = bool
            case .datetime(let date):
                result[key] = date.timeIntervalSince1970
            case .objectID(let objectId):
                result[key] = objectId.hex
            default:
                result[key] = String(describing: value)
            }
        }
        
        return result
    }
    
    func setAppActiveStatus(active: Bool, id: String = "1", completion: @escaping (Bool, Error?) -> Void) {
        guard let collection = collection else {
            let error = NSError(domain: "MongoDBService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "MongoDB collection not available"])
            completion(false, error)
            return
        }
        
        print("=== MONGODB UPDATE ===")
        print("Setting active status to: \(active) for id: \(id)")
        print("======================")
        
        // Perform update operation on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create filter to find document by id
                let filter: BSONDocument = ["id": BSON(stringLiteral: id)]
                
                // Create update document
                let update: BSONDocument = [
                    "$set": .document([
                        "active": .bool(active),
                        "lastUpdated": .datetime(Date())
                    ])
                ]
                
                // Perform update operation
                let result = try collection.updateOne(filter: filter, update: update)
                
                DispatchQueue.main.async {
                    print("✅ Active status updated successfully")
                    print("Matched count: \(result?.matchedCount ?? -1)")
                    print("Modified count: \(result?.modifiedCount ?? -1)")
                    // Print upserted ID correctly
                    let upsertedIDString: String
                    if let upsertedID = result?.upsertedID, case let .objectID(objectId) = upsertedID {
                        upsertedIDString = objectId.hex
                    } else {
                        upsertedIDString = String(describing: result?.upsertedID ?? "N/A")
                    }
                    print("Upserted ID: \(upsertedIDString)")
                    completion(true, nil)
                }
                
            } catch {
                DispatchQueue.main.async {
                    print("❌ MongoDB update failed: \(error.localizedDescription)")
                    completion(false, error)
                }
            }
        }
    }
} 
