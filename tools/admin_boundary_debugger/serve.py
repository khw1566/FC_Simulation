from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import webbrowser


PROJECT_ROOT = Path(__file__).resolve().parents[2]
URL = "http://127.0.0.1:8765/tools/admin_boundary_debugger/"


def main():
    handler = partial(SimpleHTTPRequestHandler, directory=str(PROJECT_ROOT))
    server = ThreadingHTTPServer(("127.0.0.1", 8765), handler)
    print(f"행정구역 디버거: {URL}")
    print("서버를 종료하려면 이 창에서 Ctrl+C를 누르세요.")
    webbrowser.open_new_tab(URL)
    server.serve_forever()


if __name__ == "__main__":
    main()
