import fcntl
import socket
import struct
import sys


def get_default_interface_ipv4(addr="8.8.8.8") -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((addr, 53))
    except OSError:
        return ""
    else:
        return s.getsockname()[0]
    finally:
        s.close()


def get_default_interface_ipv6(addr="2001:4860:4860::8888") -> str:
    s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    try:
        s.connect((addr, 53))
    except OSError:
        return ""
    else:
        return s.getsockname()[0]
    finally:
        s.close()


def _get_interface_ipv4(name: str) -> str:
    if sys.platform == "win32":
        return ""

    request = struct.pack("256s", name[:15].encode())
    code = 0xC0206921 if sys.platform == "darwin" else 0x8915
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        response = fcntl.ioctl(sock.fileno(), code, request)
    finally:
        sock.close()
    return socket.inet_ntoa(response[20:24])


def get_interface_name_by_ipv4(ipv4: str) -> str:
    if not ipv4 or sys.platform == "win32":
        return ""

    for _, name in socket.if_nameindex():
        try:
            if _get_interface_ipv4(name) == ipv4:
                return name
        except OSError:
            continue
    return ""


def configure_tcp_keepalive(sock: socket.socket, idle: int = 11, interval: int = 2, count: int = 3):
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)

    keepalive_idle = getattr(socket, "TCP_KEEPIDLE", None)
    if keepalive_idle is None:
        keepalive_idle = getattr(socket, "TCP_KEEPALIVE", None)

    for option, value in (
        (keepalive_idle, idle),
        (getattr(socket, "TCP_KEEPINTVL", None), interval),
        (getattr(socket, "TCP_KEEPCNT", None), count),
    ):
        if option is None:
            continue
        try:
            sock.setsockopt(socket.IPPROTO_TCP, option, value)
        except OSError:
            continue
