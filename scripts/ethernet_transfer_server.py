"""Bounded direct-link binary transfer probe; no shell or filesystem access."""

import argparse
import hashlib
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="192.168.7.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--seconds", type=int, default=600)
    parser.add_argument("--backup-output", type=Path,
                        help="Receive one 6 MiB QSPI boot-partition backup; never overwrite a file")
    args = parser.parse_args()
    payload = os.urandom(1024 * 1024)
    stress_script = Path(__file__).with_name("ethernet_uart_stress.sh").read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    counts = {"downloads": 0, "uploads": 0, "bad_uploads": 0}

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(15)

        def reply(self, status, data):
            self.send_response(status)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/payload.bin":
                self.reply(200, payload)
                counts["downloads"] += 1
            elif self.path == "/sha256":
                self.reply(200, (digest + "\n").encode("ascii"))
            elif self.path == "/stress.sh":
                self.reply(200, stress_script)
            else:
                self.reply(404, b"not found\n")

        def do_POST(self):
            if self.path == "/qspi-backup" and args.backup_output:
                if self.headers.get("Content-Length") != str(6 * 1024 * 1024):
                    self.reply(400, b"expected 6 MiB boot partition\n")
                    return
                data = self.rfile.read(6 * 1024 * 1024)
                if len(data) != 6 * 1024 * 1024:
                    self.reply(400, b"short backup\n")
                    return
                args.backup_output.parent.mkdir(parents=True, exist_ok=True)
                with args.backup_output.open("xb") as backup:
                    backup.write(data)
                backup_hash = hashlib.sha256(data).hexdigest()
                counts["qspi_backup_bytes"] = len(data)
                counts["qspi_backup_sha256"] = backup_hash
                self.reply(200, ("BACKUP_OK " + backup_hash + "\n").encode("ascii"))
                return
            if self.path != "/upload":
                self.reply(404, b"not found\n")
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                size = 0
            if size != len(payload):
                self.reply(400, b"expected exactly 1 MiB\n")
                return
            data = self.rfile.read(size)
            actual = hashlib.sha256(data).hexdigest()
            if len(data) != size or actual != digest:
                counts["bad_uploads"] += 1
                self.reply(422, b"hash mismatch\n")
                return
            counts["uploads"] += 1
            self.reply(200, ("UPLOAD_OK " + actual + "\n").encode("ascii"))

        def log_message(self, *_args):
            pass

    with HTTPServer((args.bind, args.port), Handler) as server:
        server.timeout = 1
        print(json.dumps({"host": args.bind, "port": args.port,
                          "bytes": len(payload), "sha256": digest}), flush=True)
        deadline = time.monotonic() + args.seconds
        try:
            while time.monotonic() < deadline:
                server.handle_request()
                if "qspi_backup_bytes" in counts:
                    break
        except KeyboardInterrupt:
            pass
        finally:
            print(json.dumps(counts), flush=True)


if __name__ == "__main__":
    main()
