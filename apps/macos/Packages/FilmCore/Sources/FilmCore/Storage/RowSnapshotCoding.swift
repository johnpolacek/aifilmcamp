import Foundation
import GRDB

// The **only** place a `DatabaseValue` becomes a `JSONValue` and back (PHASE1_DESIGN §3.8).
//
// `RowSnapshot` is a public `Codable` payload the app links, so a GRDB type may never
// appear inside it; keeping the conversion here — in `Storage/` — is what makes that
// true by construction.

extension RowSnapshot {
    /// Every column of `row`, as the journal payload stores them.
    init(table: String, row: Row) {
        var columns: [String: JSONValue] = [:]
        for name in row.columnNames {
            columns[name] = JSONValue(databaseValue: row[name] as DatabaseValue)
        }
        self.init(table: table, columns: columns)
    }
}

extension JSONValue {
    /// SQLite's five storage classes. A BLOB encodes base64 into `.string`; no v2 column
    /// is BLOB, and a payload may not carry `Data`.
    init(databaseValue: DatabaseValue) {
        switch databaseValue.storage {
        case .null: self = .null
        case let .int64(value): self = .int(Int(value))
        case let .double(value): self = .double(value)
        case let .string(value): self = .string(value)
        case let .blob(data): self = .string(data.base64EncodedString())
        }
    }

    /// The value to bind back into the column this came from.
    var databaseValue: DatabaseValue {
        switch self {
        case .null: DatabaseValue.null
        case let .bool(value): (value ? 1 : 0).databaseValue
        case let .int(value): value.databaseValue
        case let .double(value): value.databaseValue
        case let .string(value): value.databaseValue
        // No SQLite column holds a composite; a payload that carries one is corrupt, and
        // storing its JSON keeps the row restorable rather than crashing the undo.
        case .array, .object:
            (String(data: (try? JournalCoding.encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "")
                .databaseValue
        }
    }
}

/// Reading rows out of the database as journal payloads, and writing them back.
///
/// An inverse restores rows **by original id** and never stamps "now": `restore` writes
/// every column of the snapshot verbatim, `updated_at`, `reviewed_at`, `review_state`,
/// `source`, and `created_source` included (§3.8).
enum RowSnapshotStore {
    /// The row of `table` with that `id`, or `nil` when it is gone.
    static func capture(table: String, id: UUID, in db: Database) throws -> RowSnapshot? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM \(table) WHERE id = ?",
            arguments: [id.uuidString]
        ) else { return nil }
        return RowSnapshot(table: table, row: row)
    }

