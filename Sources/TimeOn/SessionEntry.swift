import Foundation

/// One persisted session: the ISO8601 (UTC) start timestamp and the active duration in seconds.
/// Kept free of AppKit so it can be compiled directly into the analytics test binary.
struct SessionEntry: Codable {
    let date: String
    let durationSeconds: Int
}
