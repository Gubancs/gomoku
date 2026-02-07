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
