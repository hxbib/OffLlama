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
    private var letterTokens: [String: llama_token] = [:]

    enum EngineError: Error { case load(String), context, tokenize, decode(Int32) }

    init(modelURL: URL, contextLength: UInt32 = 4096) throws {
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
        guard let c = llama_init_from_model(m, cp) else { llama_model_free(m); throw EngineError.context }
        model = m; ctx = c; vocab = llama_model_get_vocab(m)
        modelName = modelURL.deletingPathExtension().lastPathComponent
    }

    deinit { llama_free(ctx); llama_model_free(model) }

    private func tokenize(_ text: String, special: Bool = true) throws -> [llama_token] {
        let utf8 = Array(text.utf8CString)
        var cap = Int32(utf8.count + 16)
        var out = [llama_token](repeating: 0, count: Int(cap))
        var n = llama_tokenize(vocab, text, Int32(utf8.count - 1), &out, cap, false, special)
        if n < 0 { cap = -n; out = .init(repeating: 0, count: Int(cap)); n = llama_tokenize(vocab, text, Int32(utf8.count - 1), &out, cap, false, special) }
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
        var common = zip(cached, tokens).prefix { $0 == $1 }.count
        if common == tokens.count { common -= 1 }                   // must decode >= 1 token to get logits
        let mem = llama_get_memory(ctx)
        if !llama_memory_seq_rm(mem, 0, Int32(common), -1) { llama_memory_clear(mem, true); common = 0 }
        var i = common
        while i < tokens.count {
            let n = min(Int(nBatch), tokens.count - i)
            var chunk = Array(tokens[i..<(i + n)])
            let rc = chunk.withUnsafeMutableBufferPointer { llama_decode(ctx, llama_batch_get_one($0.baseAddress, Int32(n))) }
            guard rc == 0 else { cached = []; throw EngineError.decode(rc) }
            i += n
        }
        cached = tokens
    }

    private func letterToken(_ l: String) throws -> llama_token {
        if let t = letterTokens[l] { return t }
        let t = try tokenize(" " + l, special: false)               // " A" is one Llama-3 token (362)
        guard t.count == 1 else { throw EngineError.tokenize }
        letterTokens[l] = t[0]; return t[0]
    }

    func nextTokenLogits(prompt: String, candidates: [String]) async throws -> [String: Double] {
        try prefill(try tokenize(prompt))
        guard let logits = llama_get_logits_ith(ctx, -1) else { throw LLMError.badResponse("no logits") }
        var out: [String: Double] = [:]
        for l in candidates {
            let spaced = Double(logits[Int(try letterToken(l))])
            // Also consider the bare letter token and merge (log-sum-exp), mirroring LlamaServerEngine.
            if let bare = try? tokenize(l, special: false), bare.count == 1 {
                let b = Double(logits[Int(bare[0])]); let m = max(spaced, b)
                out[l] = m + log(exp(spaced - m) + exp(b - m))
            } else { out[l] = spaced }
        }
        return out
    }

    func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        var tokens = try tokenize(prompt)
        try prefill(tokens)
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(chain) }
        if temperature <= 0 { llama_sampler_chain_add(chain, llama_sampler_init_greedy()) }
        else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        }
        var text = ""
        for _ in 0..<maxTokens {
            let t = llama_sampler_sample(chain, ctx, -1)
            if llama_vocab_is_eog(vocab, t) { break }
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
