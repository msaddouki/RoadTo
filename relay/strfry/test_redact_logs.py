from redact_logs import redact


def test_connection_lines_lose_the_address():
    assert redact("[Websocket] INFO| [1] Connect from 172.18.0.1 compression=Y sliding=Y\n") == (
        "[Websocket] INFO| [1] Connect from [address] compression=Y sliding=Y\n"
    )
    assert redact("[2] Disconnect from 2001:db8::7 (0/-) UP: 310b\n") == "[2] Disconnect from [address] (0/-) UP: 310b\n"


def test_any_address_elsewhere_is_removed():
    assert redact("rate limit for 203.0.113.9 reached") == "rate limit for [address] reached"
    assert redact("peer fe80::1ff:fe23:4567:890a dropped") == "peer [address] dropped"


def test_other_lines_are_left_alone():
    for line in (
        "Inserted event. id=000b0ccd7993b61d6c64942179b767d0ca9acf3f297da14bc98239992915de1c levId=1",
        "2026-10-12 13:48:17.226 (   0.060s) [Websocket       ]INFO| Started websocket server",
        "peer: Connecting to ws://relay-b:7777",
        "strfry 1.1.3 nofiles = 65536",
        "took 12:30:45 to sync",
    ):
        assert redact(line) == line
