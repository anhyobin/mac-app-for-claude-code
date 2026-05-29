import Foundation

/// Whether a workflow run is still executing or has finished.
///
/// `.running` is detected from `journal.jsonl` (a `started` event with no
/// matching `result`) or a fresh directory mtime — NOT from the
/// `workflows/{id}.json` `status` field, which is only written when the run
/// completes (the file may be absent or stale mid-run).
enum WorkflowRunStatus: Sendable, Equatable {
    case running
    case completed
}
