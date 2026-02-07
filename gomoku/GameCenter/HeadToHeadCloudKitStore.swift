import Foundation
import CloudKit
import CryptoKit

enum HeadToHeadMatchResult {
    case localWin
    case localLoss
    case draw
}

struct HeadToHeadSummary: Equatable {
    let localWins: Int
    let opponentWins: Int
    let draws: Int

    var formattedScore: String {
        if draws > 0 {
            return "\(localWins)-\(opponentWins)-\(draws)"
        }
        return "\(localWins)-\(opponentWins)"
    }
}

enum HeadToHeadCloudKitStoreError: LocalizedError {
    case retryLimitReached
    case saveReturnedNoRecord

    var errorDescription: String? {
        switch self {
        case .retryLimitReached:
            return "Cloud sync conflict did not resolve in time."
        case .saveReturnedNoRecord:
            return "Cloud save did not return a record."
        }
    }
}

actor HeadToHeadCloudKitStore {
    private struct PairDescriptor {
        let recordID: CKRecord.ID
        let pairKey: String
        let playerAID: String
        let playerBID: String
    }

    private enum Field {
        static let pairKey = "pairKey"
        static let playerAID = "playerAID"
        static let playerBID = "playerBID"
        static let playerAWins = "playerAWins"
        static let playerBWins = "playerBWins"
        static let draws = "draws"
        static let processedMatchIDs = "processedMatchIDs"
        static let updatedAt = "updatedAt"
    }

    private let database: CKDatabase
    private let recordType = "HeadToHeadPair"
    private let maxRetryCount = 5

    init(container: CKContainer = .default()) {
        self.database = container.publicCloudDatabase
    }

    func fetchSummary(localPlayerID: String, opponentPlayerID: String) async throws -> HeadToHeadSummary? {
        let pair = pairDescriptor(localPlayerID: localPlayerID, opponentPlayerID: opponentPlayerID)
        guard let record = try await fetchRecord(withID: pair.recordID) else {
            return nil
        }
        return summary(from: record, localPlayerID: localPlayerID, opponentPlayerID: opponentPlayerID)
    }

    func recordResult(
        matchID: String,
        localPlayerID: String,
        opponentPlayerID: String,
        result: HeadToHeadMatchResult
    ) async throws -> HeadToHeadSummary {
        let pair = pairDescriptor(localPlayerID: localPlayerID, opponentPlayerID: opponentPlayerID)

        for _ in 0..<maxRetryCount {
            let currentRecord = try await fetchRecord(withID: pair.recordID) ?? makeInitialRecord(for: pair)
            let localIsPlayerA = localPlayerID == pair.playerAID
            var processedMatchIDs = currentRecord[Field.processedMatchIDs] as? [String] ?? []

            if processedMatchIDs.contains(matchID),
               let existingSummary = summary(from: currentRecord, localPlayerID: localPlayerID, opponentPlayerID: opponentPlayerID) {
                return existingSummary
            }

            processedMatchIDs.append(matchID)
            currentRecord[Field.processedMatchIDs] = processedMatchIDs as NSArray
            apply(result: result, localIsPlayerA: localIsPlayerA, to: currentRecord)
            currentRecord[Field.updatedAt] = Date() as CKRecordValue

            do {
                let saved = try await saveRecordIfUnchanged(currentRecord)
                if let summary = summary(from: saved, localPlayerID: localPlayerID, opponentPlayerID: opponentPlayerID) {
                    return summary
                }
                return HeadToHeadSummary(localWins: 0, opponentWins: 0, draws: 0)
            } catch {
                guard let ckError = Self.cloudKitError(from: error, recordID: pair.recordID),
                      ckError.code == .serverRecordChanged else {
                    throw error
                }

                if let serverRecord = ckError.serverRecord {
                    let serverProcessed = serverRecord[Field.processedMatchIDs] as? [String] ?? []
                    if serverProcessed.contains(matchID),
                       let summary = summary(from: serverRecord, localPlayerID: localPlayerID, opponentPlayerID: opponentPlayerID) {
                        return summary
                    }
                }
            }
        }

        throw HeadToHeadCloudKitStoreError.retryLimitReached
    }

    private func pairDescriptor(localPlayerID: String, opponentPlayerID: String) -> PairDescriptor {
        let orderedIDs = [localPlayerID, opponentPlayerID].sorted()
        let pairKey = orderedIDs.joined(separator: "|")
        let hash = SHA256.hash(data: Data(pairKey.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let recordID = CKRecord.ID(recordName: "h2h.\(hash)")

        return PairDescriptor(
            recordID: recordID,
            pairKey: pairKey,
            playerAID: orderedIDs[0],
            playerBID: orderedIDs[1]
        )
    }

    private func makeInitialRecord(for pair: PairDescriptor) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: pair.recordID)
        record[Field.pairKey] = pair.pairKey as CKRecordValue
        record[Field.playerAID] = pair.playerAID as CKRecordValue
        record[Field.playerBID] = pair.playerBID as CKRecordValue
        record[Field.playerAWins] = Int64(0) as CKRecordValue
        record[Field.playerBWins] = Int64(0) as CKRecordValue
        record[Field.draws] = Int64(0) as CKRecordValue
        record[Field.processedMatchIDs] = [String]() as NSArray
        record[Field.updatedAt] = Date() as CKRecordValue
        return record
    }

    private func summary(from record: CKRecord, localPlayerID: String, opponentPlayerID: String) -> HeadToHeadSummary? {
        guard let playerAID = record[Field.playerAID] as? String,
              let playerBID = record[Field.playerBID] as? String else {
            return nil
        }

        let expectedIDs = Set([localPlayerID, opponentPlayerID])
        let actualIDs = Set([playerAID, playerBID])
        guard expectedIDs == actualIDs else { return nil }

        let playerAWins = numericValue(for: Field.playerAWins, in: record)
        let playerBWins = numericValue(for: Field.playerBWins, in: record)
        let draws = numericValue(for: Field.draws, in: record)

        if localPlayerID == playerAID {
            return HeadToHeadSummary(localWins: playerAWins, opponentWins: playerBWins, draws: draws)
        }
        return HeadToHeadSummary(localWins: playerBWins, opponentWins: playerAWins, draws: draws)
    }

    private func apply(result: HeadToHeadMatchResult, localIsPlayerA: Bool, to record: CKRecord) {
        var playerAWins = numericValue(for: Field.playerAWins, in: record)
        var playerBWins = numericValue(for: Field.playerBWins, in: record)
        var draws = numericValue(for: Field.draws, in: record)

        switch result {
        case .localWin:
            if localIsPlayerA {
                playerAWins += 1
            } else {
                playerBWins += 1
            }
        case .localLoss:
            if localIsPlayerA {
                playerBWins += 1
            } else {
                playerAWins += 1
            }
        case .draw:
            draws += 1
        }

        record[Field.playerAWins] = Int64(playerAWins) as CKRecordValue
        record[Field.playerBWins] = Int64(playerBWins) as CKRecordValue
        record[Field.draws] = Int64(draws) as CKRecordValue
    }

    private func numericValue(for key: String, in record: CKRecord) -> Int {
        if let value = record[key] as? Int64 {
            return Int(value)
        }
        if let value = record[key] as? NSNumber {
            return value.intValue
        }
        return 0
    }

    private func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            var fetchedRecord: CKRecord?
            var perRecordError: Error?

            let operation = CKFetchRecordsOperation(recordIDs: [recordID])
            operation.perRecordCompletionBlock = { record, _, error in
                if let error {
                    perRecordError = error
                    return
                }
                fetchedRecord = record
            }
            operation.fetchRecordsCompletionBlock = { _, operationError in
                if let operationError,
                   let ckError = Self.cloudKitError(from: operationError, recordID: recordID),
                   ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }
                if let operationError {
                    continuation.resume(throwing: operationError)
                    return
                }
                if let ckError = perRecordError as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }
                if let perRecordError {
                    continuation.resume(throwing: perRecordError)
                    return
                }
                continuation.resume(returning: fetchedRecord)
            }

            database.add(operation)
        }
    }

    private func saveRecordIfUnchanged(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            var perRecordError: Error?
            var savedRecord: CKRecord?

            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .ifServerRecordUnchanged
            operation.isAtomic = true
            operation.perRecordCompletionBlock = { record, error in
                if let error {
                    perRecordError = error
                    return
                }
                savedRecord = record
            }
            operation.modifyRecordsCompletionBlock = { _, _, operationError in
                if let operationError {
                    continuation.resume(throwing: operationError)
                    return
                }
                if let perRecordError {
                    continuation.resume(throwing: perRecordError)
                    return
                }
                guard let savedRecord else {
                    continuation.resume(throwing: HeadToHeadCloudKitStoreError.saveReturnedNoRecord)
                    return
                }
                continuation.resume(returning: savedRecord)
            }

            database.add(operation)
        }
    }

    private static func cloudKitError(from error: Error, recordID: CKRecord.ID) -> CKError? {
        guard let ckError = error as? CKError else { return nil }

        if ckError.code == .partialFailure,
           let partialError = ckError.partialErrorsByItemID?[recordID] as? CKError {
            return partialError
        }

        return ckError
    }
}
