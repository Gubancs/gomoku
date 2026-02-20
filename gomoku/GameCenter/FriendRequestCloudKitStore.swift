import Foundation
import CloudKit
import CryptoKit

struct FriendRequest: Identifiable, Equatable {
    let id: String
    let senderID: String
    let senderName: String
    let receiverID: String
}

/// Stores cross-device friend request state in the public CloudKit database.
actor FriendRequestCloudKitStore {
    private enum Field {
        static let senderID = "senderID"
        static let senderName = "senderName"
        static let receiverID = "receiverID"
        static let status = "status"
        static let updatedAt = "updatedAt"
    }

    private enum StatusValue {
        static let pending = "pending"
        static let accepted = "accepted"
        static let rejected = "rejected"
    }

    private let database: CKDatabase
    private let recordType = "FriendRequest"

    init(container: CKContainer = .default()) {
        self.database = container.publicCloudDatabase
    }

    func sendRequest(senderID: String, senderName: String, receiverID: String) async throws {
        guard !senderID.isEmpty, !receiverID.isEmpty, senderID != receiverID else { return }
        let recordID = CKRecord.ID(recordName: recordName(senderID: senderID, receiverID: receiverID))
        let existing = try await fetchRecord(withID: recordID)
        if let existing, (existing[Field.status] as? String) == StatusValue.pending {
            return
        }
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID)
        record[Field.senderID] = senderID as CKRecordValue
        record[Field.senderName] = senderName as CKRecordValue
        record[Field.receiverID] = receiverID as CKRecordValue
        record[Field.status] = StatusValue.pending as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        _ = try await database.save(record)
    }

    func fetchIncomingRequests(receiverID: String) async throws -> [FriendRequest] {
        guard !receiverID.isEmpty else { return [] }
        let predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                    Field.receiverID, receiverID,
                                    Field.status, StatusValue.pending)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Field.updatedAt, ascending: false)]

        var requests: [FriendRequest] = []
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 50
        operation.recordFetchedBlock = { record in
            guard let senderID = record[Field.senderID] as? String,
                  let senderName = record[Field.senderName] as? String,
                  let recvrID = record[Field.receiverID] as? String else { return }
            requests.append(FriendRequest(
                id: record.recordID.recordName,
                senderID: senderID,
                senderName: senderName,
                receiverID: recvrID
            ))
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }

        return requests
    }

    func hasActiveRequest(senderID: String, receiverID: String) async throws -> Bool {
        guard !senderID.isEmpty, !receiverID.isEmpty else { return false }
        let recordID = CKRecord.ID(recordName: recordName(senderID: senderID, receiverID: receiverID))
        guard let record = try await fetchRecord(withID: recordID) else { return false }
        let status = record[Field.status] as? String ?? ""
        return status == StatusValue.pending || status == StatusValue.accepted
    }

    func respondToRequest(senderID: String, receiverID: String, accept: Bool) async throws {
        guard !senderID.isEmpty, !receiverID.isEmpty else { return }
        let recordID = CKRecord.ID(recordName: recordName(senderID: senderID, receiverID: receiverID))
        guard let record = try await fetchRecord(withID: recordID) else { return }
        record[Field.status] = (accept ? StatusValue.accepted : StatusValue.rejected) as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        _ = try await database.save(record)
    }

    // MARK: - Helpers

    private func recordName(senderID: String, receiverID: String) -> String {
        let key = senderID + "|" + receiverID
        let hash = SHA256.hash(data: Data(key.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return "friendreq.\(hash)"
    }

    private func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return nil
            }
            throw error
        }
    }
}
