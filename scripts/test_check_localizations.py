"""Regression tests for the localization guard; run with python3 -m unittest discover -s scripts -p 'test_check_localizations.py'."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('localizations', Path(__file__).with_name('check-localizations.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class LocalizationSourceTests(unittest.TestCase):
    def check(self, source):
        return checker.source_errors(source, {'settings.language': 'Language'}, {'settings'})

    def test_detects_missing_stable_key(self):
        self.assertIn('unknown localization key', self.check('Text("settings.langauge")')[0][1])

    def test_detects_chinese_lookup_keys(self):
        self.assertIn('stable key', self.check('AppLocalization.string("语言")')[0][1])
        self.assertIn('stable key', self.check('Text("语言")')[0][1])

    def test_preserves_user_data_comments_and_protocol_identifiers(self):
        self.assertEqual(self.check('let title = "用户输入"\n// Text("中文注释")\nlet id = "settings.window"'), [])

    def test_protocol_identifier_is_not_a_valid_display_key(self):
        self.assertTrue(self.check('Text("settings.window")'))

    def test_known_key_and_verbatim_content(self):
        self.assertEqual(self.check('Text("settings.language")\nText(verbatim: "用户内容")'), [])


if __name__ == '__main__':
    unittest.main()
