#!/usr/bin/env python3
"""Removes client addresses from strfry's logs before they leave the
container (the plan: relay logs without IP).

strfry logs each connection as "Connect from <ip>" and "Disconnect from <ip>".
Every line passes through here; IPv4 and IPv6 addresses are replaced, as
well as whatever follows "from" in connection lines (e.g. a forwarded
address). Lines are flushed one by one so logs stay live.
"""

import re
import sys

_CONNECTION = re.compile(r"\b((?:Dis)?[Cc]onnect(?:ion)? from) \S+")
_IPV4 = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
# Hex groups separated by colons, compressed ("::") or with at least five
# colons, so that times such as 13:48:17 are left alone.
_IPV6 = re.compile(
    r"(?<![\w:.])(?=[0-9A-Fa-f:]*::|(?:[0-9A-Fa-f]{1,4}:){5})(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![\w:.])"
)


def redact(line: str) -> str:
    line = _CONNECTION.sub(r"\1 [address]", line)
    line = _IPV4.sub("[address]", line)
    return _IPV6.sub("[address]", line)


def main() -> None:
    for line in sys.stdin:
        sys.stdout.write(redact(line))
        sys.stdout.flush()


if __name__ == "__main__":
    main()
