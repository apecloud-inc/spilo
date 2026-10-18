#!/usr/bin/env python3
"""Execute with GNU printenv/sed, as shipped in the Linux Spilo image."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


RUN = Path(__file__).resolve().parents[1] / 'runit' / 'patroni' / 'run'


class PatroniEnvironmentTest(unittest.TestCase):
    def test_environment_reaches_patroni_through_service_filter(self):
        retained = dict(NODE_NAME='worker-1', PATRONI_NAME='database-0',
                        POSTGRES_HOST_NETWORK_PORT='5433', POLARDB_LICENSE_REQUIRED='true',
                        POD_IP='192.0.2.10', POD_NAMESPACE='database',
                        KUBERNETES_SERVICE_HOST='192.0.2.1', HOSTNAME='host-worker-1')
        removed = dict(PGPASSWORD='dummy-password', AWS_SECRET_ACCESS_KEY='dummy-key',
                       PATRONI_SUPERUSER_PASSWORD='dummy-patroni-password',
                       PATRONI_OTHER='dummy-other', NODE_NAME_EXTRA='dummy-extra',
                       POLARDB_LICENSE_REQUIRED_EXTRA='dummy-extra')
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            # Only isolate host-specific setup; execute the original environment filter and exec.
            service = temporary / 'run'
            service.write_text(RUN.read_text().replace('/proc/self/coredump_filter',
                                                       str(temporary / 'coredump_filter')))
            for name in ('chrt', 'chpst'):
                stub = temporary / name
                stub.write_text('#!/bin/sh\nexit 1\n')
                stub.chmod(0o755)
            sed = shutil.which('gsed') or shutil.which('sed')
            self.assertIsNotNone(sed, 'GNU sed is required, as in the Spilo image')
            (temporary / 'sed').symlink_to(sed)
            patroni = temporary / 'patroni'
            patroni.write_text('#!{}\nimport json, os, sys\n'
                               'print(json.dumps(dict(environment=dict(os.environ), args=sys.argv[1:])))\n'
                               .format(sys.executable))
            patroni.chmod(0o755)
            environment = dict(retained, **removed, PATH=directory + ':/usr/bin:/bin',
                               HOME='/controlled-home')
            result = subprocess.run(['/bin/sh', '-e', str(service)], env=environment,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            received = json.loads(result.stdout)
            for name, value in retained.items():
                with self.subTest(retained=name):
                    self.assertEqual(received['environment'].get(name), value)
            for name in removed:
                with self.subTest(removed=name):
                    self.assertNotIn(name, received['environment'])
            self.assertEqual(received['environment']['HOME'], '/home/postgres')
            self.assertEqual(received['args'], ['/home/postgres/postgres.yml'])


if __name__ == '__main__':
    unittest.main()
