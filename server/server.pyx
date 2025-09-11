import argparse
import socket
import threading
import time
import traceback
from datetime import datetime
from libc.stdio cimport printf
import traceback
import pickle
from collections import OrderedDict
from threading import Lock, Event
import os


class Record:
    def __init__(self):
        self.data = None
        self.ev = Event()


class Results:
    """
    Кэш для результатов
    """
    def __init__(self, max_size=100):
        self.cache = OrderedDict()
        self.lock = Lock()
        self.max_size = max_size

    def reserve(self, cmd_id):
        """
        Резервируем место в кеше по cmd_id
        """
        with self.lock:
            self.cache[cmd_id] = Record()
            if len(self.cache) > self.max_size:
                self.cache.popitem(last=False)
    
    def put_data(self, cmd_id, data):
        """
        Сохраняем результат выполнения команды
        """
        with self.lock:
            record = self.cache[cmd_id]
            record.data = data
            record.ev.set()
    
    def get_data(self, cmd_id, timeout=60):
        """
        Получаем результат выполнения команды из кеша
        """
        with self.lock:
            record = self.cache[cmd_id]
            if not record.ev.is_set():
                # если ev не установлен, занчит команда еще выполняется, пробуем подождать завершения
                if not record.ev.wait(timeout):
                    raise TimeoutError

        return record.data
    
    def in_cache(self, cmd_id):
        with self.lock:
            return cmd_id in self.cache


class FileService:
    """
    Файловый сервис
    """
    def list_dir(self, path):
        return os.listdir(path)
    
    def write_to_file(self, path, mode, data):
        with open(path, mode=mode) as f:
            f.write(data)
    
    def delete_file(self, path):
        os.remove(path)


class Processor:
    """
    Класс для обработки комманд
    """
    def __init__(self):
        self.file_svc = FileService()
        self.results = Results()

    def handle_command(self, bin_cmd: object):
        cmd = pickle.loads(bin_cmd)
        method_name = cmd['method']
        cmd_id = cmd['id']
        if self.results.in_cache(cmd_id):
            result = self.results.get_data(cmd_id, 2)
        else:
            self.results.reserve(cmd_id)
            method = getattr(self.file_svc, method_name, None)
            result = {}
            if method is None:
                result['error'] = ValueError(f'Method {method} is not implemented')
            else:
                try:
                    result['result'] = method(*cmd.get('args', []), **cmd.get('kwargs', {}))
                except Exception as e:
                    result['error'] = e
            self.results.put_data(cmd_id, result)
        return pickle.dumps(result)


cdef class CyTCPServer:
    cdef public str host
    cdef public int port
    cdef public int max_connections
    cdef public bint running
    cdef object server_socket
    cdef object processor
    cdef public int connection_count

    def __init__(self, processor, host="127.0.0.1", port=8888, max_connections=10):
        self.processor = processor
        self.host = host
        self.port = port
        self.max_connections = max_connections
        self.running = False
        self.server_socket = None
        self.connection_count = 0

    cpdef start(self):
        """Запуск TCP сервера"""
        cdef str address_str

        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(self.max_connections)
            self.server_socket.settimeout(1.0)

            address_str = f"{self.host}:{self.port}"
            printf(b"Server started on %s\n", address_str.encode('utf-8'))

            self.running = True
            self._accept_connections()

        except Exception as e:
            printf(b"Server error: %s\n", str(e).encode('utf-8'))

    cdef void _accept_connections(self):
        """Основной цикл принятия соединений"""
        cdef object client_socket
        cdef tuple client_address
        cdef str client_ip
        cdef int client_port

        while self.running:
            try:
                client_socket, client_address = self.server_socket.accept()
                client_ip, client_port = client_address

                self.connection_count += 1
                printf(b"New connection: %s:%d (total: %d)\n",
                      client_ip.encode('utf-8'), client_port, self.connection_count)

                # Обрабатываем клиента в отдельном потоке
                client_thread = threading.Thread(
                    target=self._handle_client,
                    args=(client_socket, client_ip, client_port)
                )
                client_thread.daemon = True
                client_thread.start()

            except KeyboardInterrupt:
                break
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    printf(b"Accept error: %s\n", str(e).encode('utf-8'))

    def _read_chunk(self, client_socket, size):
        return client_socket.recv(size)

    cdef void _handle_client(self, object client_socket, str client_ip, int client_port):
        """Обработка клиентского соединения"""
        cdef bytes received_data
        cdef str message
        cdef bytes response
        cdef bytes response_bytes
        cdef bytes chunk
        cdef int cmd_len = 0

        try:
            client_socket.settimeout(1.0)
            bin_cmd = bytes()

            while self.running:
                try:
                    # Читаем данные
                    if cmd_len == 0:
                        # читаем длину команды
                        chunk = self._read_chunk(client_socket, 8)
                        cmd_len = int.from_bytes(chunk, 'big')
                        continue
                    chunk = self._read_chunk(client_socket, 1024)
                    if not chunk:
                        break
                    bin_cmd += chunk
                    if cmd_len != len(bin_cmd):
                        continue
                    cmd_len = 0
                    response = self.processor.handle_command(bin_cmd)
                    bin_cmd = b''

                    # Отправляем ответ
                    client_socket.sendall(len(response).to_bytes(8, 'big') + response)
                except socket.timeout:
                    continue
                except Exception as e:
                    printf(b"Client error %s:%d: %s\n",
                          client_ip.encode('utf-8'), client_port, str(e).encode('utf-8'))
                    traceback.print_exc()
                    raise

        finally:
            # Всегда закрываем соединение
            try:
                client_socket.close()
            except:
                pass

            self.connection_count -= 1
            printf(b"Connection closed: %s:%d (active: %d)\n",
                  client_ip.encode('utf-8'), client_port, self.connection_count)

    cpdef void stop(self):
        """Корректная остановка сервера"""
        self.running = False

        if self.server_socket:
            try:
                # Создаем временное соединение чтобы выйти из accept
                temp_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                temp_socket.settimeout(0.1)
                temp_socket.connect((self.host, self.port))
                temp_socket.close()
            except:
                pass

            try:
                self.server_socket.close()
            except:
                pass

        printf(b"Server stopped\n")



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ip', required=True, type=str, help='address of interface to listen')
    parser.add_argument('--port', required=True, type=int, help='port to listen')
    args = parser.parse_args()
    server = CyTCPServer(Processor(), args.ip, args.port)
    server.start()


if __name__ == '__main__':
    main()
