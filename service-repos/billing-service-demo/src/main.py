"""Billing Service for multi-tenant GitOps demo."""

import os
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = int(os.environ.get('PORT', 8080))
FLINK_ENABLED = os.environ.get('FLINK_ENABLED', 'false').lower() == 'true'
FLINK_PARALLELISM = int(os.environ.get('FLINK_PARALLELISM', 1))
FLINK_CHECKPOINT_INTERVAL = int(os.environ.get('FLINK_CHECKPOINT_INTERVAL', 60000))


class BillingHandler(BaseHTTPRequestHandler):
    """HTTP request handler for Billing service."""

    def log_message(self, format, *args):
        """Override to add timestamp to logs."""
        print(f"[{datetime.utcnow().isoformat()}] {args[0]}")

    def _send_json_response(self, status_code: int, data: dict):
        """Send JSON response."""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/health':
            self._send_json_response(200, {
                'status': 'healthy',
                'service': 'billing'
            })
            return

        if self.path == '/ready':
            self._send_json_response(200, {
                'status': 'ready',
                'service': 'billing'
            })
            return

        if self.path == '/':
            self._send_json_response(200, {
                'service': 'billing',
                'version': '0.1.0',
                'flink': {
                    'enabled': FLINK_ENABLED,
                    'parallelism': FLINK_PARALLELISM,
                    'checkpointInterval': FLINK_CHECKPOINT_INTERVAL
                }
            })
            return

        if self.path == '/pipeline/status':
            self._send_json_response(200, {
                'pipeline': 'billing-processor',
                'status': 'running' if FLINK_ENABLED else 'disabled',
                'config': {
                    'parallelism': FLINK_PARALLELISM,
                    'checkpointInterval': FLINK_CHECKPOINT_INTERVAL
                }
            })
            return

        self._send_json_response(404, {'error': 'Not Found'})


def main():
    """Start the billing service."""
    server = HTTPServer(('', PORT), BillingHandler)
    print(f"[{datetime.utcnow().isoformat()}] Billing Service started on port {PORT}")
    print(f"[{datetime.utcnow().isoformat()}] Flink pipeline: {'enabled' if FLINK_ENABLED else 'disabled'}")
    if FLINK_ENABLED:
        print(f"[{datetime.utcnow().isoformat()}] Flink parallelism: {FLINK_PARALLELISM}")
        print(f"[{datetime.utcnow().isoformat()}] Flink checkpoint interval: {FLINK_CHECKPOINT_INTERVAL}ms")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print(f"\n[{datetime.utcnow().isoformat()}] Shutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
