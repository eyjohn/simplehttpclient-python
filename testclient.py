import sys

from simplehttpclient import Request, Response, SimpleHttpClient

if len(sys.argv) != 4:
    print("Usage: python testclient.py <host> <port> <path>")
    sys.exit(1)


client = SimpleHttpClient(sys.argv[1], int(sys.argv[2]))
req = Request(sys.argv[3], None)
resp = client.make_request(req)
print("Received:", resp)
