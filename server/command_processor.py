from file_service import FileService
import pickle


class Processor:
    def __init__(self):
        self.file_svc = FileService()

    def handle_command(self, bin_cmd: bytes):
        print(f'{bin_cmd=}')
        cmd = pickle.loads(bin_cmd)
        method_name = cmd['method']
        method = getattr(self.file_svc, method_name, None)
        result = {}
        if method is None:
            result['error'] = ValueError(f'Method {method} is not implemented')
        else:
            try:
                result['result'] = method(*cmd.get('args', []), **cmd.get('kwargs', []))
            except Exception as e:
                result['error'] = e
        return pickle.dumps(result)
