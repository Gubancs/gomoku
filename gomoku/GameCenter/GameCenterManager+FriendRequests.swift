import Foundation
@preconcurrency internal import GameKit

extension GameCenterManager {

    func sendFriendRequest(to playerID: String, displayName: String) {
        guard isAuthenticated, !playerID.isEmpty else { return }
        let localID = GKLocalPlayer.local.gamePlayerID
        guard localID != playerID else { return }
        let localName = GKLocalPlayer.local.displayName
        let store = friendRequestStore

        outgoingFriendRequestPlayerIDs.insert(playerID)

        Task {
            do {
                try await store.sendRequest(senderID: localID, senderName: localName, receiverID: playerID)
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func acceptFriendRequest(_ request: FriendRequest) {
        let store = friendRequestStore
        pendingFriendRequests.removeAll { $0.id == request.id }

        Task {
            do {
                try await store.respondToRequest(senderID: request.senderID, receiverID: request.receiverID, accept: true)
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func rejectFriendRequest(_ request: FriendRequest) {
        let store = friendRequestStore
        pendingFriendRequests.removeAll { $0.id == request.id }

        Task {
            do {
                try await store.respondToRequest(senderID: request.senderID, receiverID: request.receiverID, accept: false)
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func pollFriendRequests() {
        guard isAuthenticated else { return }
        let localID = GKLocalPlayer.local.gamePlayerID
        guard !localID.isEmpty else { return }
        let store = friendRequestStore

        Task {
            do {
                let requests = try await store.fetchIncomingRequests(receiverID: localID)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.pendingFriendRequests = requests
                }
            } catch {
                debugLog("pollFriendRequests error: \(error.localizedDescription)")
            }
        }
    }

    func checkOutgoingFriendRequest(to playerID: String) {
        guard isAuthenticated, !playerID.isEmpty else { return }
        let localID = GKLocalPlayer.local.gamePlayerID
        let store = friendRequestStore

        Task {
            do {
                let hasActive = try await store.hasActiveRequest(senderID: localID, receiverID: playerID)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if hasActive {
                        self.outgoingFriendRequestPlayerIDs.insert(playerID)
                    } else {
                        self.outgoingFriendRequestPlayerIDs.remove(playerID)
                    }
                }
            } catch {
                debugLog("checkOutgoingFriendRequest error: \(error.localizedDescription)")
            }
        }
    }
}
