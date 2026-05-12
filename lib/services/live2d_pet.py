"""
Live2D Desktop Pet — PyQt6 transparent window for AI VTuber Agent.

Architecture (mirrors D:\\AUAK_Live2D_Desktop_AI approach):
  Flutter launches this script as a subprocess:
    python live2d_pet.py --port 48889 --model-url http://localhost:48888/models/live2d/...

  This script:
    1. Creates a frameless, always-on-top, transparent PyQt6 window
    2. Loads pet.html from the Live2D HTTP server (localhost:48888) in a QWebEngineView
    3. Sets up QWebChannel for:
       - windowController: frameless drag (start_drag / drag / end_drag)
       - mouseTracker: 60fps cursor position → JS eye tracking
    4. Starts a control HTTP server on localhost:<port> for Flutter commands

  Flutter controls via HTTP:
    GET  /health              → {status: "ok"}
    POST /click_through       → toggle click-through (body: {"enable": bool})
    POST /close               → clean shutdown
    POST /reload_model        → reload model (body: {"model_url": "...", scale: ..., x: ..., y: ...})
    POST /show_message        → show chat bubble (body: {"text": "...", "duration_ms": ...})
    GET  /status              → {click_through, window_pos: {x,y}, window_size: {w,h}}
"""

import sys
import os
import json
import ctypes
import threading
import argparse
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

from PyQt6.QtWidgets import QApplication, QMainWindow, QVBoxLayout, QWidget
from PyQt6.QtWebEngineWidgets import QWebEngineView
from PyQt6.QtWebChannel import QWebChannel
from PyQt6.QtCore import (
    Qt, QUrl, QTimer, QObject, pyqtSlot, pyqtSignal, QPoint
)
from PyQt6.QtWebEngineCore import QWebEnginePage, QWebEngineSettings
from PyQt6.QtGui import QCursor, QScreen


# ─── Win32 helpers ───
GWL_EXSTYLE = -20
WS_EX_TRANSPARENT = 0x00000020

user32 = ctypes.windll.user32


def get_hwnd(widget) -> int:
    """Get the native HWND for a QWidget."""
    return int(widget.winId())


def set_click_through(hwnd: int, enable: bool):
    """Toggle WS_EX_TRANSPARENT. When enabled, mouse events pass through."""
    ex_style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
    if enable:
        ex_style |= WS_EX_TRANSPARENT
    else:
        ex_style &= ~WS_EX_TRANSPARENT
    user32.SetWindowLongW(hwnd, GWL_EXSTYLE, ex_style)
    # Force window to re-evaluate layered + transparent flags
    user32.SetWindowPos(hwnd, 0, 0, 0, 0, 0, 0x0002 | 0x0001)  # SWP_NOMOVE | SWP_NOSIZE


# ─── Window drag controller (exposed to JS via QWebChannel) ───
class WindowController(QObject):
    """Frameless window drag — three-step protocol: start → drag → end."""

    def __init__(self, parent_window: QMainWindow):
        super().__init__()
        self.parent_window = parent_window
        self.old_pos: QPoint | None = None

    @pyqtSlot()
    def start_drag(self):
        self.old_pos = QCursor.pos()

    @pyqtSlot()
    def end_drag(self):
        self.old_pos = None

    @pyqtSlot()
    def drag(self):
        if self.old_pos is not None:
            delta = QCursor.pos() - self.old_pos
            self.parent_window.move(self.parent_window.pos() + delta)
            self.old_pos = QCursor.pos()


# ─── Mouse tracker (60fps → JS eye tracking) ───
class MouseTracker(QObject):
    """Tracks cursor position relative to window, emitted to JS for eye tracking."""
    mouseMoved = pyqtSignal(int, int)

    def __init__(self, parent_window: QMainWindow):
        super().__init__()
        self.parent_window = parent_window
        self.timer = QTimer()
        self.timer.timeout.connect(self.track_mouse)
        self.timer.start(16)  # ~60 fps

    def track_mouse(self):
        if self.parent_window and self.parent_window.isVisible():
            global_pos = QCursor.pos()
            relative_pos = global_pos - self.parent_window.geometry().topLeft()
            self.mouseMoved.emit(relative_pos.x(), relative_pos.y())


