using Godot;
using System;
using System.Net;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Net.Sockets;

public partial class HttpServer : Node
{
	private TcpListener _listener;
	private Thread _listenerThread;
	private volatile bool _running = false;
	private const int HTTP_PORT = 8080;

	// Cached on the main thread in _Ready(); served read-only from worker threads.
	private byte[] _indexHtmlBytes;

	public override void _Ready()
	{
		// Load index.html using Godot's virtual filesystem so this works in both
		// the editor (res:// → project dir) and packaged exports (res:// → PCK).
		using var fa = FileAccess.Open("res://assets/mobile_client/index.html", FileAccess.ModeFlags.Read);
		if (fa != null)
			_indexHtmlBytes = fa.GetBuffer((long)fa.GetLength());
		else
			GD.PushError("HttpServer: could not load res://assets/mobile_client/index.html");
		StartServer();
	}

	private void StartServer()
	{
		try
		{
			// TcpListener on IPAddress.Any binds 0.0.0.0 — works on macOS,
			// Windows, and Linux without elevated privileges or URL ACLs.
			_listener = new TcpListener(IPAddress.Any, HTTP_PORT);
			_listener.Start();
			_running = true;
			_listenerThread = new Thread(ListenerLoop) { IsBackground = true };
			_listenerThread.Start();
			GD.Print($"HttpServer: listening on 0.0.0.0:{HTTP_PORT}");
			try
			{
				foreach (var ip in GetLocalIPv4Addresses())
				{
					GD.Print($"HttpServer: http://{ip}:{HTTP_PORT}/mobile_client/index.html");
					GD.Print($"HttpServer: ws://{ip}:9090");
				}
			}
			catch (Exception) { }
		}
		catch (Exception e)
		{
			GD.PushError($"HttpServer: failed to start: {e.Message}");
		}
	}

	private void ListenerLoop()
	{
		while (_running)
		{
			try
			{
				var client = _listener.AcceptTcpClient();
				// Handle each request on a thread-pool thread so the accept
				// loop stays responsive.
				ThreadPool.QueueUserWorkItem(_ => HandleClient(client));
			}
			catch (SocketException) { break; }
			catch (Exception e)
			{
				GD.PrintErr($"HttpServer listener error: {e}");
			}
		}
	}

	private void HandleClient(TcpClient client)
	{
		try
		{
			using var stream = client.GetStream();
			stream.ReadTimeout = 5000;

			// Read the HTTP request line (e.g. "GET /path HTTP/1.1\r\n...")
			var buffer = new byte[4096];
			int bytesRead = stream.Read(buffer, 0, buffer.Length);
			if (bytesRead == 0) return;

			var requestText = Encoding.UTF8.GetString(buffer, 0, bytesRead);
			var firstLine = requestText.Split('\n')[0].Trim();
			var parts = firstLine.Split(' ');
			if (parts.Length < 2) return;

			var path = parts[1];
			// Strip query string for route matching
			var routePath = path.Contains('?') ? path.Substring(0, path.IndexOf('?')) : path;

			GD.Print($"HttpServer: {parts[0]} {path}");

			if (routePath == "/")
			{
				var location = path.Contains('?')
					? "/mobile_client/index.html" + path.Substring(path.IndexOf('?'))
					: "/mobile_client/index.html";
				WriteResponse(stream, 303, "text/html", null, location);
				return;
			}

			if (routePath == "/mobile_client/index.html")
			{
				if (_indexHtmlBytes == null)
				{
					WriteResponse(stream, 404, "text/plain", Encoding.UTF8.GetBytes("Not Found"));
					return;
				}
				WriteResponse(stream, 200, "text/html; charset=utf-8", _indexHtmlBytes);
				return;
			}

			WriteResponse(stream, 404, "text/plain", Encoding.UTF8.GetBytes("Not Found"));
		}
		catch (Exception e)
		{
			GD.PrintErr($"HttpServer: error handling request: {e.Message}");
		}
		finally
		{
			try { client.Close(); } catch { }
		}
	}

	private static void WriteResponse(NetworkStream stream, int statusCode, string contentType, byte[] body, string redirectLocation = null)
	{
		var statusText = statusCode switch
		{
			200 => "OK",
			303 => "See Other",
			404 => "Not Found",
			_ => "Error"
		};
		var sb = new StringBuilder();
		sb.Append($"HTTP/1.1 {statusCode} {statusText}\r\n");
		sb.Append($"Content-Type: {contentType}\r\n");
		if (redirectLocation != null)
			sb.Append($"Location: {redirectLocation}\r\n");
		sb.Append($"Content-Length: {body?.Length ?? 0}\r\n");
		sb.Append("Connection: close\r\n");
		sb.Append("\r\n");

		var header = Encoding.UTF8.GetBytes(sb.ToString());
		stream.Write(header, 0, header.Length);
		if (body != null && body.Length > 0)
			stream.Write(body, 0, body.Length);
	}

	private List<string> GetLocalIPv4Addresses()
	{
		var list = new List<string>();
		try
		{
			var host = Dns.GetHostEntry(Dns.GetHostName());
			foreach (var addr in host.AddressList)
			{
				if (addr.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(addr))
					list.Add(addr.ToString());
			}
		}
		catch { }
		return list;
	}

	public override void _ExitTree()
	{
		_running = false;
		try { _listener?.Stop(); } catch { }
		try { _listenerThread?.Join(1000); } catch { }
	}
}
