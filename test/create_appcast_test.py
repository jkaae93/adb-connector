import base64
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


class AppcastTest(unittest.TestCase):
    def test_signed_appcast_has_exact_archive_and_signature(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            archive = folder / 'ADB-Connector-v1.1.0-macos.zip'
            archive.write_bytes(b'archive')
            output = folder / 'appcast.xml'
            signature = base64.b64encode(bytes(range(64))).decode()
            subprocess.run([sys.executable, 'scripts/create_appcast.py', '--tag', 'v1.1.0', '--build', '3', '--archive', str(archive), '--signature', signature, '--output', str(output)], check=True)
            root = ET.parse(output).getroot()
            enclosure = root.find('./channel/item/enclosure')
            self.assertIsNotNone(enclosure)
            self.assertEqual(enclosure.attrib['length'], '7')
            self.assertEqual(enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'], signature)
            self.assertTrue(enclosure.attrib['url'].endswith('/v1.1.0/ADB-Connector-v1.1.0-macos.zip'))

    def test_rejects_malformed_signature(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            archive = folder / 'ADB-Connector-v1.1.0-macos.zip'
            archive.write_bytes(b'archive')
            result = subprocess.run([sys.executable, 'scripts/create_appcast.py', '--tag', 'v1.1.0', '--build', '3', '--archive', str(archive), '--signature', 'invalid', '--output', str(folder / 'appcast.xml')], capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
