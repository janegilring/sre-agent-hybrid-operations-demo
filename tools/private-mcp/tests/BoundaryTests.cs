using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using PrivateMcp;
using Xunit;

namespace PrivateMcpTests;

public sealed partial class BoundaryTests
{
    private static readonly BoundarySettings Settings = new()
    {
        TenantId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        Audience = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
        CallerClientId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"),
        CallerObjectId = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd"),
        Hostname = "mcp.example.test",
        CertificateThumbprint = new string('A', 40),
        ListenAddress = "192.0.2.4",
        AllowedSourceCidrs = ["198.51.100.0/27"],
        NodeIdentityEnabled = true,
        ReadCapabilitiesEnabled = true
    };

    [Theory]
    [InlineData("none", 401)]
    [InlineData("malformed", 401)]
    [InlineData("audience", 401)]
    [InlineData("audience-slash", 401)]
    [InlineData("issuer", 401)]
    [InlineData("expired", 401)]
    [InlineData("future", 401)]
    [InlineData("signature", 401)]
    [InlineData("unsigned", 401)]
    [InlineData("no-expiry", 401)]
    [InlineData("algorithm", 401)]
    [InlineData("client", 403)]
    [InlineData("object", 403)]
    [InlineData("tenant", 403)]
    [InlineData("role", 403)]
    [InlineData("no-role", 403)]
    [InlineData("duplicate-caller", 401)]
    [InlineData("delegated", 403)]
    [InlineData("version", 403)]
    public async Task AuthenticationDeniesInvalidCredentials(string mutation, int expected)
    {
        await using var host = await TestBoundary.Start();
        using var response = await host.Send("tools/list", new { }, mutation);
        Assert.Equal(expected, (int)response.StatusCode);
        Assert.True(Guid.TryParse(response.Headers.GetValues("X-Correlation-ID").Single(), out _));
        Assert.DoesNotContain("Bearer", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task ValidCallerCanInitializeAndDiscoverOnlyReadOnlyIdentity()
    {
        await using var host = await TestBoundary.Start();
        using var initialized = await host.Send("initialize", new
        {
            protocolVersion = "2025-11-25",
            capabilities = new { },
            clientInfo = new { name = "boundary-test", version = "1.0" }
        });
        Assert.Equal(HttpStatusCode.OK, initialized.StatusCode);
        var initialization = await ReadRpc(initialized);
        Assert.True(initialization.GetProperty("result").TryGetProperty("serverInfo", out _));
        using var response = await host.Send("tools/list", new { });
        var rpc = await ReadRpc(response);
        var tools = rpc.GetProperty("result").GetProperty("tools").EnumerateArray().ToArray();
        Assert.Equal(4, tools.Length);
        Assert.Equal(new[] { "get_boundary_identity", "get_health_snapshot", "get_node_identity", "get_vm_checkpoint_inventory" },
            tools.Select(tool => tool.GetProperty("name").GetString()).Order().ToArray());
        Assert.All(tools, tool => Assert.True(tool.GetProperty("annotations").GetProperty("readOnlyHint").GetBoolean()));
    }

    [Fact]
    public async Task ValidToolCallReturnsBoundedIdentityAndMatchingAuditCorrelation()
    {
        await using var host = await TestBoundary.Start();
        using var response = await host.Send("tools/call",
            new { name = "get_boundary_identity", arguments = new { target = "LocalBox-Client" } });
        var rpc = await ReadRpc(response);
        var result = rpc.GetProperty("result");
        Assert.False(result.TryGetProperty("isError", out var error) && error.GetBoolean());
        var text = result.GetProperty("content")[0].GetProperty("text").GetString()!;
        Assert.Contains("LocalBox-Client", text);
        Assert.Contains(response.Headers.GetValues("X-Correlation-ID").Single(), text);
        Assert.True(Encoding.UTF8.GetByteCount(text) < 1024);
    }

    [Theory]
    [InlineData("AzLHOST1", "get_boundary_identity")]
    [InlineData("AzLHOST2", "get_boundary_identity")]
    [InlineData("LocalBox-Client; whoami", "get_boundary_identity")]
    [InlineData("LocalBox-Client", "run_command")]
    [InlineData("LocalBox-Client", "restart_node")]
    public async Task UnauthorizedTargetsAndActionsAreDenied(string target, string action)
    {
        await using var host = await TestBoundary.Start();
        using var response = await host.Send("tools/call", new { name = action, arguments = new { target } });
        var rpc = await ReadRpc(response);
        Assert.True(rpc.TryGetProperty("error", out _) ||
            rpc.GetProperty("result").GetProperty("isError").GetBoolean());
        Assert.DoesNotContain("whoami", rpc.ToString());
    }

    [Fact]
    public async Task AdditionalArgumentsAreRejectedNotIgnored()
    {
        await using var host = await TestBoundary.Start();
        using var response = await host.Send("tools/call", new
        {
            name = "get_boundary_identity",
            arguments = new { target = "LocalBox-Client", command = "never-run" }
        });
        var rpc = await ReadRpc(response);
        Assert.True(rpc.GetProperty("result").GetProperty("isError").GetBoolean());
    }

    [Fact]
    public async Task NodeIdentityUsesServerGeneratedCorrelationAndBoundedTypedResult()
    {
        var reader = new TestNodeIdentity();
        await using var host = await TestBoundary.Start(reader: reader);
        using var response = await host.Send("tools/call",
            new { name = "get_node_identity", arguments = new { target = "AzLHOST1" } });
        var rpc = await ReadRpc(response);
        var text = rpc.GetProperty("result").GetProperty("content")[0].GetProperty("text").GetString()!;
        Assert.Contains("AzLHOST1", text);
        Assert.Contains("Kerberos", text);
        Assert.Contains(response.Headers.GetValues("X-Correlation-ID").Single(), text);
        Assert.True(Encoding.UTF8.GetByteCount(text) < 1024);
        Assert.Equal(1, reader.Calls);
    }

    [Theory]
    [InlineData("AzLHOST3", false)]
    [InlineData("AzLHOST1.jumpstart.local", false)]
    [InlineData("LocalBox-Client", false)]
    [InlineData("AzLHOST1; whoami", false)]
    [InlineData("AzLHOST1", true)]
    public async Task NodeTargetAndAdditionalArgumentsNeverReachTransport(string target, bool extra)
    {
        var reader = new TestNodeIdentity();
        await using var host = await TestBoundary.Start(reader: reader);
        var arguments = new Dictionary<string, string> { ["target"] = target };
        if (extra) arguments["command"] = "never-run";
        using var response = await host.Send("tools/call", new { name = "get_node_identity", arguments });
        var rpc = await ReadRpc(response);
        Assert.True(rpc.GetProperty("result").GetProperty("isError").GetBoolean());
        Assert.Equal(0, reader.Calls);
    }

    [Fact]
    public async Task NodeFailureDoesNotDiscloseTransportErrors()
    {
        await using var host = await TestBoundary.Start(reader: new TestNodeIdentity(fail: true));
        using var response = await host.Send("tools/call",
            new { name = "get_node_identity", arguments = new { target = "AzLHOST1" } });
        var rpc = await ReadRpc(response);
        Assert.True(rpc.GetProperty("result").GetProperty("isError").GetBoolean());
        Assert.DoesNotContain("sensitive-transport-details", rpc.ToString());
    }

    [Fact]
    public async Task HostMismatchDoesNotClaimClientProof()
    {
        await using var host = await TestBoundary.Start(machine: "SomeOtherMachine");
        using var response = await host.Send("tools/call",
            new { name = "get_boundary_identity", arguments = new { target = "LocalBox-Client" } });
        var rpc = await ReadRpc(response);
        Assert.True(rpc.GetProperty("result").GetProperty("isError").GetBoolean());
        Assert.DoesNotContain("SomeOtherMachine", rpc.ToString());
    }

    [Theory]
    [InlineData("192.0.2.4", "https", "mcp.example.test", false)]
    [InlineData("203.0.113.2", "https", "mcp.example.test", false)]
    [InlineData("198.51.100.19", "http", "mcp.example.test", false)]
    [InlineData("198.51.100.19", "https", "wrong.example.test", false)]
    [InlineData("198.51.100.19", "https", "mcp.example.test", true)]
    public async Task NetworkHostAndBrowserGuardsFailClosed(string source, string scheme, string hostname, bool origin)
    {
        await using var host = await TestBoundary.Start(source);
        using var response = await host.Send("tools/list", new { }, scheme: scheme, hostname: hostname, origin: origin);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Theory]
    [InlineData("198.51.100.1", true)]
    [InlineData("198.51.100.19", true)]
    [InlineData("198.51.100.30", true)]
    [InlineData("::ffff:198.51.100.19", true)]
    [InlineData("198.51.100.0", false)]
    [InlineData("198.51.100.31", false)]
    [InlineData("198.51.100.32", false)]
    [InlineData("::1", false)]
    [InlineData("2001:db8::19", false)]
    [InlineData(null, false)]
    public void OnlyApprovedSubnetIsAccepted(string? source, bool expected) =>
        Assert.Equal(expected, BoundarySettings.Ipv4SourceCidr.Parse("198.51.100.0/27").Contains(source is null ? null : IPAddress.Parse(source)));

    [Fact]
    public void MissingProductionAudienceIsRejected() =>
        Assert.Throws<InvalidOperationException>(() => (Settings with { Audience = Guid.Empty }).Validate());

    private static async Task<JsonElement> ReadRpc(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var text = await response.Content.ReadAsStringAsync();
        if (response.Content.Headers.ContentType?.MediaType == "text/event-stream")
            text = text.Split('\n').First(line => line.StartsWith("data: "))[6..];
        return JsonDocument.Parse(text).RootElement.Clone();
    }

    private sealed class TestIdentity(string machine) : IHostIdentity
    {
        public string MachineName => machine;
    }

    private sealed class TestNodeIdentity(bool fail = false) : INodeIdentityReader
    {
        public int Calls { get; private set; }
        public Task<NodeIdentity> ReadAsync(Guid correlation, CancellationToken cancellationToken)
            => ReadAsync("AzLHOST1", correlation, cancellationToken);
        public Task<NodeIdentity> ReadAsync(string target, Guid correlation, CancellationToken cancellationToken)
        {
            Calls++;
            if (fail) throw new InvalidOperationException("sensitive-transport-details");
            return Task.FromResult(new NodeIdentity(target, target.ToUpperInvariant(), "jumpstart.local", "10.0.26100.0",
                @"jumpstart\svcMcpNodeRead", @"WinRM Virtual Users\WinRM VA_1_jumpstart_svcMcpNodeRead",
                false, "Kerberos", correlation.ToString("D")));
        }
    }

    [Theory]
    [InlineData("get_health_snapshot", "AzLHOST1", false)]
    [InlineData("get_health_snapshot", "localboxcluster;whoami", false)]
    [InlineData("get_vm_checkpoint_inventory", "OtherCluster", false)]
    [InlineData("get_vm_checkpoint_inventory", "localboxcluster", true)]
    public async Task CapabilityTargetAndExtraArgumentsNeverReachReader(string operation, string target, bool extra)
    {
        var reader = new TestCapabilityReader();
        await using var host = await TestBoundary.Start(capabilities: reader);
        var arguments = new Dictionary<string, string> { ["target"] = target };
        if (extra) arguments["ComputerName"] = "not-allowed";
        using var response = await host.Send("tools/call", new { name = operation, arguments });
        var rpc = await ReadRpc(response);
        Assert.True(rpc.GetProperty("result").GetProperty("isError").GetBoolean());
        Assert.Equal(0, reader.Calls);
    }

    [Theory]
    [InlineData("get_health_snapshot")]
    [InlineData("get_vm_checkpoint_inventory")]
    public async Task ApprovedCapabilityReturnsCorrelationAndUnknownNotHealthy(string operation)
    {
        var reader = new TestCapabilityReader();
        await using var host = await TestBoundary.Start(capabilities: reader);
        using var response = await host.Send("tools/call", new { name = operation, arguments = new { target = "localboxcluster" } });
        var rpc = await ReadRpc(response);
        var text = rpc.GetProperty("result").GetProperty("content")[0].GetProperty("text").GetString()!;
        Assert.Contains(response.Headers.GetValues("X-Correlation-ID").Single(), text);
        Assert.DoesNotContain("Healthy", text);
        Assert.Equal(1, reader.Calls);
    }

    private sealed class TestCapabilityReader : INodeCapabilityReader
    {
        public int Calls { get; private set; }
        public Task<HealthSnapshot> ReadHealthAsync(Guid correlation, CancellationToken cancellationToken)
        {
            Calls++;
            var nodes = NodeCapabilityReader.ApprovedNodes.Select(n => new NodeObservation<HealthRow>(n, "unsupported", "Unavailable", null)).ToArray();
            return Task.FromResult(NodeCapabilityReader.SummarizeHealth(nodes, correlation, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));
        }
        public Task<VmCheckpointInventory> ReadInventoryAsync(Guid correlation, CancellationToken cancellationToken)
        {
            Calls++;
            var nodes = NodeCapabilityReader.ApprovedNodes.Select(n => new NodeObservation<VmRow>(n, "unsupported", "Unavailable", null)).ToArray();
            return Task.FromResult(NodeCapabilityReader.SummarizeInventory(nodes, correlation, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));
        }
    }
    private sealed class TestBoundary(WebApplication app, HttpClient client, RSA rsa) : IAsyncDisposable
    {
        public static async Task<TestBoundary> Start(string source = "198.51.100.19", string machine = "LocalBox-Client",
            INodeIdentityReader? reader = null, INodeCapabilityReader? capabilities = null,
            IServerExecutor? serverExecutor = null, bool serversEnabled = false, BoundarySettings? configuration = null)
        {
            var rsa = RSA.Create(2048);
            var key = new RsaSecurityKey(rsa) { KeyId = "unit-test-only" };
            var builder = WebApplication.CreateBuilder();
            builder.Logging.ClearProviders();
            builder.WebHost.UseTestServer();
            var settings = (configuration ?? Settings) with { Servers = serversEnabled ? [ServerTestData.Target] : [] };
            BoundaryApplication.ConfigureServices(builder, settings);
            if (serverExecutor is not null) builder.Services.AddSingleton(serverExecutor);
            builder.Services.AddSingleton<IHostIdentity>(new TestIdentity(machine));
            builder.Services.AddSingleton<INodeIdentityReader>(reader ?? new TestNodeIdentity());
            builder.Services.AddSingleton<INodeCapabilityReader>(capabilities ?? new TestCapabilityReader());
            builder.Services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                var configuration = new OpenIdConnectConfiguration { Issuer = Settings.Issuer };
                configuration.SigningKeys.Add(key);
                options.ConfigurationManager = new StaticConfigurationManager<OpenIdConnectConfiguration>(configuration);
            });
            var app = builder.Build();
            app.Use((context, next) =>
            {
                context.Connection.RemoteIpAddress = IPAddress.Parse(source);
                return next(context);
            });
            BoundaryApplication.ConfigurePipeline(app, settings);
            await app.StartAsync();
            return new(app, app.GetTestClient(), rsa);
        }

        public Task<HttpResponseMessage> Send(string method, object parameters, string mutation = "",
            string scheme = "https", string hostname = "mcp.example.test", bool origin = false, string? forwardedSource = null)
        {
            var request = new HttpRequestMessage(HttpMethod.Post, $"{scheme}://{hostname}/mcp");
            request.Headers.Accept.ParseAdd("application/json");
            request.Headers.Accept.ParseAdd("text/event-stream");
            request.Headers.Add("MCP-Protocol-Version", "2025-11-25");
            if (origin) request.Headers.Add("Origin", $"https://{hostname}");
            if (forwardedSource is not null)
            {
                request.Headers.Add("X-Forwarded-For", forwardedSource);
                request.Headers.Add("Forwarded", $"for=\"{forwardedSource}\";proto=https;host={hostname}");
            }
            if (mutation != "none")
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateToken(mutation));
            request.Content = new StringContent(JsonSerializer.Serialize(
                new { jsonrpc = "2.0", id = 1, method, @params = parameters }), Encoding.UTF8, "application/json");
            return client.SendAsync(request);
        }

