/**
	TCP/UDP connection and server handling.

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.net;

public import vibe.core.stream;

import vibe.core.driver;
import vibe.core.log;

import core.sys.posix.netinet.in_;
import core.time;
import std.exception;
import std.functional;
import std.string;
version(Windows) import std.c.windows.winsock;


/**
	Resolves the given host name/IP address string.

	Setting use_dns to false will only allow IP address strings but also guarantees
	that the call will not block.
*/
NetworkAddress resolveHost(string host, ushort address_family = AF_UNSPEC, bool use_dns = true)
{
	return getEventDriver().resolveHost(host, address_family, use_dns);
}


/**
	Starts listening on the specified port.

	'connection_callback' will be called for each client that connects to the
	server socket. Each new connection gets its own fiber. The stream parameter
	then allows to perform blocking I/O on the client socket.

	The address parameter can be used to specify the network
	interface on which the server socket is supposed to listen for connections.
	By default, all IPv4 and IPv6 interfaces will be used.
*/
TCPListener[] listenTCP(ushort port, void delegate(TCPConnection stream) connection_callback, TCPListenOptions options = TCPListenOptions.defaults)
{
	TCPListener[] ret;
	try ret ~= listenTCP(port, connection_callback, "::", options);
	catch (Exception e) logDiagnostic("Failed to listen on \"::\": %s", e.msg);
	try ret ~= listenTCP(port, connection_callback, "0.0.0.0", options);
	catch (Exception e) logDiagnostic("Failed to listen on \"0.0.0.0\": %s", e.msg);
	enforce(ret.length > 0, format("Failed to listen on all interfaces on port %s", port));
	return ret;
}
/// ditto
TCPListener listenTCP(ushort port, void delegate(TCPConnection stream) connection_callback, string address, TCPListenOptions options = TCPListenOptions.defaults)
{
	return getEventDriver().listenTCP(port, connection_callback, address, options);
}

/// Deprecated compatibility alias
deprecated("Please use listenTCP instead.") alias listenTcp = listenTCP;

/**
	Starts listening on the specified port.

	This function is the same as listenTCP but takes a function callback instead of a delegate.
*/
TCPListener[] listenTCP_s(ushort port, void function(TCPConnection stream) connection_callback, TCPListenOptions options = TCPListenOptions.defaults)
{
	return listenTCP(port, toDelegate(connection_callback), options);
}
/// ditto
TCPListener listenTCP_s(ushort port, void function(TCPConnection stream) connection_callback, string address, TCPListenOptions options = TCPListenOptions.defaults)
{
	return listenTCP(port, toDelegate(connection_callback), address, options);
}

/// Deprecated compatibility alias
deprecated("Please use listenTCP_s instead.") alias listenTcpS = listenTCP_s;

/**
	Establishes a connection to the given host/port.
*/
TCPConnection connectTCP(string host, ushort port)
{	
	NetworkAddress addr = resolveHost(host);
	addr.port = port; 
	return getEventDriver().connectTCP(addr);
}

TCPConnection connectTCP(NetworkAddress addr) {
	return getEventDriver().connectTCP(addr);
}

/// Deprecated compatibility alias
deprecated("Please use connectTCP instead.")alias connectTcp = connectTCP;


/**
	Creates a bound UDP socket suitable for sending and receiving packets.
*/
UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
{
	return getEventDriver().listenUDP(port, bind_address);
}

/// Deprecated compatibility alias
deprecated("Please use listenUDP instead.")alias listenUdp = listenUDP;


/**
	Represents a network/socket address.
*/
struct NetworkAddress {

	pure:
	/** Returns a string Representation of the IPAddress */
	@property string toString()
	{
		import std.conv:to;
		import std.string:format;

		switch (this.family) {
			default: assert(false, "toString() called for invalid address family.");

			case AF_INET:  
						_in_addr ip;
						ip.s4_addr32 = addr_ip4.sin_addr.s_addr;
						return format("%d.%d.%d.%d", 	
				            ip.s4_addr8[0],
							ip.s4_addr8[1],
							ip.s4_addr8[2],
							ip.s4_addr8[3]
						);
			
			case AF_INET6: return format("%x:%x:%x:%x:%x:%x:%x:%x",
						addr_ip6.sin6_addr.s6_addr16[0],
						addr_ip6.sin6_addr.s6_addr16[1],
						
						addr_ip6.sin6_addr.s6_addr16[2],
						addr_ip6.sin6_addr.s6_addr16[3],

						addr_ip6.sin6_addr.s6_addr16[4],
						addr_ip6.sin6_addr.s6_addr16[5],

						addr_ip6.sin6_addr.s6_addr16[6],
						addr_ip6.sin6_addr.s6_addr16[7]
						);
		}
		 
	}
	unittest {
		assert (NetworkAddress.init.toString()=="0.0.0.0");
	}
	pure nothrow:

