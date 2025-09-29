from pytest import fixture
import subprocess
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
   
from client.client import FileOperations


@fixture
def server():
    p = subprocess.Popen(['.\\server\\server.exe', '--ip', '127.0.0.1', '--port', '1234'])
    yield
    p.terminate()


@fixture
def client():
    with FileOperations('127.0.0.1', 1234) as c:
        yield c


def test_list_dir(server, client, tmp_path):
    folder = tmp_path / 'test'
    folder.mkdir()
    result = client.list_dir(str(tmp_path))
    assert 'test' in result

def test_write_file(server, client, tmp_path):
    file_path = tmp_path / 'test.file'
    client.write(file_path, 'wb', b'tratata')
    with open(file_path, mode='rb') as f:
        data = f.read()
    assert data == b'tratata'

def test_get_hash_file_md5(server, client, tmp_path):
    file_path = tmp_path / 'test.file'
    client.write(file_path, 'wb', b'tratata')
    hash = client.get_hash(file_path, 'md5')
    assert hash == 'cb1d3a6249c2d223c620393fa6420868'

def test_get_hash_file_sha256(server, client, tmp_path):
    file_path = tmp_path / 'test.file'
    client.write(file_path, 'wb', b'tratata')
    hash = client.get_hash(file_path, 'sha256')
    assert hash == '4ad5921e53e07ed23774a08c5ab1e6da3686dba7c47b4d90c07fd68d5a6c679d'

def test_delete_file(server, client, tmp_path):
    file_path = tmp_path / 'test.file'
    with open(file_path, mode='wb') as f:
        pass
    client.delete(file_path)
    files = client.list_dir(tmp_path)
    assert 'test.file' not in files
