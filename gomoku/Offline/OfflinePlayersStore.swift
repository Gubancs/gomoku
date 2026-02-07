import Foundation
import CloudKit
import Combine

struct OfflinePlayer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var points: Int
    var wins: Int
    var losses: Int
    var draws: Int
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, points: Int = 0, wins: Int = 0, losses: Int = 0, draws: Int = 0, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.points = points
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.updatedAt = updatedAt
    }
}

struct OfflinePlayersSnapshot: Codable, Sendable {
    var players: [OfflinePlayer]
    var lastBlackPlayerID: UUID?
    var lastWhitePlayerID: UUID?
    var updatedAt: Date
}

actor OfflinePlayersCloudStore {
    private enum Field {
        static let payload = "payload"
        static let updatedAt = "updatedAt"
    }

    private let database: CKDatabase
    private let recordType = "OfflinePlayersState"
    private let recordID = CKRecord.ID(recordName: "default")

    init(container: CKContainer = .default()) {
        database = container.privateCloudDatabase
    }

    func fetchSnapshot() async throws -> OfflinePlayersSnapshot? {
        guard let record = try await fetchRecord(withID: recordID) else {
            return nil
        }
        guard let payload = record[Field.payload] as? Data else {
            return nil
        }
        return try JSONDecoder().decode(OfflinePlayersSnapshot.self, from: payload)
    }

    func saveSnapshot(_ snapshot: OfflinePlayersSnapshot) async throws {
        let payload = try JSONEncoder().encode(snapshot)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[Field.payload] = payload as NSData
        record[Field.updatedAt] = snapshot.updatedAt as NSDate
        try await saveRecord(record)
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

    private func saveRecord(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var perRecordError: Error?

            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            operation.isAtomic = true
            operation.perRecordCompletionBlock = { _, error in
                if let error {
                    perRecordError = error
                }
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
                continuation.resume(returning: ())
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

@MainActor
final class OfflinePlayersStore: ObservableObject {
    @Published private(set) var players: [OfflinePlayer] = []
    @Published private(set) var lastBlackPlayerID: UUID?
    @Published private(set) var lastWhitePlayerID: UUID?

    private let defaultsKey = "gomoku.offlinePlayers.snapshot.v1"
    private let cloudStore = OfflinePlayersCloudStore()
    private var snapshotUpdatedAt: Date = .distantPast

    init() {
        loadLocal()
        Task { [weak self] in
            await self?.refreshFromCloud()
        }
    }

    var sortedPlayers: [OfflinePlayer] {
        players.sorted { lhs, rhs in
            if lhs.points != rhs.points {
                return lhs.points > rhs.points
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var hasEnoughPlayersForMatch: Bool {
        players.count >= 2
    }

    func player(for id: UUID?) -> OfflinePlayer? {
        guard let id else { return nil }
        return players.first(where: { $0.id == id })
    }

    func playerID(for color: Player) -> UUID? {
        switch color {
        case .black:
            return lastBlackPlayerID
        case .white:
            return lastWhitePlayerID
        }
    }

    func displayName(for color: Player) -> String {
        let fallback = color == .black ? "Black" : "White"
        guard let player = player(for: playerID(for: color)) else {
            return fallback
        }
        return player.name
    }

    func points(for color: Player) -> Int? {
        player(for: playerID(for: color))?.points
    }

    @discardableResult
    func addPlayer(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard players.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) == false else {
            return false
        }

        players.append(OfflinePlayer(name: name))
        ensureValidSelection()
        persistAndSync()
        return true
    }

    @discardableResult
    func deletePlayer(id: UUID) -> Bool {
        guard let index = players.firstIndex(where: { $0.id == id }) else {
            return false
        }

        players.remove(at: index)
        ensureValidSelection()
        persistAndSync()
        return true
    }

    func selectPlayers(blackID: UUID, whiteID: UUID) {
        guard blackID != whiteID else { return }
        guard player(for: blackID) != nil, player(for: whiteID) != nil else { return }
        lastBlackPlayerID = blackID
        lastWhitePlayerID = whiteID
        persistAndSync()
    }

    func suggestedSelection() -> (blackID: UUID, whiteID: UUID)? {
        guard players.count >= 2 else { return nil }

        if let blackID = lastBlackPlayerID,
           let whiteID = lastWhitePlayerID,
           blackID != whiteID,
           player(for: blackID) != nil,
           player(for: whiteID) != nil {
            return (blackID, whiteID)
        }

        let sorted = sortedPlayers
        guard sorted.count >= 2 else { return nil }
        return (sorted[0].id, sorted[1].id)
    }

    func recordMatchResult(winner: Player?, isDraw: Bool, blackPlayerID: UUID, whitePlayerID: UUID) {
        guard blackPlayerID != whitePlayerID else { return }
        guard let blackIndex = players.firstIndex(where: { $0.id == blackPlayerID }),
              let whiteIndex = players.firstIndex(where: { $0.id == whitePlayerID }) else {
            return
        }

        let now = Date()
        if isDraw || winner == nil {
            players[blackIndex].draws += 1
            players[whiteIndex].draws += 1
            players[blackIndex].points += 1
            players[whiteIndex].points += 1
        } else if winner == .black {
            players[blackIndex].wins += 1
            players[whiteIndex].losses += 1
            players[blackIndex].points += 3
        } else {
            players[whiteIndex].wins += 1
            players[blackIndex].losses += 1
            players[whiteIndex].points += 3
        }

        players[blackIndex].updatedAt = now
        players[whiteIndex].updatedAt = now
        lastBlackPlayerID = blackPlayerID
        lastWhitePlayerID = whitePlayerID
        persistAndSync()
    }

    func refreshFromCloud() async {
        do {
            guard let remote = try await cloudStore.fetchSnapshot() else { return }
            guard remote.updatedAt > snapshotUpdatedAt else { return }
            applySnapshot(remote, persist: true, syncToCloud: false)
        } catch {
            // Best-effort CloudKit sync; local storage remains authoritative when offline.
        }
    }

    private func ensureValidSelection() {
        if let blackID = lastBlackPlayerID,
           let whiteID = lastWhitePlayerID,
           blackID != whiteID,
           player(for: blackID) != nil,
           player(for: whiteID) != nil {
            return
        }

        guard let selection = suggestedSelection() else {
            lastBlackPlayerID = nil
            lastWhitePlayerID = nil
            return
        }

        lastBlackPlayerID = selection.blackID
        lastWhitePlayerID = selection.whiteID
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        guard let snapshot = try? JSONDecoder().decode(OfflinePlayersSnapshot.self, from: data) else { return }
        applySnapshot(snapshot, persist: false, syncToCloud: false)
    }

    private func makeSnapshot(updatedAt: Date) -> OfflinePlayersSnapshot {
        OfflinePlayersSnapshot(
            players: players,
            lastBlackPlayerID: lastBlackPlayerID,
            lastWhitePlayerID: lastWhitePlayerID,
            updatedAt: updatedAt
        )
    }

    private func applySnapshot(_ snapshot: OfflinePlayersSnapshot, persist: Bool, syncToCloud: Bool) {
        players = snapshot.players
        lastBlackPlayerID = snapshot.lastBlackPlayerID
        lastWhitePlayerID = snapshot.lastWhitePlayerID
        snapshotUpdatedAt = snapshot.updatedAt
        ensureValidSelection()

        if persist, let data = try? JSONEncoder().encode(makeSnapshot(updatedAt: snapshotUpdatedAt)) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }

        if syncToCloud {
            let cloudSnapshot = makeSnapshot(updatedAt: snapshotUpdatedAt)
            Task {
                try? await cloudStore.saveSnapshot(cloudSnapshot)
            }
        }
    }

    private func persistAndSync() {
        let timestamp = Date()
        snapshotUpdatedAt = timestamp
        let snapshot = makeSnapshot(updatedAt: timestamp)

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }

        Task {
            try? await cloudStore.saveSnapshot(snapshot)
        }
    }
}
