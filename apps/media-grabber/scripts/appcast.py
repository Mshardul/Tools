#!/usr/bin/env python3
"""Insert one signed disk image into the MediaGrabber appcast."""

import argparse
import re
import sys
from email.utils import formatdate

FEED = "https://mshardul.github.io/Tools/media-grabber/appcast.xml"
ITEM = re.compile(r"<item>(.*?)</item>", re.DOTALL)
FIELD = {
    "version": re.compile(r"<sparkle:version>([^<]*)</sparkle:version>"),
    "published": re.compile(r"<pubDate>([^<]*)</pubDate>"),
    "notes": re.compile(r"<sparkle:releaseNotesLink>([^<]*)</sparkle:releaseNotesLink>"),
    "url": re.compile(r'<enclosure url="([^"]*)"'),
    "signature": re.compile(r'sparkle:edSignature="([^"]*)"'),
    "length": re.compile(r'length="([^"]*)"'),
}


def parse_items(text):
    items = []
    for block in ITEM.findall(text):
        item = {
            name: (pattern.search(block).group(1) if pattern.search(block) else "")
            for name, pattern in FIELD.items()
        }
        if item["version"]:
            items.append(item)
    return items


def render(items):
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">',
        "  <channel>",
        "    <title>MediaGrabber</title>",
        f"    <link>{FEED}</link>",
        "    <description>MediaGrabber updates</description>",
        "    <language>en</language>",
    ]
    for item in items:
        lines.extend(
            [
                "    <item>",
                f"      <title>Version {item['version']}</title>",
                f"      <pubDate>{item['published']}</pubDate>",
                f"      <sparkle:version>{item['version']}</sparkle:version>",
                f"      <sparkle:shortVersionString>{item['version']}</sparkle:shortVersionString>",
                "      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>",
                (
                    f'      <enclosure url="{item["url"]}" '
                    f'sparkle:edSignature="{item["signature"]}" '
                    f'length="{item["length"]}" type="application/octet-stream"/>'
                ),
                f"      <sparkle:releaseNotesLink>{item['notes']}</sparkle:releaseNotesLink>",
                "    </item>",
            ]
        )
    lines.extend(["  </channel>", "</rss>", ""])
    return "\n".join(lines)


def upsert(items, item):
    kept = [existing for existing in items if existing["version"] != item["version"]]
    return [item] + kept


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    try:
        with open(args.existing, encoding="utf-8") as handle:
            current = handle.read()
    except FileNotFoundError:
        current = ""
    item = {
        "version": args.version,
        "url": args.url,
        "signature": args.signature,
        "length": args.length,
        "notes": args.notes,
        "published": formatdate(usegmt=True),
    }
    text = render(upsert(parse_items(current), item))
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(text)
    return 0


def self_test():
    first = render(
        upsert(
            [],
            {
                "version": "0.1.0",
                "url": "https://example.com/a.dmg",
                "signature": "abc",
                "length": "10",
                "notes": "https://example.com/notes",
                "published": "Thu, 01 Jan 2026 00:00:00 GMT",
            },
        )
    )
    parsed = parse_items(first)
    assert parsed[0]["version"] == "0.1.0"
    assert parsed[0]["signature"] == "abc"
    merged = upsert(
        parsed,
        {
            "version": "0.1.0",
            "url": "https://example.com/b.dmg",
            "signature": "def",
            "length": "11",
            "notes": "https://example.com/notes",
            "published": "Fri, 02 Jan 2026 00:00:00 GMT",
        },
    )
    assert len(merged) == 1
    assert merged[0]["signature"] == "def"
    again = parse_items(render(merged))
    assert again[0]["url"] == "https://example.com/b.dmg"
    print("appcast self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
