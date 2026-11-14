import Foundation
import CoreGraphics

/// Pure state reducer. One-to-one, same-class IoU association is deliberately conservative.
struct ObjectDetectionState {
    static let retentionInterval: TimeInterval = 0.8
    private struct Track {
        let object: DetectedObject
        let lastSeen: TimeInterval
    }
    private var tracks: [Track] = []
    private(set) var snapshot = DetectionSnapshot()

    mutating func update(_ candidates: [ObjectCandidate], timestamp: TimeInterval, imageSize: CGSize) {
        guard snapshot.timestamp.map({ timestamp > $0 }) ?? true else { return }
        tracks.removeAll { timestamp - $0.lastSeen > Self.retentionInterval }
        var available = tracks
        var current: [Track] = []
        for candidate in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            guard candidate.confidence.isFinite, (0.35...1).contains(candidate.confidence),
                  !candidate.name.isEmpty,
                  let box = DetectionGeometry.clippedUnitRect(candidate.boundingBox) else { continue }
            let match = available.indices.filter { available[$0].object.name == candidate.name }
                .max { DetectionGeometry.intersectionOverUnion(available[$0].object.boundingBox, box)
                    < DetectionGeometry.intersectionOverUnion(available[$1].object.boundingBox, box) }
            let id: UUID
            if let match, DetectionGeometry.intersectionOverUnion(available[match].object.boundingBox, box) >= 0.3 {
                id = available.remove(at: match).object.id
            } else {
                id = UUID()
            }
            current.append(Track(object: .init(id: id, name: candidate.name,
                                              confidence: candidate.confidence, boundingBox: box),
                                 lastSeen: timestamp))
            if current.count == 20 { break }
        }
        // Preserve list order across confidence fluctuations to reduce VoiceOver focus movement.
        let oldIDs = tracks.map { $0.object.id }
        current.sort { (oldIDs.firstIndex(of: $0.object.id) ?? Int.max)
            < (oldIDs.firstIndex(of: $1.object.id) ?? Int.max) }
        tracks = current + available
        snapshot.objects = current.map(\.object)
        snapshot.timestamp = timestamp
        snapshot.uprightImageSize = imageSize
        if let selected = snapshot.selectedTarget {
            if let match = current.first(where: { $0.object.id == selected.object.id }) {
                snapshot.selectedTarget = .init(object: match.object, state: .tracking,
                                                lastSeenTimestamp: timestamp, uprightImageSize: imageSize)
            } else {
                markTargetLost()
            }
        }
    }

    mutating func select(_ id: UUID) {
        guard let object = snapshot.objects.first(where: { $0.id == id }),
              let timestamp = snapshot.timestamp else { return }
        snapshot.selectedTarget = .init(object: object, state: .tracking,
                                        lastSeenTimestamp: timestamp,
                                        uprightImageSize: snapshot.uprightImageSize)
    }

    mutating func clearSelection() { snapshot.selectedTarget = nil }

    /// Also called by a watchdog so a stalled frame stream cannot leave a usable stale target.
    mutating func expire(at timestamp: TimeInterval) {
        tracks.removeAll { timestamp - $0.lastSeen > Self.retentionInterval }
        guard let last = snapshot.timestamp, timestamp - last > Self.retentionInterval else { return }
        snapshot.objects = []
        markTargetLost()
    }

    mutating func suspend() {
        tracks = []
        snapshot.objects = []
        snapshot.timestamp = nil
        markTargetLost()
    }

    private mutating func markTargetLost() {
        guard let selected = snapshot.selectedTarget else { return }
        snapshot.selectedTarget = .init(object: selected.object, state: .lost,
                                        lastSeenTimestamp: selected.lastSeenTimestamp,
                                        uprightImageSize: selected.uprightImageSize)
    }
}
