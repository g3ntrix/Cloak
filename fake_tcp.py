import asyncio
import socket
import sys
import threading
import time

from monitor_connection import MonitorConnection
from injecter import CapturedPacket, build_tcp_injector


class FakeInjectiveConnection(MonitorConnection):
    def __init__(self, sock: socket.socket, src_ip, dst_ip,
                 src_port, dst_port, fake_data: bytes, bypass_method: str, peer_sock: socket.socket):
        super().__init__(sock, src_ip, dst_ip, src_port, dst_port)
        self.fake_data = fake_data
        self.sch_fake_sent = False
        self.fake_sent = False
        self.t2a_event = asyncio.Event()
        self.t2a_msg = ""
        self.bypass_method = bypass_method
        self.peer_sock = peer_sock
        self.running_loop = asyncio.get_running_loop()
        self.fake_seq_num = -1
        self.fake_ack_num = -1


class FakeTcpInjector:
    def __init__(self, src_ip: str, dst_ip: str, connections: dict[tuple, FakeInjectiveConnection], iface_name=None):
        self.injector = build_tcp_injector(src_ip, dst_ip, iface_name)
        self.connections = connections

    def fake_send_thread(self, packet: CapturedPacket, connection: FakeInjectiveConnection):
        time.sleep(0.001)
        with connection.thread_lock:
            if not connection.monitor:
                return

            if connection.bypass_method == "wrong_seq":
                connection.fake_seq_num = (connection.syn_seq + 1 - len(connection.fake_data)) & 0xffffffff
                connection.fake_ack_num = (connection.syn_ack_seq + 1) & 0xffffffff
                connection.fake_sent = True
                self.injector.send_fake_packet(packet, connection.fake_data, connection.fake_seq_num,
                                               connection.fake_ack_num)
            else:
                sys.exit("not implemented method!")

    def on_unexpected_packet(self, packet: CapturedPacket, connection: FakeInjectiveConnection, info_m: str):
        print(info_m, packet)
        connection.sock.close()
        connection.peer_sock.close()
        connection.monitor = False
        connection.t2a_msg = "unexpected_close"
        connection.running_loop.call_soon_threadsafe(connection.t2a_event.set, )
        self.injector.pass_packet(packet)

    def on_inbound_packet(self, packet: CapturedPacket, connection: FakeInjectiveConnection):
        if connection.syn_seq == -1:
            self.on_unexpected_packet(packet, connection, "unexpected inbound packet, no syn sent!")
            return
        if packet.ack and packet.syn and (not packet.rst) and (not packet.fin) and (len(packet.payload) == 0):
            seq_num = packet.seq_num
            ack_num = packet.ack_num
            if connection.syn_ack_seq != -1 and connection.syn_ack_seq != seq_num:
                self.on_unexpected_packet(packet, connection,
                                          "unexpected inbound syn-ack packet, seq change! " + str(seq_num) + " " + str(
                                              connection.syn_ack_seq))
                return
            if ack_num != ((connection.syn_seq + 1) & 0xffffffff):
                self.on_unexpected_packet(packet, connection,
                                          "unexpected inbound syn-ack packet, ack not matched! " + str(
                                              ack_num) + " " + str(connection.syn_seq))
                return
            connection.syn_ack_seq = seq_num
            self.injector.pass_packet(packet)
            return
        if packet.ack and (not packet.syn) and (not packet.rst) and (not packet.fin) and (
                len(packet.payload) == 0) and connection.fake_sent:
            seq_num = packet.seq_num
            ack_num = packet.ack_num
            if connection.syn_ack_seq == -1 or ((connection.syn_ack_seq + 1) & 0xffffffff) != seq_num:
                self.on_unexpected_packet(packet, connection,
                                          "unexpected inbound ack packet, seq not matched! " + str(seq_num) + " " + str(
                                              connection.syn_ack_seq))
                return
            if ack_num != ((connection.syn_seq + 1) & 0xffffffff):
                self.on_unexpected_packet(packet, connection,
                                          "unexpected inbound ack packet, ack not matched! " + str(ack_num) + " " + str(
                                              connection.syn_seq))
                return

            connection.monitor = False
            connection.t2a_msg = "fake_data_ack_recv"
            connection.running_loop.call_soon_threadsafe(connection.t2a_event.set, )
            return
        self.on_unexpected_packet(packet, connection, "unexpected inbound packet")

    def on_outbound_packet(self, packet: CapturedPacket, connection: FakeInjectiveConnection):
        if connection.fake_sent and packet.payload == connection.fake_data and packet.seq_num == connection.fake_seq_num \
                and packet.ack_num == connection.fake_ack_num:
            return
        if connection.sch_fake_sent:
            self.on_unexpected_packet(packet, connection, "unexpected outbound packet, recv packet after fake sent!")
            return
        if packet.syn and (not packet.ack) and (not packet.rst) and (not packet.fin) and (len(packet.payload) == 0):
            seq_num = packet.seq_num
            ack_num = packet.ack_num
            if ack_num != 0:
                self.on_unexpected_packet(packet, connection, "unexpected outbound syn packet, ack_num is not zero!")
                return
            if connection.syn_seq != -1 and connection.syn_seq != seq_num:
                self.on_unexpected_packet(packet, connection, "unexpected outbound syn packet, seq not matched! " + str(
                    seq_num) + " " + str(connection.syn_seq))
                return
            connection.syn_seq = seq_num
            self.injector.pass_packet(packet)
            return
        if packet.ack and (not packet.syn) and (not packet.rst) and (not packet.fin) and (len(packet.payload) == 0):
            seq_num = packet.seq_num
            ack_num = packet.ack_num
            if connection.syn_seq == -1 or ((connection.syn_seq + 1) & 0xffffffff) != seq_num:
                self.on_unexpected_packet(packet, connection,
                                          "unexpected outbound ack packet, seq not matched! " + str(
                                              seq_num) + " " + str(connection.syn_seq))
                return
            if connection.syn_ack_seq == -1 or ack_num != ((connection.syn_ack_seq + 1) & 0xffffffff):
                self.on_unexpected_packet(packet, connection,
                                          "unexpected outbound ack packet, ack not matched! " + str(
                                              ack_num) + " " + str(connection.syn_ack_seq))
                return

            self.injector.pass_packet(packet)
            connection.sch_fake_sent = True
            threading.Thread(target=self.fake_send_thread, args=(packet, connection), daemon=True).start()
            return
        self.on_unexpected_packet(packet, connection, "unexpected outbound packet")

    def inject(self, packet: CapturedPacket):
        if packet.is_inbound:
            c_id = (packet.dst_addr, packet.dst_port, packet.src_addr, packet.src_port)
            try:
                connection = self.connections[c_id]
            except KeyError:
                self.injector.pass_packet(packet)
            else:
                with connection.thread_lock:
                    if not connection.monitor:
                        self.injector.pass_packet(packet)
                        return
                    self.on_inbound_packet(packet, connection)
        elif packet.is_outbound:
            c_id = (packet.src_addr, packet.src_port, packet.dst_addr, packet.dst_port)
            try:
                connection = self.connections[c_id]
            except KeyError:
                self.injector.pass_packet(packet)
            else:
                with connection.thread_lock:
                    if not connection.monitor:
                        self.injector.pass_packet(packet)
                        return
                    self.on_outbound_packet(packet, connection)
        else:
            sys.exit("impossible direction!")

    def run(self):
        self.injector.run(self.inject)
