import Foundation
import SQLite3
import Security

// MARK: - Response envelopes

private func jsonObject(_ obj: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
          let str = String(data: data, encoding: .utf8)
    else { return "{}" }
    return str
}

func okEnvelope(_ data: [String: Any], summary: String) -> String {
    jsonObject(["ok": true, "data": data, "summary": summary])
}

func errEnvelope(_ code: String, _ message: String) -> String {
    jsonObject(["ok": false, "error": ["code": code, "message": message]])
}

// MARK: - API keys (macOS Keychain, same store Osaurus uses)

/// Maps Osaurus provider display name -> provider UUID, read from
/// ~/.osaurus/providers/remote.json. Keys are stored in the Keychain under
/// service "ai.osaurus.remote" with account "<uuid>.apiKey".
private func providerUUIDs() -> [String: String] {
    let url = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
        .appendingPathComponent(".osaurus/providers/remote.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let providers = obj["providers"] as? [[String: Any]]
    else { return [:] }
    var map: [String: String] = [:]
    for p in providers {
        if let name = p["name"] as? String, let id = p["id"] as? String {
            map[name] = id
        }
    }
    return map
}

// Fallbacks in case remote.json moves; these are the current UUIDs.
private let kFallbackOpenRouterUUID = "4C02D654-8275-4AA9-9405-47EE2F9125A2"
private let kFallbackDeepInfraUUID = "A4D9ACDB-44DE-40F7-AFCC-9855ABBE893F"

private func keychainSecret(service: String, account: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

private func apiKey(providerName: String, uuidMap: [String: String], fallback: String) -> String? {
    let uuid = uuidMap[providerName] ?? fallback
    return keychainSecret(service: "ai.osaurus.remote", account: uuid + ".apiKey")
}

// MARK: - Synchronous HTTP

private func fetchJSON(_ url: URL, bearer: String? = nil) -> [String: Any]? {
    var req = URLRequest(url: url)
    req.timeoutInterval = 20
    if let bearer {
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }
    let sem = DispatchSemaphore(value: 0)
    var result: [String: Any]?
    URLSession.shared.dataTask(with: req) { data, _, _ in
        defer { sem.signal() }
        if let data,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result = obj
        }
    }.resume()
    sem.wait()
    return result
}

// MARK: - Local SQLite (read-only)

private final class DBReader {
    private var db: OpaquePointer?
    init?(path: String) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, db != nil
        else { return nil }
        self.db = db
    }
    deinit { if let db { sqlite3_close(db) } }

    func query(_ sql: String) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_NULL: row[name] = NSNull()
                default: row[name] = String(cString: sqlite3_column_text(stmt, i))
                }
            }
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Time ranges

private enum TimeRange: String {
    case thisSession = "this_session"
    case today
    case d7 = "7d"
    case d30 = "30d"
    case all
}

private func monthsInRange(start: Date, end: Date) -> [String] {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy.MM"
    var out: [String] = []
    var cursor = start
    let cal = Calendar.current
    while cursor <= end {
        let m = fmt.string(from: cursor)
        if !out.contains(m) { out.append(m) }
        cursor = cal.date(byAdding: .month, value: 1, to: cursor) ?? cursor.addingTimeInterval(30 * 86400)
    }
    return out
}

/// Maps a provider-qualified model id to a short provider label.
private func providerOf(_ model: String) -> String {
    let first = String(model.split(separator: "/").first ?? "").lowercased()
    let known: Set<String> = [
        "openrouter", "deep-infra", "deepinfra", "opencode-go",
        "ollama", "llama-on-sophrosyne", "opencode", "hosted",
    ]
    if known.contains(first) { return first }
    return model.lowercased().hasPrefix("osaurusai") ? "local" : "other"
}

// MARK: - Report

