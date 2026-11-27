# HTTP server for the tests: serves a directory, the big files at about 3 MB/s
# so a download can be cancelled while it runs.
# usage: slow_server.py DIRECTORY PORT_FILE
# the port is written in PORT_FILE once the server listens
import functools
import http.server
import os
import sys
import threading
import time


class SlowHandler(http.server.SimpleHTTPRequestHandler):
    def copyfile(self, source, outputfile):
        slow = os.fstat(source.fileno()).st_size > 1024 * 1024
        while True:
            chunk = source.read(64 * 1024)
            if not chunk:
                break
            try:
                outputfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                return
            if slow:
                time.sleep(0.02)

    def log_message(self, *args):
        pass


def exit_with_parent():
    # the test may abort: do not stay alive without it
    parent = os.getppid()
    while os.getppid() == parent:
        time.sleep(0.5)
    os._exit(0)


threading.Thread(target=exit_with_parent, daemon=True).start()
handler = functools.partial(SlowHandler, directory=sys.argv[1])
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
port_file = sys.argv[2]
with open(port_file + ".tmp", "w") as f:
    f.write(str(server.server_address[1]))
os.rename(port_file + ".tmp", port_file)
server.serve_forever()
