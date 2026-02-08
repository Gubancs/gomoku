import Foundation
import CloudKit

/// Lightweight presence tracker stored in the public CloudKit database.
/// Each player keeps a single `Presence` record keyed by playerID.
actor PresenceCloudKitStore {
    private enum Field {
        static let playerID = "playerID"
        static let updatedAt = "updatedAt"
    }

    private let database: CKDatabase
    private let recordType = "Presence"

    init(container: CKContainer = .default()) {
        self.database = container.publicCloudDatabase
    }

    func heartbeat(playerID: String) async throws {
        let recordID = CKRecord.ID(recordName: "presence.\(playerID)")

        let record: CKRecord
        if let existing = try await fetchRecord(withID: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
            record[Field.playerID] = playerID as CKRecordValue
        }

        record[Field.updatedAt] = Date() as CKRecordValue
        _ = try await database.save(record)
    }

    func onlineCount(within seconds: TimeInterval) async throws -> Int {
        let cutoff = Date().addingTimeInterval(-seconds)
        let predicate = NSPredicate(format: "%K > %@", Field.updatedAt, cutoff as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Field.updatedAt, ascending: false)]

        var count = 0
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 200
        operation.recordFetchedBlock = { _ in count += 1 }

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

        return count
    }

    func deletePresence(playerID: String) async {
        let recordID = CKRecord.ID(recordName: "presence.\(playerID)")
        do {
            try await database.deleteRecord(withID: recordID)
        } catch {
            // best-effort; ignore errors
        }
    }

    // MARK: - Helpers

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

enum RematchRequestActionResult {
    case pending
    case accepted
}

enum RematchRequestStatus: Equatable {
    case none
    case incoming(requesterID: String)
    case outgoingPending
    case accepted
    case declinedByOpponent
}

/// Stores cross-device rematch handshake state for ended matches.
actor RematchCloudKitStore {
    private enum Field {
        static let matchID = "matchID"
        static let requesterID = "requesterID"
        static let responderID = "responderID"
        static let status = "status"
        static let updatedAt = "updatedAt"
    }

    private enum StatusValue {
        static let pending = "pending"
        static let accepted = "accepted"
        static let declined = "declined"
    }

    private let database: CKDatabase
    private let recordType = "RematchRequest"

    init(container: CKContainer = .default()) {
        self.database = container.publicCloudDatabase
    }

    func requestRematch(matchID: String, localPlayerID: String) async throws -> RematchRequestActionResult {
        guard !matchID.isEmpty, !localPlayerID.isEmpty else { return .pending }
        let recordID = CKRecord.ID(recordName: "rematch.\(matchID)")
        let now = Date()

        let record = try await fetchRecord(withID: recordID) ?? CKRecord(recordType: recordType, recordID: recordID)
        let requesterID = record[Field.requesterID] as? String
        let status = record[Field.status] as? String

        if status == StatusValue.pending, requesterID != nil, requesterID != localPlayerID {
            record[Field.matchID] = matchID as CKRecordValue
            record[Field.status] = StatusValue.accepted as CKRecordValue
            record[Field.responderID] = localPlayerID as CKRecordValue
            record[Field.updatedAt] = now as CKRecordValue
            _ = try await database.save(record)
            return .accepted
        }

        if status == StatusValue.accepted {
            return .accepted
        }

        record[Field.matchID] = matchID as CKRecordValue
        record[Field.requesterID] = localPlayerID as CKRecordValue
        record[Field.responderID] = nil
        record[Field.status] = StatusValue.pending as CKRecordValue
        record[Field.updatedAt] = now as CKRecordValue
        _ = try await database.save(record)
        return .pending
    }

    func acceptRematch(matchID: String, localPlayerID: String) async throws -> Bool {
        guard !matchID.isEmpty, !localPlayerID.isEmpty else { return false }
        let recordID = CKRecord.ID(recordName: "rematch.\(matchID)")
        guard let record = try await fetchRecord(withID: recordID) else { return false }

        let requesterID = record[Field.requesterID] as? String
        let status = record[Field.status] as? String

        if status == StatusValue.accepted {
            return true
        }
        guard status == StatusValue.pending, requesterID != localPlayerID else {
            return false
        }

        record[Field.status] = StatusValue.accepted as CKRecordValue
        record[Field.responderID] = localPlayerID as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        _ = try await database.save(record)
        return true
    }

    func declineRematch(matchID: String, localPlayerID: String) async throws {
        guard !matchID.isEmpty, !localPlayerID.isEmpty else { return }
        let recordID = CKRecord.ID(recordName: "rematch.\(matchID)")
        guard let record = try await fetchRecord(withID: recordID) else { return }

        let requesterID = record[Field.requesterID] as? String
        let status = record[Field.status] as? String
        guard status == StatusValue.pending, requesterID != localPlayerID else {
            return
        }

        record[Field.status] = StatusValue.declined as CKRecordValue
        record[Field.responderID] = localPlayerID as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        _ = try await database.save(record)
    }

    func fetchStatus(matchID: String, localPlayerID: String) async throws -> RematchRequestStatus {
        guard !matchID.isEmpty, !localPlayerID.isEmpty else { return .none }
        let recordID = CKRecord.ID(recordName: "rematch.\(matchID)")
        guard let record = try await fetchRecord(withID: recordID) else {
            return .none
        }

        let requesterID = record[Field.requesterID] as? String ?? ""
        let status = record[Field.status] as? String ?? ""

        switch status {
        case StatusValue.pending:
            if requesterID == localPlayerID {
                return .outgoingPending
            }
            return .incoming(requesterID: requesterID)
        case StatusValue.accepted:
            return .accepted
        case StatusValue.declined:
            if requesterID == localPlayerID {
                return .declinedByOpponent
            }
            return .none
        default:
            return .none
        }
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