# ─── HTTP control request handler ───
class ControlHandler(BaseHTTPRequestHandler):
    """Tiny HTTP server for Flutter ↔ Pet communication."""

    main_window: 'Live2DPetWindow' = None

    def log_message(self, format, *args):
        pass  # suppress HTTP logs

    def do_GET(self):
        if self.path in ('/health', '/'):
            self._send_json({"status": "ok"})
        elif self.path == '/status':
            w = self.main_window
            geo = w.geometry() if w else None
            self._send_json({
                "click_through": w._click_through if w else None,
                "window_pos": {"x": geo.x(), "y": geo.y()} if geo else None,
                "window_size": {"w": geo.width(), "h": geo.height()} if geo else None,
            })
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        content_len = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_len) if content_len > 0 else b'{}'
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            data = {}

        if self.path == '/click_through':
            enable = data.get('enable', True)
            if self.main_window:
                self.main_window.toggle_click_through(enable)
            self._send_json({"click_through": enable})

        elif self.path == '/close':
            self._send_json({"status": "closing"})
            if self.main_window:
                QTimer.singleShot(100, self.main_window.shutdown)

        elif self.path == '/reload_model':
            model_url = data.get('model_url', '')
            if self.main_window and model_url:
                self.main_window.reload_model(
                    model_url,
                    scale=data.get('scale'),
                    x=data.get('x'),
                    y=data.get('y'),
                )
            self._send_json({"status": "reloading", "model_url": model_url})

        elif self.path == '/show_message':
            text = data.get('text', '')
            duration_ms = data.get('duration_ms', 3000)
            if self.main_window and text:
                self.main_window.show_message(text, duration_ms)
            self._send_json({"status": "ok"})

        else:
            self.send_response(404)
            self.end_headers()

    def _send_json(self, data: dict):
        body = json.dumps(data).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)


# ─── Parent-alive checker (exits pet when Flutter is closed) ───
# On Windows, ProcessSignal.sigterm.watch() in Dart does not reliably
# fire when the Flutter window is closed. Instead, the Python pet
# periodically polls Flutter's Live2DServer (port 48888). If the server
# is unreachable for 3 consecutive checks, Flutter has exited and the
# pet shuts itself down.
class ParentAliveChecker(QObject):
    def __init__(self, parent_window: 'Live2DPetWindow',
                 health_url: str = 'http://127.0.0.1:48888', interval_ms: int = 3000):
        super().__init__()
        self.parent_window = parent_window
        self.health_url = health_url
        self.fail_count = 0
        self.max_fails = 1
        self.timer = QTimer()
        self.timer.timeout.connect(self._check)
        self.timer.start(interval_ms)

    def _check(self):
        try:
            req = urllib.request.Request(self.health_url, method='HEAD')
            urllib.request.urlopen(req, timeout=2)
            self.fail_count = 0  # parent alive
        except Exception:
            self.fail_count += 1
            if self.fail_count >= self.max_fails:
                print(f'[Live2DPet] Parent (Flutter) unreachable for '
                      f'{self.fail_count} checks. Shutting down.', flush=True)
                self.timer.stop()
                self.parent_window.shutdown()


