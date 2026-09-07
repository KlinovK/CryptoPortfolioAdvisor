import socket

import pytest


@pytest.fixture(autouse=True)
def default_suite_has_no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    def blocked_connect(_socket: socket.socket, address: object) -> None:
        raise AssertionError(f"Default tests must remain offline; socket attempted {address!r}.")

    monkeypatch.setattr(socket.socket, "connect", blocked_connect)
