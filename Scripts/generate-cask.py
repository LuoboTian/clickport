#!/usr/bin/env python3
"""Generate a local Homebrew Cask; never upload or install anything (FR-13)."""

import argparse
import hashlib
import re
from pathlib import Path
from urllib.parse import urlsplit


def https_url(value):
    try:
        parsed = urlsplit(value)
        valid = (parsed.scheme == "https" and parsed.hostname
                 and not parsed.username and not parsed.password
                 and not parsed.query and not parsed.fragment
                 and not any(character.isspace() for character in value)
                 and all(ord(character) >= 32 for character in value))
    except ValueError:
        valid = False
    if not valid:
        raise argparse.ArgumentTypeError("Use an HTTPS URL without credentials, query or fragment")
    return value


def ruby_string(value):
    # Single quotes keep URL contents literal, including Ruby interpolation syntax.
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dmg", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--download-url", type=https_url, required=True)
    parser.add_argument("--homepage", type=https_url, required=True)
    parser.add_argument("--output", type=Path, default=Path("build/homebrew/clickport.rb"))
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", args.version):
        parser.error("Version must use major.minor.patch, optionally with a prerelease suffix")
    if not args.dmg.is_file() or args.dmg.suffix.lower() != ".dmg":
        parser.error("DMG must be an existing .dmg file")
    if args.output.name != "clickport.rb":
        parser.error("Output filename must be clickport.rb")
    digest = hashlib.sha256()
    with args.dmg.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    content = f'''# Generated locally; publish only after release verification.
cask "clickport" do
  version {ruby_string(args.version)}
  sha256 "{digest.hexdigest()}"

  url {ruby_string(args.download_url)}
  name "Clickport"
  desc "Finder context menu actions and file utilities"
  homepage {ruby_string(args.homepage)}

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Clickport.app"

  uninstall quit: "org.clickport.app"
end
'''
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    print(f"Generated local Cask: {args.output}")
    print("No upload, installation, notarization or release validation was performed.")


if __name__ == "__main__":
    main()
