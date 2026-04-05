import html
import json
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer


HOST = "0.0.0.0"
PORT = 8787
APP_CALLBACK_SCHEME = "secrandom://auth/callback"
WEB_RETURN_BASE_URL = "http://localhost:5173/oauth-callback"


class MockOAuthHandler(BaseHTTPRequestHandler):
    @staticmethod
    def _resolve_platform(query: dict, user_agent: str) -> str:
        # 优先使用显式参数，避免仅靠 UA 猜测导致误判
        raw = (
            query.get("platform", [""])[0]
            or query.get("client_platform", [""])[0]
        ).strip().lower()
        if raw in {"web", "windows", "android", "ios", "macos", "linux"}:
            return raw

        ua = user_agent.lower()
        if "flutter-web" in ua or "mozilla/" in ua:
            return "web"
        if "windows" in ua:
            return "windows"
        if "android" in ua:
            return "android"
        if "iphone" in ua or "ipad" in ua or "ios" in ua:
            return "ios"
        if "macintosh" in ua or "mac os" in ua:
            return "macos"
        if "linux" in ua:
            return "linux"
        return "unknown"

    def _send_json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj, separators=(",", ":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, code: int, body: str) -> None:
        body_bytes = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)

        if parsed.path == "/oauth/authorize":
            redirect_uri = query.get("redirect_uri", ["http://127.0.0.1:8788/callback"])[0]
            state = query.get("state", [""])[0]
            sep = "&" if "?" in redirect_uri else "?"
            location = f"{redirect_uri}{sep}code=mock_code_123"
            if state:
                location += f"&state={urllib.parse.quote(state, safe='')}"
            self.send_response(302)
            self.send_header("Location", location)
            self.end_headers()
            return

        if parsed.path == "/callback":
            platform = self._resolve_platform(
                query,
                self.headers.get("User-Agent", ""),
            )
            target = APP_CALLBACK_SCHEME
            if parsed.query:
                target = f"{target}?{parsed.query}"
            safe_target = html.escape(target, quote=True)
            # Web 专用回跳地址：把 code/state/error 原样带回前端页面
            web_return_params = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
            if not any(k == "platform" for k, _ in web_return_params):
                web_return_params.append(("platform", platform))
            web_return_target = WEB_RETURN_BASE_URL
            if web_return_params:
                web_return_target = (
                    f"{WEB_RETURN_BASE_URL}?{urllib.parse.urlencode(web_return_params)}"
                )
            safe_web_return_target = html.escape(web_return_target, quote=True)
            page = (
                "<!doctype html><html><head><meta charset='utf-8'>"
                "<meta name='viewport' content='width=device-width, initial-scale=1'>"
                "<title>OAuth Callback</title></head>"
                "<body style='font-family:Arial,sans-serif;padding:24px;line-height:1.6'>"
                "<h2>授权完成，正在返回 App...</h2>"
                f"<p>检测到平台：<b>{html.escape(platform)}</b></p>"
                "<p>若未自动跳转，请点击下方按钮。</p>"
                f"<p><a href='{safe_target}' style='display:inline-block;padding:10px 14px;background:#2563eb;color:#fff;text-decoration:none;border-radius:8px'>返回 Secrandom App</a></p>"
                f"<p><a href='{safe_web_return_target}' style='display:inline-block;padding:10px 14px;background:#059669;color:#fff;text-decoration:none;border-radius:8px'>返回 Web 页面</a></p>"
                f"<script>"
                f"var appTarget={json.dumps(target)};"
                f"var webTarget={json.dumps(web_return_target)};"
                f"var switched=false;"
                f"window.addEventListener('blur',function(){{switched=true;}});"
                f"var preferWeb={json.dumps(platform == 'web')};"
                f"if(preferWeb){{"
                f"  setTimeout(function(){{window.location.href=webTarget;}},120);"
                f"  setTimeout(function(){{if(!switched)window.location.href=appTarget;}},1200);"
                f"}}else{{"
                f"  setTimeout(function(){{window.location.href=appTarget;}},120);"
                f"  setTimeout(function(){{if(!switched)window.location.href=webTarget;}},1200);"
                f"}}"
                f"</script>"
                "</body></html>"
            )
            self._send_html(200, page)
            return

        if parsed.path == "/api/oauth/userinfo":
            authorization = self.headers.get("Authorization", "")
            if not authorization.startswith("Bearer "):
                self._send_json(
                    401,
                    {
                        "error": "invalid_token",
                        "error_description": "Missing bearer token",
                    },
                )
                return
            self._send_json(
                200,
                {
                    "user_id": "u_mock_001",
                    "email": "mock.user@example.com",
                    "name": "Mock User",
                    "github_username": "mock-gh",
                    "permission": 100,
                    "role": "tester",
                    "avatar_url": None,
                    "background_url": None,
                    "bio": "mock account for local testing",
                    "tags": ["qa", "oauth"],
                    "gender": "secret",
                    "gender_visible": False,
                    "birth_date": None,
                    "birth_calendar_type": None,
                    "birth_year_visible": False,
                    "birth_visible": False,
                    "location": "local",
                    "location_visible": True,
                    "website": "https://localhost",
                    "email_visible": False,
                    "developed_platforms": ["secrandom"],
                    "contributed_platforms": ["sectl"],
                    "user_type": "normal",
                    "created_at": "2026-01-01T00:00:00Z",
                    "platform_id": "69d054360032cf00c164",
                    "login_time": "2026-04-04T00:00:00Z",
                },
            )
            return

        self._send_json(404, {"error": "not_found", "path": parsed.path})

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(length).decode("utf-8") if length > 0 else ""
        try:
            body = json.loads(raw) if raw else {}
        except Exception:
            body = {}

        if parsed.path == "/api/oauth/token":
            if body.get("grant_type") == "refresh_token":
                self._send_json(
                    200,
                    {
                        "access_token": "mock_access_token_refreshed",
                        "refresh_token": "mock_refresh_token_456",
                        "token_type": "Bearer",
                        "expires_in": 3600,
                    },
                )
                return
            self._send_json(
                200,
                {
                    "access_token": "mock_access_token_123",
                    "refresh_token": "mock_refresh_token_456",
                    "token_type": "Bearer",
                    "expires_in": 3600,
                },
            )
            return

        if parsed.path == "/api/oauth/introspect":
            self._send_json(200, {"active": True})
            return

        if parsed.path == "/api/oauth/logout":
            self._send_json(200, {"success": True})
            return

        self._send_json(404, {"error": "not_found", "path": parsed.path})

    def log_message(self, fmt: str, *args) -> None:
        print(f"[mock] {fmt % args}", flush=True)


def main() -> None:
    print(f"Mock OAuth server (callback bridge) running at {HOST}:{PORT}", flush=True)
    HTTPServer((HOST, PORT), MockOAuthHandler).serve_forever()


if __name__ == "__main__":
    main()
