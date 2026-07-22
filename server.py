#!/usr/bin/env python3
import http.server, os, sys

os.chdir(os.path.dirname(os.path.abspath(__file__)))
port = int(os.environ.get('PORT') or (sys.argv[1] if len(sys.argv) > 1 else 4040))

handler = http.server.SimpleHTTPRequestHandler
with http.server.HTTPServer(('', port), handler) as httpd:
    print(f'Serving on port {port}')
    httpd.serve_forever()
