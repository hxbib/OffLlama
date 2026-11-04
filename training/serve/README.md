# Self-hosted System-2: Muse Glimmer 30B on Modal (vLLM, H100)

Muse Glimmer 30B is Meta's open-weights model (Apache-2.0). Here it runs as Pocket Glimmer's cloud brain on our own Modal GPU. The API is OpenAI-compatible, so the app's existing `CloudPresets.modal` client works without changes. Full write-up and measured numbers: `docs/OPEN_WEIGHTS_SYSTEM2.md`.

| | |
|---|---|
| Model | `meta-models/Muse-Glimmer-30B`, bf16 safetensors (~59.6 GB), served as `muse-glimmer` |
| Server | vLLM 0.33.0. Glimmer support is native since 0.28.0; no `trust_remote_code` |
| Flags | `--generation-config auto --tool-call-parser muse_glimmer --reasoning-parser muse_glimmer --enable-auto-tool-choice --language-model-only --max-model-len 16384 --default-chat-template-kwargs '{"reasoning_strength":"low"}'` |
| GPU | 1x H100 80GB. `min_containers=0`, `max_containers=1`, `scaledown_window=300` (idle costs $0) |
| Auth | Every path except `/health` needs `Authorization: Bearer $PG_GLIMMER_TOKEN`. The check is `pg_auth.py`, and the token is stored in the Modal Secret `pg-glimmer-token` |
| Storage | Weights live in Volume `pg-glimmer-weights`. The torch.compile/vLLM cache lives in Volume `pg-glimmer-vllm-cache` |

## Deploy

```bash
source /tmp/gencode/sec/env.sh                       # MODAL_TOKEN_ID / MODAL_TOKEN_SECRET (never commit)
MODAL=/tmp/gencode/modalenv/bin/modal                # modal 1.6.3
# one-time: bearer token as a Modal Secret (keep a private copy for clients)
python3 -c "import json,secrets; json.dump({'PG_GLIMMER_TOKEN':'pgg_'+secrets.token_urlsafe(32)}, open('/tmp/tok.json','w'))"
$MODAL secret create pg-glimmer-token --from-json /tmp/tok.json --force && rm /tmp/tok.json
# one-time: weights -> Volume (~60 GB)
$MODAL run training/serve/modal_glimmer_vllm.py::download
# persistent endpoint (prints https://<workspace>--pg-glimmer-vllm-serve.<region>.modal.run)
$MODAL deploy training/serve/modal_glimmer_vllm.py
```

## Smoke test

```bash
source /tmp/gencode/sec/glimmer.env                  # PG_GLIMMER_URL, PG_GLIMMER_TOKEN (outside the repo)
python3 eval/serve/smoke_glimmer.py --out eval/serve/glimmer_modal_smoke.json
# the app's own Swift CloudBrain code:
docker run --rm --network host -e PG_GLIMMER_TOKEN -v "$PWD/core:/src" -w /src swift:6.1-noble \
  bash -c 'swift run -c debug pg-cli cloud-probe --url "'"$PG_GLIMMER_URL"'/v1/" --model muse-glimmer "question with [PERSON_1]"'
```

## Stop / cost control

The endpoint scales to zero 5 minutes after the last request. To take it down entirely, run `modal app stop pg-glimmer-vllm`. The H100 is billed per second only while a container is up, at the Modal list price of about $3.95–4.56/h.
