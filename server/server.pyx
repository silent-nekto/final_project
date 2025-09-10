import argparse
import socket
import threading
import time
import traceback
from cpython cimport PyBytes_AsString
from command_processor import Processor
from datetime import datetime
from libc.stdio cimport printf


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

    cdef void _handle_client(self, object client_socket, str client_ip, int client_port):
        """Обработка клиентского соединения"""
        cdef bytes received_data
        cdef str message
        cdef str response
        cdef bytes response_bytes
        cdef unsigned char* c_data

        try:
            client_socket.settimeout(1.0)
            bin_cmd = bytes()

            while self.running:
                try:
                    # Читаем данные
                    received_data = client_socket.recv(1024)
                    c_data = <unsigned char*> received_data
                    if not received_data:
                        break
                    printf(b'Blob received 1: ' + c_data)
                    bin_cmd += c_data
                    if b'\n' not in bin_cmd:
                        continue
                    printf(b'Blob received 2: ' + bin_cmd)
                    response = self.processor.handle_command(PyBytes_AsString(bin_cmd[:-1]))
                    bin_cmd = b''

                    # Отправляем ответ
                    client_socket.sendall(response)

                except socket.timeout:
                    continue
                except Exception as e:
                    printf(b"Client error %s:%d: %s\n",
                          client_ip.encode('utf-8'), client_port, str(e).encode('utf-8'))
                    traceback.print_exc()
                    break

        finally:
            # Всегда закрываем соединение
            try:
                client_socket.close()
            except:
                pass

            self.connection_count -= 1
            printf(b"Connection closed: %s:%d (active: %d)\n",
                  client_ip.encode('utf-8'), client_port, self.connection_count)

    cdef str _process_message(self, str message, str client_ip, int client_port):
        """Обработка входящих сообщений (идемпотентные команды)"""
        cdef str cmd = message.upper().strip()

        if cmd == "HELLO":
            return f"Hello, {client_ip}:{client_port}!\n"

        elif cmd == "TIME":
            return f"Server time: {datetime.now().isoformat()}\n"

        elif cmd == "STATS":
            return f"Active connections: {self.connection_count}\n"

        elif cmd == "PING":
            return "PONG\n"

        elif cmd.startswith("ECHO "):
            return message[5:] + "\n"

        elif cmd == "QUIT":
            return "Goodbye!\n"

        elif cmd == "UPTIME":
            # Здесь можно добавить логику отслеживания времени работы
            return "Server is running\n"

        else:
            return f"Unknown command: '{message}'. Available: HELLO, TIME, STATS, PING, ECHO, QUIT, UPTIME\n"

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
    printf(b'Start server!')
    server = CyTCPServer(Processor(), args.ip, args.port)
    server.start()


if __name__ == '__main__':
    main()
