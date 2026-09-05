import Foundation
import GRDB

/// `ProjectObserving` over GRDB, kept behind `AsyncStream<ProjectChange>` (§3.9a).
///
/// One `ValueObservation` per area, all scheduled `.async(onQueue:)` on this session's
/// observation queue. GRDB notifies a fresh value after **every** transaction that
/// impacts the observed region (deduplication is opt-in and deliberately not used), so
/// the trivial `COUNT(*)` fetches below act purely as region declarations.
///
/// The element consumers receive is only the **set** of changed areas: they always
/// refetch, so coalescing a transaction's six notifications into one set is exactly the
/// contract. A short debounce on the observation queue does the coalescing — one import
/// otherwise arrives as six separate elements.
///
/// No GRDB type appears in any public signature; this whole type is internal.
final class ProjectObservationHub: @unchecked Sendable {
    /// The areas and the tables whose changes mean that area changed.
    private static let areas: [(change: ProjectChange, tables: [String])] = [
        (.script, ["scripts", "projects"]),
        // `scene_entities` is in **both** areas: the scene detail lists a scene's
        // entities and the entity inspector lists an entity's appearances, so a
        // `setSceneEntity` has to refresh each (Plan 005 §3.11).
        (.scenes, ["scenes", "sequences", "scene_exclusions", "scene_entities"]),
        (.entities, [
            "entities", "entity_aliases", "scene_entities",
            "entity_states", "continuity_events", "entity_relationships", "evidence",
        ]),
        (.jobs, ["jobs"]),
        (.journal, ["edit_journal", "edit_journal_affected"]),
        (.locks, ["locks"]),
        // PHASE2_DESIGN §7.5. The template lives in `.requirements` because the manifest
        // views render it beside the rows it seeds; `assets` and `asset_versions` are the
        // media area, which the inspector refreshes on its own.
        (.requirements, [
            "asset_requirement_types", "asset_requirements", "asset_requirement_scenes",
            "asset_requirement_basis", "asset_dependencies",
        ]),
        (.assets, ["assets", "asset_versions"]),
        // PHASE3_DESIGN §7.4. The prompt tables join the media area — without the
        // table→area entries the workshop never refreshes.
        (.assets, ["asset_prompts", "asset_prompt_references"]),
        // PHASE5_DESIGN §7.5. The scene prompt tables and `imported_skills` join the
        // media area on the exact Phase 3 precedent; no new `ProjectChange` flag is
        // minted. The style bible needs no entry here: `projects` is a `.script` table,
        // so `setStyleBible` arrives through `.script`.
        (.assets, [
            "scene_prompt_sets", "scene_prompt_cards", "scene_prompt_card_references",
            "imported_skills",
        ]),
    ]

    /// How long the hub waits for the rest of one transaction's notifications.
    private static let coalescingWindow: DispatchTimeInterval = .milliseconds(20)

    private let database: ProjectDatabase
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var continuations: [UUID: AsyncStream<ProjectChange>.Continuation] = [:]
    private var cancellables: [AnyDatabaseCancellable] = []
    /// The areas that have already delivered their start-up value; the first notification
    /// of an observation is its initial fetch, not a change.
    private var started: Set<Int> = []
    private var pending: ProjectChange = []
    private var flushScheduled = false
    private var isFinished = false

    init(database: ProjectDatabase) {
        self.database = database
        self.queue = DispatchQueue(label: "FilmCore.ProjectObservation.\(UUID().uuidString)")
    }

    /// A new stream over this session's changes. Observations start with the first stream.
    func makeStream() -> AsyncStream<ProjectChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ProjectChange>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        var shouldStart = false
        lock.lock()
        if isFinished {
            lock.unlock()
            continuation.finish()
            return stream
        }
        continuations[id] = continuation
        shouldStart = cancellables.isEmpty
        lock.unlock()

        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.continuations[id] = nil
            self.lock.unlock()
        }
        if shouldStart { startObserving() }
        return stream
    }

    /// Finishes every stream and stops every observation. `close()` calls this **before**
    /// checkpointing, so no notification can arrive against a closed database.
    func finish() {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        isFinished = true
        let continuations = self.continuations.values
        let cancellables = self.cancellables
        self.continuations = [:]
        self.cancellables = []
        lock.unlock()

        for cancellable in cancellables { cancellable.cancel() }
        for continuation in continuations { continuation.finish() }
    }

    deinit { finish() }

    // MARK: - Wiring

    private func startObserving() {
        var started: [AnyDatabaseCancellable] = []
        for (index, area) in Self.areas.enumerated() {
            let sql = area.tables
                .map { "(SELECT COUNT(*) FROM \($0))" }
                .joined(separator: " + ")
            let observation = ValueObservation.tracking { db in
                try Int.fetchOne(db, sql: "SELECT \(sql)") ?? 0
            }
            let cancellable = observation.start(
                in: database.queue,
                scheduling: .async(onQueue: queue),
                onError: { _ in },
                onChange: { [weak self] _ in self?.record(area: area.change, index: index) }
            )
            started.append(cancellable)
        }
        lock.lock()
        if isFinished {
            lock.unlock()
            for cancellable in started { cancellable.cancel() }
            return
        }
        cancellables.append(contentsOf: started)
        lock.unlock()
    }

    /// Accumulates one area, scheduling the flush that emits the coalesced set.
    private func record(area: ProjectChange, index: Int) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        // The first notification is the observation's initial value, not a change.
        guard started.contains(index) else {
            started.insert(index)
            lock.unlock()
            return
        }
        pending.insert(area)
        let shouldSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()

        guard shouldSchedule else { return }
        queue.asyncAfter(deadline: .now() + Self.coalescingWindow) { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        lock.lock()
        let change = pending
        pending = []
        flushScheduled = false
        let targets = isFinished ? [] : Array(continuations.values)
        lock.unlock()

        guard !change.isEmpty else { return }
        for continuation in targets { continuation.yield(change) }
    }
}
