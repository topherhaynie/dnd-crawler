using Godot;
using System;
using System.Net;
using System.Text;
using System.IO;
using System.Threading;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Runtime.InteropServices;

public partial class HttpServer : Node
{
	private HttpListener _listener;
	private Thread _listenerThread;
	private volatile bool _running = false;
	private const int HTTP_PORT = 8080;

	public override void _Ready()
	{
		StartServer();
	}

	private void StartServer()
	{
		try
		{
			_listener = new HttpListener();
			// Listen on localhost. On Windows also add the wildcard prefix so LAN
			// clients can reach the server; the http://+:port/ syntax is a Windows
			// URL ACL reservation and throws HttpListenerException on macOS/Linux.
			_listener.Prefixes.Add($"http://localhost:{HTTP_PORT}/");
			if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
				_listener.Prefixes.Add($"http://+:{HTTP_PORT}/");
			_listener.Start();
			_running = true;
			_listenerThread = new Thread(ListenerLoop) { IsBackground = true };
			_listenerThread.Start();
			GD.Print($"HttpServer: listening on port {HTTP_PORT}");
			// Print accessible URLs for convenience (HTTP + WebSocket).
			try
			{
				var ips = GetLocalIPv4Addresses();
				foreach (var ip in ips)
				{
					GD.Print($"HttpServer: http://{ip}:{HTTP_PORT}/mobile_client/index.html");
					GD.Print($"HttpServer: ws://{ip}:9090");
				}
			}
			catch (Exception) { }
		}
		catch (Exception e)
		{
			GD.PushError($"HttpServer: failed to start HttpListener: {e.Message}");
		}
	}

	private void ListenerLoop()
	{
		while (_running)
		{
			try
			{
				var context = _listener.GetContext();
				HandleContext(context);
			}
			catch (HttpListenerException) { break; }
			catch (Exception e)
			{
				GD.PrintErr($"HttpServer listener error: {e}");
			}
		}
	}

	private void HandleContext(HttpListenerContext ctx)
	{
		var req = ctx.Request;
		var res = ctx.Response;
		var path = req.Url.AbsolutePath;
		GD.Print($"HttpServer: received request: {req.HttpMethod} {path}");

		try
		{
			if (path == "/")
			{
				res.StatusCode = 303;
				res.RedirectLocation = "/mobile_client/index.html";
				res.Close();
				return;
			}

			if (path == "/mobile_client/index.html")
			{
				// AppContext.BaseDirectory is stable in both editor and packaged exports
				// on all platforms. Directory.GetCurrentDirectory() is unreliable
				// inside a macOS .app bundle (cwd is typically "/").
				var localPath = Path.Combine(AppContext.BaseDirectory, "assets/mobile_client/index.html");
				if (!File.Exists(localPath))
				{
					res.StatusCode = 404;
					res.Close();
					return;
				}
				var bytes = File.ReadAllBytes(localPath);
				res.ContentType = "text/html";
				res.ContentLength64 = bytes.Length;
				res.OutputStream.Write(bytes, 0, bytes.Length);
				res.Close();
				return;
			}

			res.StatusCode = 404;
			res.Close();
		}
		catch (Exception e)
		{
			GD.PrintErr($"HttpServer: error handling request: {e}");
			try { res.StatusCode = 500; res.Close(); } catch { }
		}
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
				{
					list.Add(addr.ToString());
				}
			}
		}
		catch { }
		return list;
	}

	public override void _ExitTree()
	{
		_running = false;
		try
		{
			_listener?.Stop();
		}
		catch { }
		try { _listenerThread?.Join(1000); } catch { }
	}
}