func generateSpendReport(timeRangeRaw: String?) -> (data: [String: Any], summary: String) {
    let now = Date()
    let cal = Calendar.current
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let historyPath = home + "/.osaurus/chat-history/history.sqlite"
    let ledgerPath = home + "/.osaurus/billing/ledger.sqlite"

    let range = TimeRange(rawValue: timeRangeRaw ?? "") ?? .today
    var start: Date
    var end = now
    var rangeLabel: String
    var sessionFilter: String?

    switch range {
    case .thisSession:
        rangeLabel = "this session (most recently active)"
        if let db = DBReader(path: historyPath),
           let row = db.query("SELECT id, created_at FROM sessions ORDER BY updated_at DESC LIMIT 1").first,
           let created = row["created_at"] as? Double {
            start = Date(timeIntervalSince1970: created)
            sessionFilter = row["id"] as? String
        } else {
            start = now.addingTimeInterval(-3600)
        }
    case .today:
        start = cal.startOfDay(for: now); rangeLabel = "today"
    case .d7:
        start = now.addingTimeInterval(-7 * 86400); rangeLabel = "last 7 days"
    case .d30:
        start = now.addingTimeInterval(-30 * 86400); rangeLabel = "last 30 days"
    case .all:
        start = Date(timeIntervalSince1970: 0); rangeLabel = "all time"
    }

    let startTS = start.timeIntervalSince1970
    let endTS = end.timeIntervalSince1970
    let iso: (Double) -> String = { ts in
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    var caveats: [String] = []
    var providers: [String: Any] = [:]

    // --- Provider exact totals ------------------------------------------
    let uuids = providerUUIDs()
    let orKey = apiKey(providerName: "OpenRouter", uuidMap: uuids, fallback: kFallbackOpenRouterUUID)
    let diKey = apiKey(providerName: "DeepInfra", uuidMap: uuids, fallback: kFallbackDeepInfraUUID)

    // OpenRouter: GET /api/v1/key -> usage_daily / usage_weekly / usage_monthly / usage (USD).
    if let key = orKey,
       let resp = fetchJSON(URL(string: "https://openrouter.ai/api/v1/key")!, bearer: key),
       let d = resp["data"] as? [String: Any] {
        var usd: Double?
        switch range {
        case .today: usd = d["usage_daily"] as? Double
        case .d7: usd = d["usage_weekly"] as? Double
        case .d30: usd = d["usage_monthly"] as? Double
        case .all: usd = d["usage"] as? Double
        case .thisSession: usd = nil  // no per-session granularity on OpenRouter
        }
        providers["openrouter"] = [
            "configured": true,
            "usd": usd as Any,
            "granularity": "day",
            "source": "OpenRouter GET /api/v1/key",
        ]
    } else {
        providers["openrouter"] = ["configured": false, "usd": NSNull(), "note": "key not found"]
    }

    // DeepInfra: GET /payment/usage?from=YYYY.MM&to=YYYY.MM -> monthly totals (cents).
    if let key = diKey {
        let months = monthsInRange(start: start, end: end)
        var totalCents = 0
        var periods: [String] = []
        if let first = months.first, let last = months.last,
           let resp = fetchJSON(URL(string: "https://api.deepinfra.com/payment/usage?from=\(first)&to=\(last)")!, bearer: key),
           let monthsArr = resp["months"] as? [[String: Any]] {
            for m in monthsArr {
                if let cost = m["total_cost"] as? Int, let period = m["period"] as? String {
                    totalCents += cost
                    periods.append(period)
                }
            }
        }
        providers["deepinfra"] = [
            "configured": true,
            "usd": Double(totalCents) / 100.0,
            "granularity": "month",
            "periods": periods,
            "source": "DeepInfra GET /payment/usage",
        ]
        if range == .today || range == .d7 {
            caveats.append(
                "DeepInfra reports monthly totals only; '\(rangeLabel)' shows the overlapping month(s), not a day-level figure."
            )
        }
    } else {
        providers["deepinfra"] = ["configured": false, "usd": NSNull(), "note": "key not found"]
    }

    // --- Local per-session stats ----------------------------------------
    var sessions: [[String: Any]] = []
    var totalOutputTokens: Int64 = 0
    var totalTurns = 0
    var byProvider: [String: [String: Any]] = [:]

    if let db = DBReader(path: historyPath) {
        let sql: String
        if let sid = sessionFilter {
            sql = """
                SELECT s.id, s.title, s.created_at, s.updated_at, s.selected_model, s.turn_count,
                       (SELECT COALESCE(SUM(t.generation_token_count),0) FROM turns t
                        WHERE t.session_id = s.id AND t.generation_token_count IS NOT NULL) AS output_tokens
                FROM sessions s WHERE s.id = '\(sid)'
                """
        } else {
            sql = """
                SELECT s.id, s.title, s.created_at, s.updated_at, s.selected_model, s.turn_count,
                       (SELECT COALESCE(SUM(t.generation_token_count),0) FROM turns t
                        WHERE t.session_id = s.id AND t.generation_token_count IS NOT NULL) AS output_tokens
                FROM sessions s
                WHERE s.created_at >= \(startTS) AND s.created_at <= \(endTS)
                ORDER BY s.updated_at DESC LIMIT 100
                """
        }
        for row in db.query(sql) {
            guard let id = row["id"] as? String else { continue }
            let model = (row["selected_model"] as? String) ?? ""
            let provider = providerOf(model)
            let out = (row["output_tokens"] as? Int64) ?? 0
            let turns = Int((row["turn_count"] as? Int64) ?? 0)
            totalOutputTokens += out
            totalTurns += turns
            var agg = byProvider[provider] ?? ["sessions": 0, "turns": 0, "output_tokens": Int64(0)]
            agg["sessions"] = (agg["sessions"] as? Int ?? 0) + 1
            agg["turns"] = (agg["turns"] as? Int ?? 0) + turns
            agg["output_tokens"] = (agg["output_tokens"] as? Int64 ?? 0) + out
            byProvider[provider] = agg
            sessions.append([
                "id": id,
                "title": row["title"] ?? "",
                "created_at": iso((row["created_at"] as? Double) ?? 0),
                "model": model,
                "provider": provider,
                "turns": turns,
                "output_tokens": out,
                "cost_usd": NSNull(),
            ])
        }
        caveats.append(
            "Per-session token counts come from ~/.osaurus/chat-history/history.sqlite. The host records only output tokens (generation_token_count) for OpenRouter/DeepInfra; input tokens and USD are not stored locally for those providers."
        )
    }

    // --- Router exact billing (empty today; exact when hosted Router is used) ---
    var routerUSD: Double = 0
    var routerSessions = 0
    if let db = DBReader(path: ledgerPath) {
        let rows = db.query(
            "SELECT session_id, SUM(CAST(cost_micro AS REAL)) AS micro, COUNT(*) AS n FROM router_billing WHERE created_at >= \(startTS) AND created_at <= \(endTS) AND session_id IS NOT NULL GROUP BY session_id"
        )
        for r in rows {
            if let micro = r["micro"] as? Double {
                routerUSD += micro / 1e6
                routerSessions += 1
            }
        }
        // attach exact cost to matching session rows
        let costBySession = Dictionary(
            rows.compactMap { r -> (String, Double)? in
                guard let sid = r["session_id"] as? String, let micro = r["micro"] as? Double else { return nil }
                return (sid, micro / 1e6)
            },
            uniquingKeysWith: { a, _ in a }
        )
        for i in sessions.indices {
            if let id = sessions[i]["id"] as? String, let c = costBySession[id] {
                sessions[i]["cost_usd"] = c
            }
        }
    }
    providers["router"] = [
        "usd": routerUSD,
        "sessions": routerSessions,
        "note": "Osaurus Router exact billing ledger (~/.osaurus/billing/ledger.sqlite)",
    ]

    caveats.append(
        "Exact per-session USD is only recorded for sessions run through Osaurus Router. OpenRouter/DeepInfra sessions cannot be broken down to per-session cost from provider APIs (OpenRouter exposes day/week/month totals only; DeepInfra exposes monthly totals only)."
    )

    // --- Assemble ---------------------------------------------------------
    let local: [String: Any] = [
        "sessions": sessions.count,
        "turns": totalTurns,
        "output_tokens": totalOutputTokens,
        "by_provider": byProvider,
    ]
    let data: [String: Any] = [
        "time_range": rangeLabel,
        "generated_at": iso(now.timeIntervalSince1970),
        "period": ["start": iso(startTS), "end": iso(endTS)],
        "providers": providers,
        "local": local,
        "sessions": sessions,
        "caveats": caveats,
    ]

    // summary line
    let fmtUSD: (Double?) -> String = { v in
        guard let v else { return "n/a" }
        return String(format: "$%.4f", v)
    }
    var summary = "Spend (\(rangeLabel)):"
    if let or = (providers["openrouter"] as? [String: Any]), let usd = or["usd"] as? Double {
        summary += " OpenRouter \(fmtUSD(usd));"
    }
    if let di = (providers["deepinfra"] as? [String: Any]), let usd = di["usd"] as? Double {
        summary += " DeepInfra \(fmtUSD(usd)) (monthly);"
    }
    summary += " \(sessions.count) sessions, \(totalTurns) turns, \(totalOutputTokens) output tokens locally"
    return (data, summary)
}
