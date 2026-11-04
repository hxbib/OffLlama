import Foundation
import PocketCore
import llama   // llama.xcframework (module "llama") built from llama.cpp

/// On-device System 1 + local System 2 runtime. One context, serialized by the actor.
/// Decisions reuse the KV cache for the shared prompt prefix, so each decision only prefills the new tail
/// and reads logits for the option letters from a single forward pass.
actor LlamaCppEngine: LLMEngine {
    nonisolated let modelName: String
    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer
    private let nBatch: Int32 = 512
    private var cached: [llama_token] = []
    private var letterTokens: [String: [llama_token]] = [:]   // " A" and "A" variants
    private let nCtx: Int
    /// KV prefix reuse across decision types: each Reflex prompt prefix (system + that type's exemplars, i.e. everything
    /// before the last user turn of DecisionPrompt.llama3) stays resident in its own sequence 1..<nSeq; a decision copies
    /// it into seq 0 (metadata-only with kv_unified) and evaluates only the suffix. Off => exactly the old single-sequence path.
    nonisolated let prefixReuse: Bool
    static let nSeq: Int32 = 8                                   // seq 0 = live, 1..7 = cached prefixes
    private var prefixes: [[llama_token]: (seq: Int32, used: UInt64)] = [:]
    private var useClock: UInt64 = 0
    private var prefixBudget: Int { nCtx / 2 }                  // max cached prefix tokens (rest is for the live sequence)
    private var prefixHits = 0, prefixMisses = 0
    static let userTurn = "<|start_header_id|>user<|end_header_id|>"
    /// Same k as LlamaServerEngine.topK / training `n_probs` (top-40 letter readout).
    static let topK = 40

    /// k-th largest value of `p[0..<count]` (one pass, k-slot insertion buffer; k = 40 over a 128k vocab is ~0.1 ms).
    static func kthLargest(_ p: UnsafeMutablePointer<Float>, count: Int, k: Int) -> Float {
        guard count > 0, k > 0 else { return -.infinity }
        var top = [Float](); top.reserveCapacity(k + 1)       // ascending; top[0] = current k-th largest
        for i in 0..<count {
            let x = p[i]
            if top.count == k { if x <= top[0] { continue }; top.removeFirst() }
            var j = top.count
            while j > 0 && top[j - 1] > x { j -= 1 }
            top.insert(x, at: j)
        }
        return top.count < k ? -.infinity : top[0]
    }

    enum EngineError: Error { case load(String), context, tokenize, decode(Int32) }

    init(modelURL: URL, contextLength: UInt32 = 4096, prefixReuse: Bool = LlamaCppEngine.prefixReuseDefault) throws {
        llama_backend_init()
        var mp = llama_model_default_params()
        mp.n_gpu_layers = 99                  // all layers on Metal
        guard let m = llama_model_load_from_file(modelURL.path, mp) else { throw EngineError.load(modelURL.lastPathComponent) }
        var cp = llama_context_default_params()
        cp.n_ctx = contextLength
        cp.n_batch = 512
        cp.n_ubatch = 512
        let cores = Int32(max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        cp.n_threads = cores; cp.n_threads_batch = cores
        if prefixReuse { cp.n_seq_max = UInt32(Self.nSeq); cp.kv_unified = true }   // one shared KV buffer, every seq may use all of n_ctx
        self.prefixReuse = prefixReuse
        guard let c = llama_init_from_model(m, cp) else { llama_model_free(m); throw EngineError.context }
        model = m; ctx = c; vocab = llama_model_get_vocab(m); nCtx = Int(contextLength)
        modelName = modelURL.deletingPathExtension().lastPathComponent
    }

    deinit { llama_free(ctx); llama_model_free(model) }

    /// Default OFF for the submission build: prefix reuse is ~15% faster on cal180 (73.6 s vs 87.0 s on a Linux box) but
    /// shifts a few confidences near τ (median 0.007, worst 0.135, 6 crossings on cal180), so on-screen numbers would
    /// not match the certified cal180 operating point. Settings toggle "Reuse cached prompt prefix" turns it on.
    static var prefixReuseDefault: Bool { UserDefaults.standard.object(forKey: "pg_kv_prefix") as? Bool ?? false }

    /// `addBOS` = llama.cpp `add_special`. Decision prompts already start with "<|begin_of_text|>", and llama-server
    /// (`/completion` with a string prompt) tokenizes with add_special=true, so every certified number (cal180, τ=0.90,
    /// priors from `pg-cli priors`, the Swift e2e) was measured on <BOS><BOS>... prompts. Decisions therefore pass
    /// addBOS=true to reproduce that exact token stream: on cal180 the single-BOS stream flips 18/180 argmaxes and moves
    /// 36/180 confidences across τ=0.90 (docs/CODE_REVIEW_NOV4.md). Free-text generation keeps a single BOS.
    private func tokenize(_ text: String, special: Bool = true, addBOS: Bool = false) throws -> [llama_token] {
        let utf8 = Array(text.utf8CString)
        var cap = Int32(utf8.count + 16)
        var out = [llama_token](repeating: 0, count: Int(cap))
        var n = llama_tokenize(vocab, text, Int32(utf8.count - 1), &out, cap, addBOS, special)
        if n < 0 { cap = -n; out = .init(repeating: 0, count: Int(cap)); n = llama_tokenize(vocab, text, Int32(utf8.count - 1), &out, cap, addBOS, special) }
        guard n >= 0 else { throw EngineError.tokenize }
        return Array(out.prefix(Int(n)))
    }

    private func piece(_ t: llama_token) -> String {
        var buf = [CChar](repeating: 0, count: 64)
        let n = llama_token_to_piece(vocab, t, &buf, Int32(buf.count), 0, false)
        guard n > 0 else { return "" }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Prefill `tokens`, reusing the cached common prefix. Leaves logits for the last token.
    private func prefill(_ tokens: [llama_token]) throws {
        guard tokens.count < nCtx else { throw EngineError.decode(-100) }   // prompt longer than context
        var common = zip(cached, tokens).prefix { $0 == $1 }.count
        if common == tokens.count { common -= 1 }                   // must decode >= 1 token to get logits
        let mem = llama_get_memory(ctx)
        if !llama_memory_seq_rm(mem, 0, Int32(common), -1) { llama_memory_clear(mem, true); prefixes.removeAll(); common = 0 }
        var i = common
        while i < tokens.count {
            let n = min(Int(nBatch), tokens.count - i)
            var chunk = Array(tokens[i..<(i + n)])
            let rc = chunk.withUnsafeMutableBufferPointer { llama_decode(ctx, llama_batch_get_one($0.baseAddress, Int32(n))) }
            if rc != 0, !prefixes.isEmpty {                            // KV slots taken by cached prefixes: drop them, redo once
                llama_memory_clear(mem, true); prefixes.removeAll(); cached = []
                return try prefill(tokens)
            }
            guard rc == 0 else { cached = []; throw EngineError.decode(rc) }
            i += n
        }
        cached = tokens
    }

    /// Single-token ids for " A" (Llama-3: 362) and "A". Variants that aren't one token are skipped.
    private func letterTokenIDs(_ l: String) throws -> [llama_token] {
        if let t = letterTokens[l] { return t }
        let ids = try [" " + l, l].compactMap { v -> llama_token? in let t = try tokenize(v, special: false); return t.count == 1 ? t[0] : nil }
        guard !ids.isEmpty else { throw EngineError.tokenize }
        letterTokens[l] = ids; return ids
    }

    /// Prefill a decision prompt, reusing a cached per-type prefix sequence when possible. Any mismatch => plain prefill.
    private func prefillDecision(_ prompt: String, _ tokens: [llama_token]) throws {
        guard prefixReuse, let r = prompt.range(of: Self.userTurn, options: .backwards), r.lowerBound > prompt.startIndex,
              let pt = try? tokenize(String(prompt[..<r.lowerBound]), addBOS: true), pt.count >= 16, pt.count < tokens.count,
              tokens.starts(with: pt), pt.count <= prefixBudget else { return try prefill(tokens) }
        let mem = llama_get_memory(ctx)
        let L = Int32(pt.count)
        useClock += 1
        if let hit = prefixes[pt] {
            prefixHits += 1
            prefixes[pt]!.used = useClock
            if !cached.starts(with: pt) {                           // seq 0 holds something else: swap in the cached prefix
                _ = llama_memory_seq_rm(mem, 0, -1, -1)             // removing a whole sequence never fails
                llama_memory_seq_cp(mem, hit.seq, 0, 0, L)
                guard llama_memory_seq_pos_max(mem, 0) == L - 1 else {   // safety: copy didn't land as expected
                    dropPrefixes(); cached = []; return try prefill(tokens)
                }
                cached = pt
            }
            do { try prefill(tokens) } catch { dropPrefixes(); cached = []; try prefill(tokens) }
            return
        }
        prefixMisses += 1
        // Make room (LRU by tokens), then evaluate normally and keep [0, L) of seq 0 as this prefix.
        while !prefixes.isEmpty, prefixes.keys.reduce(0, { $0 + $1.count }) + pt.count > prefixBudget || prefixes.count >= Int(Self.nSeq) - 1 {
            let victim = prefixes.min { $0.value.used < $1.value.used }!
            _ = llama_memory_seq_rm(mem, victim.value.seq, -1, -1)
            prefixes[victim.key] = nil
        }
        do { try prefill(tokens) } catch { dropPrefixes(); cached = []; try prefill(tokens) }
        let used = Set(prefixes.values.map { $0.seq })
        if let seq = (1..<Self.nSeq).first(where: { !used.contains($0) }) {
            _ = llama_memory_seq_rm(mem, seq, -1, -1)
            llama_memory_seq_cp(mem, 0, seq, 0, L)
            if llama_memory_seq_pos_max(mem, seq) == L - 1 { prefixes[pt] = (seq, useClock) } else { _ = llama_memory_seq_rm(mem, seq, -1, -1) }
        }
    }

    private func dropPrefixes() {
        let mem = llama_get_memory(ctx)
        for p in prefixes.values { _ = llama_memory_seq_rm(mem, p.seq, -1, -1) }
        prefixes.removeAll()
    }

    func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double] {
        let t0 = Date()
        let tokens = try tokenize(prompt, addBOS: true)     // same token stream as the llama-server eval (see tokenize)
        try prefillDecision(prompt, tokens)
        if prefixReuse {
            print(String(format: "PGPERF decision prompt_tokens=%d prefill_ms=%.0f prefix_hits=%d prefix_misses=%d prefixes=%d",
                         tokens.count, Date().timeIntervalSince(t0) * 1000, prefixHits, prefixMisses, prefixes.count))
        }
        guard let logits = llama_get_logits_ith(ctx, -1) else { throw LLMError.badResponse("no logits") }
        // Parity with the certified eval (llama-server `n_probs: 40`, LlamaServerEngine.topK): only token variants inside
        // the top-40 of the full vocabulary count, and a letter with no variant there is omitted so Reflex applies the
        // same floor (min seen - 2) as eval/score_decisions.py. Raw logits vs server log-probs differ by one constant
        // (log Z), which the letter softmax and the relative floor cancel.
        let cutoff = Self.kthLargest(logits, count: Int(llama_vocab_n_tokens(vocab)), k: Self.topK)
        var out: [String: Double] = [:]
        for l in candidates {
            // log-sum-exp over the letter's token variants, mirroring LlamaServerEngine.
            let v = try letterTokenIDs(l).map { logits[Int($0)] }.filter { $0 >= cutoff }.map { Double($0) }
            guard let m = v.max() else { continue }
            out[l] = m + log(v.reduce(0) { $0 + exp($1 - m) })
        }
        guard !out.isEmpty else { throw LLMError.noCandidateTokens }
        return out
    }

    func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        var tokens = try tokenize(prompt)
        let nPrompt = tokens.count
        let t0 = Date()
        if prefixReuse, !prefixes.isEmpty, prefixes.keys.reduce(0, { $0 + $1.count }) + nPrompt + maxTokens >= nCtx {
            dropPrefixes()                     // free KV cells so generation can use the whole context
        }
        try prefill(tokens)
        let tPrefill = Date()
        var tFirstToken: Date? = nil
        var nGen = 0
        defer {
            // Mac-day measurement line: filter the Xcode console for "PGPERF". RAM: Debug navigator > Memory gauge.
            let end = Date(), first = tFirstToken ?? end
            let decodeS = end.timeIntervalSince(first)
            print(String(format: "PGPERF prompt_tokens=%d prefill_ms=%.0f ttft_ms=%.0f gen_tokens=%d decode_tok_s=%.1f",
                         nPrompt, tPrefill.timeIntervalSince(t0) * 1000, first.timeIntervalSince(t0) * 1000,
                         nGen, (nGen > 1 && decodeS > 0) ? Double(nGen - 1) / decodeS : 0))
        }
        let budget = min(maxTokens, nCtx - tokens.count - 1)
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(chain) }
        if temperature <= 0 { llama_sampler_chain_add(chain, llama_sampler_init_greedy()) }
        else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        }
        var text = ""
        for _ in 0..<max(0, budget) {
            let t = llama_sampler_sample(chain, ctx, -1)
            if tFirstToken == nil { tFirstToken = Date() }
            if llama_vocab_is_eog(vocab, t) { break }
            nGen += 1
            text += piece(t)
            tokens.append(t)
            var one = [t]
            let rc = one.withUnsafeMutableBufferPointer { llama_decode(ctx, llama_batch_get_one($0.baseAddress, 1)) }
            guard rc == 0 else { throw EngineError.decode(rc) }
            cached = tokens
        }
        return text
    }
}
