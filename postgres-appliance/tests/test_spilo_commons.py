import importlib
import os
import unittest
from unittest.mock import patch

import spilo_commons


class ExtensionConfigurationTest(unittest.TestCase):
    def test_pg_textsearch_opt_in_and_version_gate(self):
        for enabled in ('false', 'true'):
            with patch.dict(os.environ, {'ENABLE_PG_TEXTSEARCH': enabled}):
                importlib.reload(spilo_commons)
                for version in range(14, 20):
                    for allowlist in (False, True):
                        with self.subTest(enabled=enabled, version=version, allowlist=allowlist):
                            result = spilo_commons.append_extensions('pg_stat_statements', version, allowlist).split(',')
                            self.assertIn('pg_stat_statements', result)
                            self.assertEqual('pg_textsearch' in result, enabled == 'true' and version in (17, 18))
                            if enabled == 'true':
                                adjusted = spilo_commons.adjust_extensions('pg_textsearch', version, allowlist)
                                self.assertEqual(adjusted, 'pg_textsearch' if version in (17, 18) else '')
        importlib.reload(spilo_commons)


if __name__ == '__main__':
    unittest.main()
