import socket, socketserver, select, struct

def exact(s,n):
 b=b''
 while len(b)<n:
  x=s.recv(n-len(b))
  if not x: raise EOFError()
  b+=x
 return b
class Handler(socketserver.BaseRequestHandler):
 def handle(self):
  c=self.request; c.settimeout(20); upstream=None
  try:
   first=exact(c,1)
   if first==b'\x05':
    n=exact(c,1)[0]; methods=exact(c,n)
    if 0 not in methods: c.sendall(b'\x05\xff'); return
    c.sendall(b'\x05\x00'); ver,cmd,_,atyp=exact(c,4)
    if ver!=5 or cmd!=1: c.sendall(b'\x05\x07\x00\x01'+b'\x00'*6); return
    if atyp==1: host=socket.inet_ntop(socket.AF_INET,exact(c,4))
    elif atyp==3: host=exact(c,exact(c,1)[0]).decode('idna')
    elif atyp==4: host=socket.inet_ntop(socket.AF_INET6,exact(c,16))
    else: return
    port=struct.unpack('!H',exact(c,2))[0]
    upstream=socket.create_connection((host,port),timeout=15); c.sendall(b'\x05\x00\x00\x01'+b'\x00'*6)
   else:
    data=first
    while b'\r\n\r\n' not in data and len(data)<65536: data+=exact(c,1)
    head,rest=data.split(b'\r\n\r\n',1); lines=head.split(b'\r\n'); method,target,version=lines[0].decode('iso-8859-1').split(' ',2)
    if method.upper()=='CONNECT':
     from urllib.parse import urlsplit
     u=urlsplit('//'+target); host=u.hostname; port=u.port or 443
     upstream=socket.create_connection((host,port),timeout=15); c.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
     if rest: upstream.sendall(rest)
    else:
     from urllib.parse import urlsplit
     u=urlsplit(target); host=u.hostname; port=u.port or 80
     if u.scheme!='http' or not host: return
     upstream=socket.create_connection((host,port),timeout=15)
     path=u.path or '/'
     if u.query: path+='?'+u.query
     lines[0]=(method+' '+path+' '+version).encode('iso-8859-1')
     upstream.sendall(b'\r\n'.join(lines)+b'\r\n\r\n'+rest)
   c.settimeout(None); upstream.settimeout(None)
   while True:
    ready,_,_=select.select([c,upstream],[],[],300)
    if not ready: break
    for s in ready:
     data=s.recv(65536)
     if not data: return
     (upstream if s is c else c).sendall(data)
  except Exception: pass
  finally:
   if upstream: upstream.close()
class Server(socketserver.ThreadingTCPServer):
 allow_reuse_address=True
 daemon_threads=True
Server(('0.0.0.0',2079),Handler).serve_forever()
