import socket
import pickle
import uuid
import time


class Client:
    def __init__(self, ip, port, timeout=600):
        self.ip = ip
        self.port = port
        self.sock = None
        self.timeout = timeout
        self._connect()

    def _connect(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.connect((self.ip, self.port))
        if self.timeout > 60:
            # для переподключения на случай обрыва соединения
            # т.к. ошибка чтения из закрытого соединения может прилететь не сразу
            self.sock.settimeout(60)

    def close(self):
        self.sock.close()

    def send_cmd(self, method, *args, **kwargs):
        cmd = {
            'method': method,
            'args': args,
            'kwargs': kwargs,
            'id': uuid.uuid4()
        }
        
        return self._process_command(cmd)
    
    def _process_command(self, cmd):
        elapsed = 0
        start = time.time()

        bin_cmd = pickle.dumps(cmd)
        cmd_len = len(bin_cmd).to_bytes(8, 'big')
        
        while elapsed < self.timeout:
            elapsed = time.time() - start
            try:
                self.sock.sendall(cmd_len + bin_cmd)
                response = bytes()
                resp_len = int.from_bytes(self.sock.recv(8), 'big')
                while len(response) < resp_len:
                    chunk = self.sock.recv(1024)
                    print(chunk)
                    if not chunk:
                        break
                    response += chunk
            except socket.timeout:
                #  возможно разрыв
                print('reconnecting...')
                self._connect()
                continue
            return pickle.loads(response)
        raise TimeoutError('Command was hanged')


class FileOperations:
    def __init__(self, ip, port):
        self.client = None
        self.ip = ip
        self.port = port

    def list_dir(self, path):
        return self.client.send_cmd('list_dir', path)
    
    def write(self, path, mode, data):
        return self.client.send_cmd('write_to_file', path, mode, data)
    
    def delete(self, path):
        return self.client.send_cmd('delete_file', path)
    
    def start(self):
        self.client = Client(self.ip, self.port)

    def stop(self):
        self.client.close()
    
    def __enter__(self):
        self.start()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()

#with FileOperations('127.0.0.1', 1234) as c:
#    print(c.list_dir('.'))
#    c.write(r'.\test.txt', 'ab', b'XXX')
#    print(c.list_dir('.'))
#    c.delete(r'.\test.txt')
#    print(c.list_dir('.'))
