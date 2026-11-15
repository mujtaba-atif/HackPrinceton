// Ported from Probe (github.com/amiezeng/Probe), used with the authors' permission.
// Iris changes: renamed Probe → Iris, Find → Locate.

import CoreGraphics
import Foundation

struct EdgeMeasurement: Equatable {
    let fingertip: CGPoint // index fingertip, normalized 0-1, Vision coords
    let edge: CGPoint    // nearest point on the mask's outer contour, Vision coords
    let distance: Float? // meters, 3D via LiDAR; nil when depth is unavailable
    // Fingertip overlaps the object on screen: distance is then the depth gap to the surface behind it.
    let insideMask: Bool
    // 2D fingertip -> contour distance (normalized), 0 when inside the mask. Used when LiDAR is missing.
    let screenGap: CGFloat
    // Signed depth difference along the camera axis (meters): object minus fingertip, with the same
    // reach correction as `distance`. Positive means the object is still beyond the fingertip, so the
    // hand has to go forward; negative means the hand has overshot past it. `distance` is unsigned and
    // can't tell those apart, which is what forward/back guidance needs. nil without LiDAR depth.
    let depthGap: Float?
    // Iris: why `depthGap` is missing, so guidance can ask for the right fix (or say nothing).
    var depthStatus: ReachDepthStatus = .measured
}

// Debounced "hand reached the object" state from a noisy distance stream. Measured distance never
// reaches 0 at contact (finger thickness, LiDAR noise), so contact is a small threshold held briefly,
// and letting go needs a larger one (hysteresis) so the state doesn't flicker around the threshold.
struct FoundTracker {
    var contactDistance: Float = 0.025  // meters (≈1 in): counts as touching
    var releaseDistance: Float = 0.05   // meters (≈2 in): counts as clearly let go
    var dwell: TimeInterval = 0.3       // contact must last this long to become found
    var release: TimeInterval = 0.5     // separation must last this long to clear found
    var lostTimeout: TimeInterval = 1.5 // no measurement for this long resets
    private(set) var found = false
    private var pendingSince: TimeInterval? // start of the current run toward flipping `found`
    private var lastMeasurement: TimeInterval?

    // distance: meters, nil when there's no measurement; time: seconds (e.g. ARFrame.timestamp).
    mutating func update(distance: Float?, time: TimeInterval) -> Bool {
        guard let distance else {
            // Grasping often hides the object, so a missing measurement holds the state until it times out.
            if let last = lastMeasurement, time - last >= lostTimeout {
                found = false
                pendingSince = nil
                lastMeasurement = nil
            }
            return found
        }
        lastMeasurement = time

        // Not found: time spent touching. Found: time spent clearly apart.
        let flipping = found ? distance >= releaseDistance : distance <= contactDistance
        if !flipping {
            pendingSince = nil
        } else if let since = pendingSince {
            if time - since >= (found ? release : dwell) {
                found.toggle()
                pendingSince = nil
            }
        } else {
            pendingSince = time
        }
        return found
    }
}
