#!/usr/bin/env python3
"""Bridge MCP stdio to an already-running ADB Connector HTTP server."""
import json
import os
import sys
import urllib.request

endpoint = os.environ.get('ADB_CONNECTOR_MCP_URL', '')
token = os.environ.get('ADB_CONNECTOR_MCP_TOKEN', '')
if not endpoint.startswith('http://127.0.0.1:') or not token:
    print('Configure ADB_CONNECTOR_MCP_URL and ADB_CONNECTOR_MCP_TOKEN in the app.', file=sys.stderr)
    sys.exit(1)

for line in sys.stdin:
    message = None
    try:
        message = json.loads(line)
        request = urllib.request.Request(endpoint, line.encode('utf-8'), {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'Authorization': 'Bearer ' + token,
        }, method='POST')
        with urllib.request.urlopen(request, timeout=75) as response:
            body = response.read()
        if body:
            print(body.decode('utf-8'), flush=True)
    except Exception as error:
        if isinstance(message, dict) and 'id' in message:
            print(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'error': {
                'code': -32603, 'message': 'ADB Connector MCP is unavailable: ' + str(error)
            }}), flush=True)
        else:
            print(str(error), file=sys.stderr, flush=True)
