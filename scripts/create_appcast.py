#!/usr/bin/env python3
"""Create a Sparkle appcast for a signed GitHub release asset."""
import argparse
import base64
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--signature', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'v\d+\.\d+\.\d+', args.tag):
        parser.error('tag must have the form v1.2.3')
    if not re.fullmatch(r'[1-9]\d*', args.build):
        parser.error('build must be a positive integer')
    try:
        signature = base64.b64decode(args.signature, validate=True)
    except ValueError:
        parser.error('invalid EdDSA signature')
    if len(signature) != 64:
        parser.error('invalid EdDSA signature length')
    if not args.archive.is_file() or args.archive.stat().st_size == 0:
        parser.error('archive is missing or empty')
    if args.archive.name != f'ADB-Connector-{args.tag}-macos.zip':
        parser.error('archive name does not match the tag')

    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'ADB Connector'
    ET.SubElement(channel, 'language').text = 'ko'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'ADB Connector {args.tag}'
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = args.build
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = args.tag[1:]
    ET.SubElement(item, 'link').text = f'https://github.com/jkaae93/adb_connector/releases/tag/{quote(args.tag)}'
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/jkaae93/adb_connector/releases/download/{quote(args.tag)}/{quote(args.archive.name)}',
        f'{{{SPARKLE}}}edSignature': args.signature,
        'length': str(args.archive.stat().st_size),
        'type': 'application/octet-stream',
    })
    ET.indent(rss)
    ET.ElementTree(rss).write(args.output, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    main()