        private string CreateToken(string mutation)
        {
            if (mutation == "malformed") return "not-a-token";
            using var otherKey = RSA.Create(2048);
            var claims = new Dictionary<string, object>
            {
                ["tid"] = mutation == "tenant" ? Guid.Empty.ToString() : Settings.TenantId.ToString(),
                ["azp"] = mutation == "client" ? Guid.Empty.ToString() : Settings.CallerClientId.ToString(),
                ["oid"] = mutation == "object" ? Guid.Empty.ToString() : Settings.CallerObjectId.ToString(),
                ["ver"] = mutation == "version" ? "1.0" : "2.0",
                ["roles"] = new[] { mutation == "role" ? "Other.Read" : BoundarySettings.RequiredRole }
            };
            if (mutation == "delegated") claims["scp"] = "diagnostic.read";
            if (mutation == "no-role") claims.Remove("roles");
            if (mutation == "duplicate-caller")
                claims["azp"] = new[] { Settings.CallerClientId.ToString(), Settings.CallerClientId.ToString() };
            var now = DateTime.UtcNow;
            var descriptor = new SecurityTokenDescriptor
            {
                Issuer = mutation == "issuer" ? "https://wrong.example.test" : Settings.Issuer,
                Audience = mutation == "audience" ? Guid.Empty.ToString() :
                    mutation == "audience-slash" ? Settings.Audience + "/" : Settings.Audience.ToString(),
                Claims = claims,
                IssuedAt = now.AddHours(-2),
                NotBefore = mutation == "future" ? now.AddHours(1) : now.AddHours(-2),
                Expires = mutation == "no-expiry" ? null : mutation == "expired" ? now.AddHours(-1) : now.AddHours(2),
                SigningCredentials = mutation == "unsigned" ? null : mutation == "algorithm" ?
                    new SigningCredentials(new SymmetricSecurityKey(RandomNumberGenerator.GetBytes(32)), SecurityAlgorithms.HmacSha256) :
                    new SigningCredentials(
                    new RsaSecurityKey(mutation == "signature" ? otherKey : rsa) { KeyId = "unit-test-only" },
                    SecurityAlgorithms.RsaSha256)
            };
            return new JsonWebTokenHandler { SetDefaultTimesOnTokenCreation = false }.CreateToken(descriptor);
        }

        public async ValueTask DisposeAsync()
        {
            client.Dispose();
            await app.DisposeAsync();
            rsa.Dispose();
        }
    }
}
