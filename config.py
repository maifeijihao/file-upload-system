import socket

PASSWORD = ""
START_PORT = 5000

def find_available_port(start_port):
    port = start_port
    max_port = start_port + 100
    
    while port <= max_port:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('0.0.0.0', port))
            sock.close()
            return port
        except OSError:
            port += 1
            continue
    
    return None