# ─── Main Live2D pet window ───
class Live2DPetWindow(QMainWindow):
    DEFAULT_W = 320
    DEFAULT_H = 480

    def __init__(self, model_url: str, scale: float = 0, x_pct: float = 50.0,
                 y_pct: float = 50.0, control_port: int = 48889):
        super().__init__()

        self._model_url = model_url
        self._scale = scale   # 0 = auto-scale
        self._x_pct = x_pct
        self._y_pct = y_pct
        self._control_port = control_port
        self._click_through = False  # default: interactive (not click-through)

        # 1. Window flags: frameless, always-on-top, tool (no taskbar entry)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)

        # Center on screen
        screen_geo = QApplication.primaryScreen().availableGeometry() if QApplication.primaryScreen() else None
        if screen_geo:
            cx = (screen_geo.width() - self.DEFAULT_W) // 2 + screen_geo.x()
            cy = (screen_geo.height() - self.DEFAULT_H) // 2 + screen_geo.y()
        else:
            cx, cy = 100, 100
        self.setGeometry(cx, cy, self.DEFAULT_W, self.DEFAULT_H)

        # 2. WebView — transparent background, JS enabled
        self.view = QWebEngineView()
        self.view.page().setBackgroundColor(Qt.GlobalColor.transparent)
        self.view.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)

        settings = self.view.page().settings()
        settings.setAttribute(QWebEngineSettings.WebAttribute.JavascriptEnabled, True)
        settings.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, True)
        settings.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessRemoteUrls, True)

        # 3. Build URL with query params
        pet_base = "http://localhost:48888/live2d_web/pet.html"
        escaped_model = self._model_url.replace('"', '%22')
        full_url = (
            f"{pet_base}"
            f"?model={escaped_model}"
            f"&scale={self._scale}"
            f"&x={self._x_pct}"
            f"&y={self._y_pct}"
            f"&port={self._control_port}"
        )
        self.view.load(QUrl(full_url))
        self.view.loadFinished.connect(self._on_load_finished)

        # 4. Layout — full view
        layout = QVBoxLayout()
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.view)
        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)

        # 5. QWebChannel — drag + eye tracking
        self._setup_web_channel()

        # 6. Parent-alive checker — polls Flutter HTTP server, exits if Flutter is gone
        self._parent_checker = ParentAliveChecker(self)

        # 7. Show
        self.show()

    def _setup_web_channel(self):
        self.channel = QWebChannel(self)
        self.window_controller = WindowController(self)
        self.mouse_tracker = MouseTracker(self)

        self.channel.registerObject("windowController", self.window_controller)
        self.channel.registerObject("mouseTracker", self.mouse_tracker)
        self.view.page().setWebChannel(self.channel)

    def _on_load_finished(self, ok: bool):
        if not ok:
            print(f"[Live2DPet] Page load failed for: {self._model_url}", file=sys.stderr)
        else:
            print(f"[Live2DPet] Page loaded. Model: {self._model_url}", flush=True)

    def toggle_click_through(self, enable: bool):
        self._click_through = enable
        hwnd = get_hwnd(self)
        set_click_through(hwnd, enable)
        # Update JS to hide/show drag handle
        self.view.page().runJavaScript(f"window.setClickThrough({str(enable).lower()});")

    def show_message(self, text: str, duration_ms: int = 3000):
        """Show a chat bubble on the pet."""
        escaped = text.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')
        self.view.page().runJavaScript(f"window.showMessage('{escaped}', {duration_ms});")

    def reload_model(self, model_url: str, scale: float | None,
                     x: float | None, y: float | None):
        self._model_url = model_url
        if scale is not None:
            self._scale = scale
        if x is not None:
            self._x_pct = x
        if y is not None:
            self._y_pct = y

        escaped_model = self._model_url.replace('"', '%22')
        full_url = (
            f"http://localhost:48888/live2d_web/pet.html"
            f"?model={escaped_model}"
            f"&scale={self._scale}"
            f"&x={self._x_pct}"
            f"&y={self._y_pct}"
            f"&port={self._control_port}"
        )
        self.view.load(QUrl(full_url))

    def shutdown(self):
        """Clean shutdown — stop checker, hide then quit the Qt event loop."""
        if hasattr(self, '_parent_checker') and self._parent_checker:
            self._parent_checker.timer.stop()
        self.hide()
        QApplication.quit()

    def closeEvent(self, event):
        self.shutdown()
        event.accept()


# ─── Entry point ───
def main():
    parser = argparse.ArgumentParser(description="Live2D Desktop Pet (PyQt6)")
    parser.add_argument("--port", type=int, default=48889,
                        help="HTTP control server port (default: 48889)")
    parser.add_argument("--model-url", type=str, required=True,
                        help="Full HTTP URL to the Live2D model JSON")
    parser.add_argument("--scale", type=float, default=0,
                        help="Model scale (0 = auto-fit, default: 0)")
    parser.add_argument("--x", type=float, default=50.0,
                        help="Model X position percent (default: 50)")
    parser.add_argument("--y", type=float, default=42.0,
                        help="Model Y position percent (default: 42, shifted up to visually center chibi models)")
    args = parser.parse_args()

    # Qt application
    app = QApplication(sys.argv)
    app.setApplicationName("Live2DPet")

    # Create the window
    window = Live2DPetWindow(
        model_url=args.model_url,
        scale=args.scale,
        x_pct=args.x,
        y_pct=args.y,
        control_port=args.port,
    )

    # Start HTTP control server in a daemon thread
    ControlHandler.main_window = window
    httpd = HTTPServer(('127.0.0.1', args.port), ControlHandler)
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    print(f"[Live2DPet] Control server: http://localhost:{args.port}", flush=True)

    # Run Qt event loop
    try:
        app.exec()
    finally:
        httpd.shutdown()
        print("[Live2DPet] Shutdown complete.", flush=True)


if __name__ == "__main__":
    main()
