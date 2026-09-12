import Foundation

// MARK: - Osaurus spend tool
//
// Reports how much has been spent on LLM providers across Osaurus sessions.
// Exact USD totals come from the provider APIs (OpenRouter + DeepInfra, keys
// read from the macOS Keychain where Osaurus stores them); per-session stats
// (model, turns, output tokens) come from the local chat database.

private struct SpendTool {
    let name = "spend_report"

    func run(args: String) -> String {
        struct Args: Decodable {
            let time_range: String?
        }
        let input = (try? JSONDecoder().decode(Args.self, from: Data(args.utf8)))
        let (data, summary) = generateSpendReport(timeRangeRaw: input?.time_range)
        return okEnvelope(data, summary: summary)
    }
}

// MARK: - C ABI Surface (v3 documented surface)
//
// This Swift mirror MUST stay byte-compatible with `osr_host_api` in
// `osaurus_plugin.h`. Field order, count, and types are FROZEN — the host
// writes by offset. Two slots (`dispatch_clarify`, `dispatch_add_issue`) are
// RESERVED for ABI compatibility and must remain in their current positions.

private typealias osr_plugin_ctx_t = UnsafeMutableRawPointer

// Config + Storage + Logging
private typealias osr_config_get_fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_config_set_fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
private typealias osr_config_delete_fn = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_db_exec_fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_db_query_fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_log_fn = @convention(c) (Int32, UnsafePointer<CChar>?) -> Void

// Agent Dispatch
private typealias osr_dispatch_fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_task_status_fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_dispatch_cancel_fn = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_dispatch_clarify_fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void

// Inference
private typealias osr_complete_fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_complete_stream_fn = @convention(c) (
    UnsafePointer<CChar>?,
    (@convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void)?,
    UnsafeMutableRawPointer?
) -> UnsafePointer<CChar>?
private typealias osr_embed_fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_list_models_fn = @convention(c) () -> UnsafePointer<CChar>?

// HTTP Client
private typealias osr_http_request_fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?

// File I/O
private typealias osr_file_read_fn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?

// Extended Agent Dispatch
private typealias osr_list_active_tasks_fn = @convention(c) () -> UnsafePointer<CChar>?
private typealias osr_send_draft_fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
private typealias osr_dispatch_interrupt_fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
private typealias osr_dispatch_add_issue_fn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafePointer<CChar>?

// Streaming control (v3)
private typealias osr_complete_cancel_fn = @convention(c) (UnsafePointer<CChar>?) -> Void

private struct osr_host_api {
    var version: UInt32

    // Config + Storage + Logging
    var config_get: osr_config_get_fn?
    var config_set: osr_config_set_fn?
    var config_delete: osr_config_delete_fn?
    var db_exec: osr_db_exec_fn?
    var db_query: osr_db_query_fn?
    var log: osr_log_fn?

    // Agent Dispatch
    var dispatch: osr_dispatch_fn?
    var task_status: osr_task_status_fn?
    var dispatch_cancel: osr_dispatch_cancel_fn?
    var dispatch_clarify: osr_dispatch_clarify_fn?  // RESERVED

    // Inference
    var complete: osr_complete_fn?
    var complete_stream: osr_complete_stream_fn?
    var embed: osr_embed_fn?
    var list_models: osr_list_models_fn?

    // HTTP Client
    var http_request: osr_http_request_fn?

    // File I/O
    var file_read: osr_file_read_fn?

    // Extended Agent Dispatch
    var list_active_tasks: osr_list_active_tasks_fn?
    var send_draft: osr_send_draft_fn?
    var dispatch_interrupt: osr_dispatch_interrupt_fn?
    var dispatch_add_issue: osr_dispatch_add_issue_fn?  // RESERVED

    // Streaming control (v3)
    var complete_cancel: osr_complete_cancel_fn?
}