    /// Every row of `table` matching `condition`, in primary-key order for a stable payload.
    static func captureAll(
        table: String,
        where condition: String,
        arguments: StatementArguments,
        in db: Database
    ) throws -> [RowSnapshot] {
        let order = primaryKey(of: table).map { "\"\($0)\"" }.joined(separator: ", ")
        return try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM \(table) WHERE \(condition) ORDER BY \(order)",
                arguments: arguments
            )
            .map { RowSnapshot(table: table, row: $0) }
    }

    /// `true` when that row is still there.
    static func exists(table: String, id: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM \(table) WHERE id = ?)",
            arguments: [id.uuidString]
        ) ?? false
    }

    /// Writes the snapshot back, creating the row again when it was deleted.
    ///
    /// Deliberately **not** `INSERT OR REPLACE`: with `PRAGMA foreign_keys = ON` a REPLACE
    /// deletes the conflicting row first and fires its `ON DELETE CASCADE`, so restoring
    /// an entity row that way would take its aliases and appearances with it. An `UPDATE`
    /// of the existing row, or an `INSERT` when there is none, touches nothing else.
    static func restore(_ snapshot: RowSnapshot, in db: Database) throws {
        let names = snapshot.columns.keys.sorted()
        guard !names.isEmpty else { return }
        let key = primaryKey(of: snapshot.table)
        let condition = key.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
        let keyValues = key.map { snapshot.columns[$0]?.databaseValue ?? .null }
        let present = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM \(snapshot.table) WHERE \(condition))",
            arguments: StatementArguments(keyValues)
        ) ?? false

        if present {
            let assignments = names.filter { !key.contains($0) }
            guard !assignments.isEmpty else { return }
            let setClause = assignments.map { "\"\($0)\" = ?" }.joined(separator: ", ")
            let values = assignments.map { snapshot.columns[$0]?.databaseValue ?? .null }
            try db.execute(
                sql: "UPDATE \(snapshot.table) SET \(setClause) WHERE \(condition)",
                arguments: StatementArguments(values + keyValues)
            )
        } else {
            let quoted = names.map { "\"\($0)\"" }.joined(separator: ", ")
            let placeholders = Array(repeating: "?", count: names.count).joined(separator: ", ")
            let values = names.map { snapshot.columns[$0]?.databaseValue ?? .null }
            try db.execute(
                sql: "INSERT INTO \(snapshot.table) (\(quoted)) VALUES (\(placeholders))",
                arguments: StatementArguments(values)
            )
        }
    }

    /// `true` when restoring this snapshot would hit a `UNIQUE` constraint held by a
    /// different row — the check `applyInverse` runs before it writes anything.
    ///
    /// `ignoring` names rows the **same inverse** is about to move or restore, so the slot
    /// they hold now is not a reason to refuse: after a merge collision the survivor sits
    /// where the loser used to, and putting both back is exactly what `unmerge` does.
    static func wouldCollide(
        _ snapshot: RowSnapshot,
        ignoring: Set<String> = [],
        in db: Database
    ) throws -> Bool {
        let key = primaryKey(of: snapshot.table)
        // Only single-column keys can be excluded in SQL; `locks` is the one composite and
        // it carries no `UNIQUE` constraint of its own, so the loop below never runs for it.
        let excluded = key == ["id"] ? ignoring.sorted() : []
        for group in uniqueColumns(of: snapshot.table) {
            let condition = group.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
            let values = group.map { snapshot.columns[$0]?.databaseValue ?? .null }
            var keyCondition = key.map { "\"\($0)\" <> ?" }.joined(separator: " OR ")
            let keyValues = key.map { snapshot.columns[$0]?.databaseValue ?? .null }
            var arguments = StatementArguments(values + keyValues)
            if !excluded.isEmpty {
                let placeholders = excluded.map { _ in "?" }.joined(separator: ", ")
                keyCondition = "(\(keyCondition)) AND \"id\" NOT IN (\(placeholders))"
                arguments += StatementArguments(excluded)
            }
            let collides = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM \(snapshot.table) WHERE \(condition) AND (\(keyCondition))
                    )
                    """,
                arguments: arguments
            ) ?? false
            if collides { return true }
        }
        return false
    }

    /// Deletes the row an inverse must take away again.
    static func delete(table: String, id: UUID, in db: Database) throws {
        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id.uuidString])
    }

    /// The primary key of a snapshot table. Most fact tables are keyed by `id`; locks and
    /// image-generation references use composite keys.
    static func primaryKey(of table: String) -> [String] {
        switch table {
        case "locks": ["subject_kind", "subject_id", "field"]
        case "image_generation_references", "image_generation_amendments":
            ["run_id", "position"]
        default: ["id"]
        }
    }

    /// The `UNIQUE` constraints of §4.3 an inverse could collide with.
    ///
    /// PHASE2_DESIGN §4.3's uniques join Phase 1's. `asset_versions` carries two — the
    /// per-asset version number and the bundle-unique `relative_path`. Its **partial**
    /// unique index `index_asset_versions_approved` (at most one `approved` version per
    /// asset) is deliberately *not* listed and is therefore invisible to `wouldCollide`:
    /// this map models table-level `UNIQUE` constraints, not `WHERE`-qualified indexes,
    /// and §7.3's approve/reject operations own that consequence.
    static func uniqueColumns(of table: String) -> [[String]] {
        switch table {
        case "entities": [["project_id", "kind", "name_normalized"]]
        case "entity_aliases": [["project_id", "kind", "normalized"]]
        case "scene_entities": [["scene_id", "entity_id", "role"]]
        case "entity_relationships": [["from_entity_id", "to_entity_id", "kind"]]
        case "scenes": [["script_id", "ordinal"], ["script_id", "start_utf16"]]
        case "sequences": [["script_id", "ordinal"]]
        case "asset_requirements": [["entity_id", "type_id"], ["entity_id", "name_normalized"]]
        case "asset_requirement_scenes": [["requirement_id", "scene_id"]]
        case "scene_reference_exclusions": [["scene_id", "requirement_id"]]
        case "asset_requirement_basis": [["requirement_id", "subject_kind", "subject_id"]]
        case "asset_dependencies": [["requirement_id", "depends_on_requirement_id"]]
        case "assets": [["requirement_id"]]
        case "asset_versions": [["asset_id", "version_number"], ["relative_path"]]
        // PHASE3_DESIGN §7.4: the pair is what makes `wouldCollide` fire on §7.2's
        // prompt-number walk (delete the newest, regenerate, undo refuses). The
        // citations' `(prompt_id, position)` pair keeps their dense numbering unique.
        case "asset_prompts": [["requirement_id", "prompt_number"]]
        case "asset_prompt_references": [["prompt_id", "position"]]
        case "image_generation_amendments": [["run_id", "amendment_run_id"]]
        // PHASE5_DESIGN §4.3's v6 tables (Plan 019): the scene pair mirrors the asset
        // prompt pair, and the import's UNIQUE root keeps a re-import from colliding.
        case "scene_prompts": [["scene_id", "target_profile", "prompt_number"]]
        case "scene_prompt_references": [["prompt_id", "position"]]
        case "scene_prompt_sets": [["scene_id", "target_profile", "set_number"]]
        case "scene_prompt_cards": [["set_id", "card_order"]]
        case "scene_prompt_card_references": [["card_id", "position"]]
        case "imported_skills": [["relative_root"]]
        case "asset_requirement_types": [["project_id", "entity_kind", "code"]]
        default: []
        }
    }

    /// The table a subject of that kind lives in, or `nil` for the kinds that are not one
    /// row of one table (`script`, and `synopsis`, which is a column set on `scenes`).
    static func table(for kind: SubjectKind) -> String? {
        switch kind {
        case .entity: "entities"
        case .alias: "entity_aliases"
        case .appearance: "scene_entities"
        case .scene: "scenes"
        case .state: "entity_states"
        case .event: "continuity_events"
        case .relationship: "entity_relationships"
        // PHASE2_DESIGN §7.5: every new table is snapshot-restorable, the template
        // included — `removeTemplateEntry`'s inverse restores its row.
        case .requirement: "asset_requirements"
        case .requirementScene: "asset_requirement_scenes"
        case .basis: "asset_requirement_basis"
        case .dependency: "asset_dependencies"
        case .asset: "assets"
        case .version: "asset_versions"
        case .prompt: "asset_prompts"
        case .promptReference: "asset_prompt_references"
        case .templateEntry: "asset_requirement_types"
        case .synopsis, .script: nil
        }
    }
}

extension RowSnapshotStore {
    /// `true` when the row this snapshot came from is still in its table.
    static func isPresent(_ snapshot: RowSnapshot, in db: Database) throws -> Bool {
        let key = primaryKey(of: snapshot.table)
        let condition = key.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
        let values = key.map { snapshot.columns[$0]?.databaseValue ?? .null }
        return try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM \(snapshot.table) WHERE \(condition))",
            arguments: StatementArguments(values)
        ) ?? false
    }

    /// A snapshot's primary key rendered as one string, for stable ordering and de-duplication.
    static func keyDescription(of snapshot: RowSnapshot) -> String {
        primaryKey(of: snapshot.table)
            .map { name -> String in
                guard case let .string(value)? = snapshot.columns[name] else { return "" }
                return value
            }
            .joined(separator: "/")
    }

    /// Every lock row over one subject (§3.7). Lock rows carry no foreign key, so a
    /// deletion that takes their subject away must take them along by hand.
    static func captureLocks(subject: SubjectRef, in db: Database) throws -> [RowSnapshot] {
        try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM locks WHERE subject_kind = ? AND subject_id = ? ORDER BY field",
                arguments: [subject.kind.rawValue, subject.id.uuidString]
            )
            .map { RowSnapshot(table: "locks", row: $0) }
    }

    /// Removes every lock row over one subject.
    static func deleteLocks(subject: SubjectRef, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM locks WHERE subject_kind = ? AND subject_id = ?",
            arguments: [subject.kind.rawValue, subject.id.uuidString]
        )
    }
}

/// Full snapshots of the rows one operation touched, **de-duplicated keeping the first**.
///
/// A merge can meet the same row twice — a relationship it already re-pointed can lose a
/// later collision — and the payload must keep the row as it was *before* the operation
/// started, so the second capture is dropped rather than the first (§3.8).
struct SnapshotCollector {
    private var seen: Set<String> = []
    private(set) var snapshots: [RowSnapshot] = []

    var isEmpty: Bool { snapshots.isEmpty }

    mutating func add(_ snapshot: RowSnapshot) {
        let key = "\(snapshot.table)#\(RowSnapshotStore.keyDescription(of: snapshot))"
        guard seen.insert(key).inserted else { return }
        snapshots.append(snapshot)
    }

    mutating func add(contentsOf snapshots: [RowSnapshot]) {
        for snapshot in snapshots { add(snapshot) }
    }

    mutating func add(table: String, row: Row) {
        add(RowSnapshot(table: table, row: row))
    }

    /// Captures the row by id, when it is there.
    @discardableResult
    mutating func capture(table: String, id: UUID, in db: Database) throws -> Bool {
        guard let snapshot = try RowSnapshotStore.capture(table: table, id: id, in: db) else {
            return false
        }
        add(snapshot)
        return true
    }

    /// Captures every lock row over a subject.
    mutating func captureLocks(subject: SubjectRef, in db: Database) throws {
        add(contentsOf: try RowSnapshotStore.captureLocks(subject: subject, in: db))
    }
}

/// Restoring and deleting **groups** of rows in an order the foreign keys survive (§3.8).
///
/// `RowSnapshotStore` handles one row; a delete, merge, or split hands back a whole
/// sub-graph, and the order it goes back in is what keeps
/// `PRAGMA foreign_key_check` clean.
enum RowGraph {
    /// Parents before the rows that reference them; a table not listed sorts last.
    ///
    /// The v4 tables are **appended** in their own FK dependency order (PHASE2_DESIGN §7.5,
    /// §4.2 step 2): types, requirements, scene links, basis, dependencies, assets,
    /// versions. Every one of them references only tables that appear earlier in this list,
    /// so appending keeps the whole order a valid topological one. `locks` stays last: it
    /// has no foreign keys at all.
    ///
    /// PHASE3_DESIGN §7.4 inserts the prompt tables into that order rather than appending:
    /// `asset_versions` now also references `asset_prompts` (its `prompt_id`, §4.2 step 3),
    /// so a version row cannot restore before its prompt — the order reads `… assets,
    /// asset_prompts, asset_versions, asset_prompt_references …`, both insertions before
    /// `locks`.
    static let tableOrder: [String] = [
        "projects", "project_assets", "scripts", "sequences", "scenes", "scene_exclusions",
        "entities", "entity_aliases", "scene_entities", "entity_states",
        "entity_relationships", "continuity_events", "evidence",
        "asset_requirement_types", "asset_requirements", "asset_requirement_scenes",
        "scene_reference_exclusions",
        "asset_requirement_basis", "asset_dependencies", "assets", "asset_prompts",
        "image_generation_runs", "asset_versions", "asset_prompt_references",
        "image_generation_references", "image_generation_amendments",
        // PHASE5_DESIGN §4.3's v6 tables (Plan 019): `scene_prompts` after the asset
        // tables it joins through its citations, `imported_skills` before nothing —
        // only `projects.scene_skill_id` references it, and `projects` restores first.
        "imported_skills", "scene_prompt_sets", "scene_prompt_cards",
        "scene_prompt_card_references", "scene_prompts", "scene_prompt_references",
        "locks",
    ]

    static func rank(of table: String) -> Int {
        tableOrder.firstIndex(of: table) ?? tableOrder.count
    }

    /// Restores every snapshot: parent tables first, then — within one table — the order
    /// the constraints demand.
    ///
    /// In `entities` an **insert** has to go first, because a child row's `parent_id` may
    /// not land before the parent row exists. Everywhere else the **update** goes first: a
    /// merge collision leaves the survivor holding the loser's `UNIQUE` slot, and the
    /// loser can only be inserted once the survivor has moved back out of it.
    static func restore(_ snapshots: [RowSnapshot], in db: Database) throws {
        var decorated: [(rank: Int, phase: Int, key: String, snapshot: RowSnapshot)] = []
        for snapshot in snapshots {
            let present = try RowSnapshotStore.isPresent(snapshot, in: db)
            let insertsFirst = snapshot.table == "entities"
            decorated.append((
                rank: rank(of: snapshot.table),
                phase: (present == insertsFirst) ? 1 : 0,
                key: RowSnapshotStore.keyDescription(of: snapshot),
                snapshot: snapshot
            ))
        }
        decorated.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.phase != rhs.phase { return lhs.phase < rhs.phase }
            return lhs.key < rhs.key
        }
        for item in decorated { try RowSnapshotStore.restore(item.snapshot, in: db) }
    }

    /// Deletes rows child-first — the mirror of `restore` — and returns the lock rows it
    /// took with them.
    ///
    /// §3.7: lock rows are removed **and snapshotted** when their subject goes away. They
    /// carry no foreign key, so nothing else would take them; and without the snapshot a
    /// lock a person put on a merge-created alias would be destroyed by the undo and lost
    /// to the redo.
    @discardableResult
    static func delete(_ refs: [SubjectRef], in db: Database) throws -> [RowSnapshot] {
        let ordered = refs
            .compactMap { ref -> (rank: Int, ref: SubjectRef, table: String)? in
                guard let table = RowSnapshotStore.table(for: ref.kind) else { return nil }
                return (rank(of: table), ref, table)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.ref.id.uuidString < rhs.ref.id.uuidString
            }
        var removedLocks: [RowSnapshot] = []
        for item in ordered {
            removedLocks += try RowSnapshotStore.captureLocks(subject: item.ref, in: db)
            try RowSnapshotStore.delete(table: item.table, id: item.ref.id, in: db)
            try RowSnapshotStore.deleteLocks(subject: item.ref, in: db)
        }
        return removedLocks
    }

    /// The subjects a snapshot list names, for an inverse's `affected` set.
    static func subjects(of snapshots: [RowSnapshot]) -> Set<SubjectRef> {
        var refs: Set<SubjectRef> = []
        for snapshot in snapshots {
            guard let kind = subjectKind(of: snapshot.table),
                  case let .string(raw)? = snapshot.columns["id"],
                  let id = UUID(uuidString: raw)
            else { continue }
            refs.insert(SubjectRef(kind: kind, id: id))
        }
        return refs
    }

    /// The inverse of `RowSnapshotStore.table(for:)`.
    static func subjectKind(of table: String) -> SubjectKind? {
        switch table {
        case "entities": .entity
        case "entity_aliases": .alias
        case "scene_entities": .appearance
        case "scenes": .scene
        case "entity_states": .state
        case "continuity_events": .event
        case "entity_relationships": .relationship
        // PHASE2_DESIGN §7.5's reverse map for the v4 tables.
        case "asset_requirements": .requirement
        case "asset_requirement_scenes": .requirementScene
        case "asset_requirement_basis": .basis
        case "asset_dependencies": .dependency
        case "assets": .asset
        case "asset_versions": .version
        // PHASE3_DESIGN §7.4's reverse map for the v5 tables.
        case "asset_prompts": .prompt
        case "asset_prompt_references": .promptReference
        case "scene_prompt_sets", "scene_prompt_cards", "scene_prompts": .prompt
        case "scene_prompt_card_references", "scene_prompt_references": .promptReference
        case "asset_requirement_types": .templateEntry
        default: nil
        }
    }
}
