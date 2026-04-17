from __future__ import annotations

import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Callable, Optional


@dataclass
class CapturedPacket:
    direction: str
    src_addr: str
    dst_addr: str
    src_port: int
    dst_port: int
    seq_num: int
    ack_num: int
    syn: bool
    ack: bool
    rst: bool
    fin: bool
    psh: bool
    payload: bytes
    ip_id: Optional[int] = None
    native: Any = None

    @property
    def is_inbound(self) -> bool:
        return self.direction == "inbound"

    @property
    def is_outbound(self) -> bool:
        return self.direction == "outbound"


class TcpInjector(ABC):
    def __init__(self, src_ip: str, dst_ip: str, iface_name: Optional[str] = None):
        self.src_ip = src_ip
        self.dst_ip = dst_ip
        self.iface_name = iface_name or None

    @abstractmethod
    def run(self, on_packet: Callable[[CapturedPacket], None]):
        raise NotImplementedError

    @abstractmethod
    def pass_packet(self, packet: CapturedPacket):
        raise NotImplementedError

    @abstractmethod
    def send_fake_packet(self, packet: CapturedPacket, fake_payload: bytes, seq_num: int, ack_num: int):
        raise NotImplementedError


class WinDivertTcpInjector(TcpInjector):
    def __init__(self, src_ip: str, dst_ip: str, iface_name: Optional[str] = None):
        super().__init__(src_ip, dst_ip, iface_name)
        try:
            from pydivert import WinDivert
        except ImportError as exc:
            raise RuntimeError("pydivert is required for Windows packet capture") from exc

        w_filter = (
            "tcp and ("
            + f"(ip.SrcAddr == {self.src_ip} and ip.DstAddr == {self.dst_ip})"
            + " or "
            + f"(ip.SrcAddr == {self.dst_ip} and ip.DstAddr == {self.src_ip})"
            + ")"
        )
        self.w = WinDivert(w_filter)

    @staticmethod
    def _to_packet(packet) -> CapturedPacket:
        ip_layer = packet.ipv4 if packet.ipv4 else packet.ipv6
        return CapturedPacket(
            direction="inbound" if packet.is_inbound else "outbound",
            src_addr=packet.ip.src_addr,
            dst_addr=packet.ip.dst_addr,
            src_port=packet.tcp.src_port,
            dst_port=packet.tcp.dst_port,
            seq_num=packet.tcp.seq_num,
            ack_num=packet.tcp.ack_num,
            syn=packet.tcp.syn,
            ack=packet.tcp.ack,
            rst=packet.tcp.rst,
            fin=packet.tcp.fin,
            psh=packet.tcp.psh,
            payload=bytes(packet.tcp.payload),
            ip_id=getattr(ip_layer, "ident", None),
            native=packet,
        )

    def run(self, on_packet: Callable[[CapturedPacket], None]):
        with self.w:
            while True:
                on_packet(self._to_packet(self.w.recv(65575)))

    def pass_packet(self, packet: CapturedPacket):
        self.w.send(packet.native, False)

    def send_fake_packet(self, packet: CapturedPacket, fake_payload: bytes, seq_num: int, ack_num: int):
        native_packet = packet.native
        native_packet.tcp.psh = True
        native_packet.ip.packet_len = native_packet.ip.packet_len + len(fake_payload)
        native_packet.tcp.payload = fake_payload
        if native_packet.ipv4:
            native_packet.ipv4.ident = (native_packet.ipv4.ident + 1) & 0xFFFF
        native_packet.tcp.seq_num = seq_num
        native_packet.tcp.ack_num = ack_num
        self.w.send(native_packet, True)


class ScapyTcpInjector(TcpInjector):
    def __init__(self, src_ip: str, dst_ip: str, iface_name: Optional[str] = None):
        super().__init__(src_ip, dst_ip, iface_name)
        try:
            from scapy.all import IP, TCP, send, sniff
        except ImportError as exc:
            raise RuntimeError("scapy is required for macOS packet capture") from exc

        self._IP = IP
        self._TCP = TCP
        self._send = send
        self._sniff = sniff
        self._bpf_filter = f"tcp and host {self.src_ip} and host {self.dst_ip}"

    def _to_packet(self, packet) -> Optional[CapturedPacket]:
        if self._IP not in packet or self._TCP not in packet:
            return None

        ip_layer = packet[self._IP]
        tcp_layer = packet[self._TCP]
        if ip_layer.src == self.src_ip and ip_layer.dst == self.dst_ip:
            direction = "outbound"
        elif ip_layer.src == self.dst_ip and ip_layer.dst == self.src_ip:
            direction = "inbound"
        else:
            return None

        return CapturedPacket(
            direction=direction,
            src_addr=ip_layer.src,
            dst_addr=ip_layer.dst,
            src_port=tcp_layer.sport,
            dst_port=tcp_layer.dport,
            seq_num=tcp_layer.seq,
            ack_num=tcp_layer.ack,
            syn=bool(tcp_layer.flags & 0x02),
            ack=bool(tcp_layer.flags & 0x10),
            rst=bool(tcp_layer.flags & 0x04),
            fin=bool(tcp_layer.flags & 0x01),
            psh=bool(tcp_layer.flags & 0x08),
            payload=bytes(tcp_layer.payload),
            ip_id=getattr(ip_layer, "id", None),
            native=packet,
        )

    def run(self, on_packet: Callable[[CapturedPacket], None]):
        def handle_packet(packet):
            parsed_packet = self._to_packet(packet)
            if parsed_packet is not None:
                on_packet(parsed_packet)

        sniff_kwargs = {
            "filter": self._bpf_filter,
            "prn": handle_packet,
            "store": False,
        }
        if self.iface_name:
            sniff_kwargs["iface"] = self.iface_name
        self._sniff(**sniff_kwargs)

    def pass_packet(self, packet: CapturedPacket):
        # Passive capture on macOS does not require reinjecting the original packet.
        return None

    def send_fake_packet(self, packet: CapturedPacket, fake_payload: bytes, seq_num: int, ack_num: int):
        ip_packet = self._IP(src=packet.src_addr, dst=packet.dst_addr)
        if packet.ip_id is not None:
            ip_packet.id = (packet.ip_id + 1) & 0xFFFF

        tcp_packet = self._TCP(
            sport=packet.src_port,
            dport=packet.dst_port,
            flags="PA",
            seq=seq_num,
            ack=ack_num,
        )
        self._send(ip_packet / tcp_packet / fake_payload, verbose=False)


def build_tcp_injector(src_ip: str, dst_ip: str, iface_name: Optional[str] = None) -> TcpInjector:
    if sys.platform == "win32":
        return WinDivertTcpInjector(src_ip, dst_ip, iface_name)
    return ScapyTcpInjector(src_ip, dst_ip, iface_name)
