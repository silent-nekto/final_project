import socket
import pickle
client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client.connect(("127.0.0.1", 1234))
cmd = {
    'method': 'list_dir',
    'args': ['come_dir']
}
bin_cmd = pickle.dumps(cmd)
print(f'{bin_cmd=}')
client.sendall(bin_cmd + b'\n')
response = client.recv(1024)
resp = pickle.loads(response)
print(f"Command: {cmd} -> Response: {resp}")
client.close()