	private union {
		sockaddr addr;
		sockaddr_in addr_ip4;
		sockaddr_in6 addr_ip6;
	}

	/** Family (AF_) of the socket address.
	*/
	@property ushort family() const { return addr.sa_family; }
	/// ditto
	@property void family(ushort val) { addr.sa_family = cast(ubyte)val; }

	/** The port in host byte order.
	*/
	@property ushort port()
	const {
		switch (this.family) {
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: return ntoh(addr_ip4.sin_port);
			case AF_INET6: return ntoh(addr_ip6.sin6_port);
		}
	}
	/// ditto
	@property void port(ushort val)
	{
		switch (this.family) {
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: addr_ip4.sin_port = hton(val); break;
			case AF_INET6: addr_ip6.sin6_port = hton(val); break;
		}
	}

	/** A pointer to a sockaddr struct suitable for passing to socket functions.
	*/
	@property inout(sockaddr)* sockAddr() inout { return &addr; }

	/** Size of the sockaddr struct that is returned by sockAddr().
	*/
	@property int sockAddrLen()
	const {
		switch (this.family) {
			default: assert(false, "sockAddrLen() called for invalid address family.");
			case AF_INET: return addr_ip4.sizeof;
			case AF_INET6: return addr_ip6.sizeof;
		}
	}

	@property inout(sockaddr_in)* sockAddrInet4() inout
		in { assert (family == AF_INET); }
		body { return &addr_ip4; }

	@property inout(sockaddr_in6)* sockAddrInet6() inout
		in { assert (family == AF_INET6); }
		body { return &addr_ip6; }
}


/**
	Represents a single TCP connection.
*/
interface TCPConnection : ConnectionStream {
	/// Used to disable Nagle's algorithm.
	@property void tcpNoDelay(bool enabled);
	/// ditto
	@property bool tcpNoDelay() const;

	/// Controls the read time out after which the connection is closed automatically.
	@property void readTimeout(Duration duration);
	/// ditto
	@property Duration readTimeout() const;

	/// Returns the IP address of the connected peer.
	@property string peerAddress() const;

	/// The local/bind address of the underlying socket.
	@property NetworkAddress localAddress() const;

	/// The address of the connected peer.
	@property NetworkAddress remoteAddress() const;
}

/// Deprecated compatibility alias
deprecated("Please use TCPConnection instead.")alias TcpConnection = TCPConnection;


/**
	Represents a listening TCP socket.
*/
interface TCPListener {
	/// Stops listening and closes the socket.
	void stopListening();
}

/// Deprecated compatibility alias
deprecated("Please use TCPListener instead.")alias TcpListener = TCPListener;


/**
	Represents a bound and possibly 'connected' UDP socket.
*/
interface UDPConnection {
	/** Returns the address to which the UDP socket is bound.
	*/
	@property string bindAddress() const;

	/** Determines if the socket is allowed to send to broadcast addresses.
	*/
	@property bool canBroadcast() const;
	/// ditto
	@property void canBroadcast(bool val);

	/// The local/bind address of the underlying socket.
	@property NetworkAddress localAddress() const;

	/** Locks the UDP connection to a certain peer.

		Once connected, the UDPConnection can only communicate with the specified peer.
		Otherwise communication with any reachable peer is possible.
	*/
	void connect(string host, ushort port);
	/// ditto
	void connect(NetworkAddress address);

	/** Sends a single packet.

		If peer_address is given, the packet is send to that address. Otherwise the packet
		will be sent to the address specified by a call to connect().
	*/
	void send(in ubyte[] data, in NetworkAddress* peer_address = null);

	/** Receives a single packet.

		If a buffer is given, it must be large enough to hold the full packet.
	*/
	ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null);
}

/// Deprecated compatibility alias
deprecated("Please use UDPConnection instead.")alias UdpConnection = UDPConnection;


enum TCPListenOptions {
	defaults = 0,
	distribute = 1<<0
}

/// Deprecated compatibility alias
deprecated("Please use TCPListenOptions instead.")alias TcpListenOptions = TCPListenOptions;

private pure nothrow {
	import std.bitmanip;
	
	ushort ntoh(ushort val)
	{
		version (LittleEndian) return swapEndian(val);
		else version (BigEndian) return val;
		else static assert(false, "Unknown endianness.");
	}

	ushort hton(ushort val)
	{
		version (LittleEndian) return swapEndian(val);
		else version (BigEndian) return val;
		else static assert(false, "Unknown endianness.");
	}

	struct _in_addr
	{
		union
		{
			uint8_t[4] s4_addr8;
			uint16_t[2] s4_addr16;
			uint32_t[1] s4_addr32;
		}
	}
}