private typealias osr_free_string_t = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_init_t = @convention(c) () -> osr_plugin_ctx_t?
private typealias osr_destroy_t = @convention(c) (osr_plugin_ctx_t?) -> Void
private typealias osr_get_manifest_t = @convention(c) (osr_plugin_ctx_t?) -> UnsafePointer<CChar>?
private typealias osr_invoke_t = @convention(c) (
    osr_plugin_ctx_t?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
) -> UnsafePointer<CChar>?
private typealias osr_handle_route_t = @convention(c) (osr_plugin_ctx_t?, UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
private typealias osr_on_config_changed_t = @convention(c) (osr_plugin_ctx_t?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
private typealias osr_on_task_event_t = @convention(c) (osr_plugin_ctx_t?, UnsafePointer<CChar>?, Int32, UnsafePointer<CChar>?) -> Void

private struct osr_plugin_api {
    var free_string: osr_free_string_t?
    var `init`: osr_init_t?
    var destroy: osr_destroy_t?
    var get_manifest: osr_get_manifest_t?
    var invoke: osr_invoke_t?
    var version: UInt32 = 2
    var handle_route: osr_handle_route_t?
    var on_config_changed: osr_on_config_changed_t?
    var on_task_event: osr_on_task_event_t?
}

private nonisolated(unsafe) var hostAPI: UnsafePointer<osr_host_api>?

private class PluginContext {
    let tool = SpendTool()
}

private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
    guard let p = strdup(s) else { return nil }
    return UnsafePointer(p)
}

private nonisolated(unsafe) var api: osr_plugin_api = {
    var api = osr_plugin_api()

    api.free_string = { ptr in
        if let p = ptr { free(UnsafeMutableRawPointer(mutating: p)) }
    }

    api.`init` = {
        let ctx = PluginContext()
        return Unmanaged.passRetained(ctx).toOpaque()
    }

    api.destroy = { ctxPtr in
        guard let ctxPtr = ctxPtr else { return }
        Unmanaged<PluginContext>.fromOpaque(ctxPtr).release()
    }

    api.get_manifest = { ctxPtr in
        let manifest = """
        {
          "plugin_id": "com.ggr.osaurus-spend",
          "name": "Spend",
          "version": "0.1.0",
          "description": "Report LLM spend across Osaurus sessions.",
          "license": "MIT",
          "authors": ["Scott"],
          "min_macos": "15.0",
          "min_osaurus": "0.5.0",
          "capabilities": {
            "tools": [
              {
                "id": "spend_report",
                "description": "Report how much you've spent on LLM providers across Osaurus sessions for a chosen time range (this_session, today, 7d, 30d, all). Pulls exact USD totals from OpenRouter (GET /api/v1/key: daily/weekly/monthly/all-time) and DeepInfra (GET /payment/usage: monthly), and reads per-session stats (model, turn count, output tokens) from the local chat database. API keys are read from the macOS Keychain (service ai.osaurus.remote). Exact per-session USD is only available for Osaurus Router sessions (host records input/output tokens + cost); OpenRouter/DeepInfra sessions record only output-token counts locally. 'this_session' resolves to the most recently active session.",
                "parameters": {
                  "type": "object",
                  "properties": {
                    "time_range": {
                      "type": "string",
                      "enum": ["this_session", "today", "7d", "30d", "all"],
                      "default": "today",
                      "description": "Time range for the report."
                    }
                  },
                  "required": []
                },
                "requirements": [],
                "permission_policy": "ask"
              }
            ]
          }
        }
        """
        return makeCString(manifest)
    }

    api.invoke = { ctxPtr, typePtr, idPtr, payloadPtr in
        guard let ctxPtr = ctxPtr,
              let typePtr = typePtr,
              let idPtr = idPtr,
              let payloadPtr = payloadPtr else { return nil }

        let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()
        let type = String(cString: typePtr)
        let id = String(cString: idPtr)
        let payload = String(cString: payloadPtr)

        guard type == "tool" else {
            return makeCString(errEnvelope("UNKNOWN_CAPABILITY", "This plugin only handles 'tool' invocations, got '\(type)'."))
        }
        if id == ctx.tool.name {
            return makeCString(ctx.tool.run(args: payload))
        }
        return makeCString(errEnvelope("UNKNOWN_TOOL", "Unknown tool: '\(id)'."))
    }

    api.version = 2

    api.handle_route = { _, _ in
        return makeCString(#"{"status":404}"#)
    }

    api.on_config_changed = { _, _, _ in }
    api.on_task_event = { _, _, _, _ in }

    return api
}()

@_cdecl("osaurus_plugin_entry_v2")
public func osaurus_plugin_entry_v2(_ host: UnsafeRawPointer?) -> UnsafeRawPointer? {
    if let host {
        hostAPI = host.assumingMemoryBound(to: osr_host_api.self)
    } else {
        hostAPI = nil
    }
    return UnsafeRawPointer(&api)
}

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
    return UnsafeRawPointer(&api)
}
