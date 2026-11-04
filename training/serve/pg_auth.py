"""Bearer-token gate for the self-hosted Muse Glimmer vLLM server (loaded via `vllm serve --middleware pg_auth.bearer_auth`).

vLLM's own `--api-key` guards only /v1, /v2 and /inference; /invocations (same inference capability) stays open.
This middleware requires `Authorization: Bearer $PG_GLIMMER_TOKEN` on every path except /health, so the public
*.modal.run URL cannot be used to burn GPU time without the token. The token lives in the Modal Secret
`pg-glimmer-token`, never in the repo."""
import hmac
import os

from starlette.responses import JSONResponse

_EXPECTED = ("Bearer " + os.environ["PG_GLIMMER_TOKEN"]).encode()
_OPEN = {"/health"}


async def bearer_auth(request, call_next):
    if request.url.path not in _OPEN:
        if not hmac.compare_digest(request.headers.get("authorization", "").encode(), _EXPECTED):
            return JSONResponse({"error": {"message": "unauthorized", "type": "auth_error"}}, status_code=401)
    return await call_next(request)
