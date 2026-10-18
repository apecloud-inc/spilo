#!/usr/bin/env python3
import ast
import logging
import os
from pathlib import Path
import socket
import unittest
from unittest.mock import Mock, patch


# Load the real function without the image-only bootstrap dependencies.
SOURCE = Path(__file__).resolve().parents[1] / 'scripts' / 'configure_spilo.py'
FUNCTION = next(node for node in ast.parse(SOURCE.read_text()).body
                if isinstance(node, ast.FunctionDef) and node.name == 'get_instance_metadata')


class InstanceMetadataTest(unittest.TestCase):
    def setUp(self):
        self.namespace = dict(os=os, socket=socket, logging=logging, requests=Mock(),
                              USE_KUBERNETES=True, PROVIDER_GOOGLE='google',
                              PROVIDER_AWS='aws', PROVIDER_OPENSTACK='openstack')
        exec(compile(ast.Module(body=[FUNCTION], type_ignores=[]), str(SOURCE), 'exec'), self.namespace)
        self.metadata = self.namespace['get_instance_metadata']

    def test_kubernetes_pod_ip_does_not_resolve_hostname(self):
        for address in ('192.0.2.10', '2001:db8::10'):
            with self.subTest(address=address), patch.dict(os.environ, POD_IP=address), \
                    patch.object(socket, 'getaddrinfo', side_effect=socket.gaierror('unresolvable')) as dns:
                self.assertEqual(self.metadata('local')['ip'], address)
                dns.assert_not_called()

    def test_missing_or_empty_pod_ip_uses_dns(self):
        for pod_ip in (None, ''):
            for address in ('192.0.2.20', '2001:db8::20'):
                environment = {} if pod_ip is None else {'POD_IP': pod_ip}
                with self.subTest(pod_ip=pod_ip, address=address), patch.dict(os.environ, environment, clear=True), \
                        patch.object(socket, 'getaddrinfo', return_value=[(0, 0, 0, '', (address, 0))]) as dns:
                    self.assertEqual(self.metadata('local')['ip'], address)
                    dns.assert_called_once_with(socket.gethostname(), 0, socket.AF_UNSPEC, socket.SOCK_STREAM, 0)
                with patch.dict(os.environ, environment, clear=True), \
                        patch.object(socket, 'getaddrinfo', side_effect=socket.gaierror('unresolvable')):
                    self.assertRaises(socket.gaierror, self.metadata, 'local')

    def test_non_kubernetes_ignores_pod_ip(self):
        self.namespace['USE_KUBERNETES'] = False
        with patch.dict(os.environ, POD_IP='192.0.2.10'), \
                patch.object(socket, 'getaddrinfo', return_value=[(0, 0, 0, '', ('192.0.2.20', 0))]):
            self.assertEqual(self.metadata('local')['ip'], '192.0.2.20')
        with patch.dict(os.environ, POD_IP='192.0.2.10'), \
                patch.object(socket, 'getaddrinfo', side_effect=socket.gaierror('unresolvable')):
            self.assertRaises(socket.gaierror, self.metadata, 'local')

    def test_provider_metadata_keeps_kubernetes_address(self):
        requests = self.namespace['requests']
        requests.get.return_value.text = 'provider-value'
        requests.get.return_value.json.return_value = {'availability_zone': 'provider-zone', 'uuid': 'provider-id'}
        for provider in ('google', 'aws', 'openstack'):
            with self.subTest(provider=provider), patch.dict(os.environ, POD_IP='2001:db8::10'), \
                    patch.object(socket, 'getaddrinfo', side_effect=socket.gaierror('unresolvable')):
                metadata = self.metadata(provider)
                self.assertEqual(metadata['ip'], '2001:db8::10')
                self.assertEqual(metadata['id'], socket.gethostname())
                self.assertEqual(metadata['zone'], 'provider-zone' if provider == 'openstack' else 'provider-value')

    def test_non_kubernetes_provider_metadata_overrides_dns(self):
        self.namespace['USE_KUBERNETES'] = False
        requests = self.namespace['requests']
        requests.get.return_value.text = 'provider-value'
        requests.get.return_value.json.return_value = {'availability_zone': 'provider-zone', 'uuid': 'provider-id'}
        for provider in ('google', 'aws', 'openstack'):
            with self.subTest(provider=provider), patch.dict(os.environ, POD_IP='192.0.2.10'), \
                    patch.object(socket, 'getaddrinfo', return_value=[(0, 0, 0, '', ('192.0.2.20', 0))]):
                metadata = self.metadata(provider)
                self.assertEqual(metadata['ip'], '192.0.2.20' if provider == 'google' else 'provider-value')
                self.assertEqual(metadata['id'], 'provider-value')


if __name__ == '__main__':
    unittest.main()
