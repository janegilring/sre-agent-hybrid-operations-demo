using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using PrivateMcp;
using Xunit;
using Ipv4SourceCidr = PrivateMcp.BoundarySettings.Ipv4SourceCidr;

namespace PrivateMcpTests;

public sealed partial class BoundaryTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("*")]
    [InlineData("+")]
    [InlineData("0.0.0.0")]
    [InlineData("0.0.0.1")]
    [InlineData("255.255.255.255")]
    [InlineData("224.0.0.1")]
    [InlineData("240.0.0.1")]
    [InlineData("::")]
    [InlineData("::1")]
    [InlineData("::ffff:192.0.2.4")]
    [InlineData("192.0.2")]
    [InlineData("3221225988")]
    [InlineData("0xc0000204")]
    [InlineData("192.000.2.4")]
    [InlineData("192.0.2.004")]
    [InlineData("192.0.2.256")]
    [InlineData("192.0.2.4 ")]
    [InlineData("192.0.2.4/32")]
    [InlineData("mcp.example.test")]
    public void InvalidListenerConfigurationIsRejected(string? value) =>
        Assert.Throws<InvalidOperationException>(() => (Settings with { ListenAddress = value! }).Validate());

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("*")]
    [InlineData("0.0.0.0/0")]
    [InlineData("0.0.0.0/8")]
    [InlineData("224.0.0.0/4")]
    [InlineData("192.0.0.0/2")]
    [InlineData("198.51.100.1/27")]
    [InlineData("198.51.100.0")]
    [InlineData("198.51.100.0/31")]
    [InlineData("198.51.100.0/33")]
    [InlineData("198.51.100.0/-1")]
    [InlineData("198.51.100.0/+27")]
    [InlineData("198.51.100.0/027")]
    [InlineData("198.51.100.0/27/27")]
    [InlineData("198.51.100.0/27 ")]
    [InlineData("198.51.100.0 /27")]
    [InlineData("198.51.100/27")]
    [InlineData("198.051.100.0/27")]
    [InlineData("198.51.256.0/27")]
    [InlineData("0xc6336400/27")]
    [InlineData("3325256704/27")]
    [InlineData("2001:db8::/64")]
    [InlineData("::ffff:198.51.100.0/27")]
    public void InvalidSourceCidrRejectsWholeAllowlist(string? value) =>
        Assert.Throws<InvalidOperationException>(() =>
            (Settings with { AllowedSourceCidrs = ["198.51.100.0/27", value!] }).Validate());

    [Fact]
    public void NullEmptyAndOversizedAllowlistsAreRejected()
    {
        foreach (var cidrs in new string[][] { null!, [], Enumerable.Repeat("198.51.100.0/27", 17).ToArray() })
            Assert.Throws<InvalidOperationException>(() => (Settings with { AllowedSourceCidrs = cidrs }).Validate());
    }

    [Theory]
    [InlineData("ListenAddress")]
    [InlineData("AllowedSourceCidrs")]
    public void MissingRequiredJsonSettingFailsClosedThroughProductionBinder(string missing)
    {
        var values = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(JsonSerializer.Serialize(Settings))!;
        values.Remove(missing);
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(values)));
        var configuration = new ConfigurationBuilder().AddJsonStream(stream).Build();
        var settings = configuration.Get<BoundarySettings>()!;
        Assert.Throws<InvalidOperationException>(settings.Validate);
    }

    [Fact]
    public void ListenerIsConfigurableButPortRemainsFixed()
    {
        (Settings with { ListenAddress = "203.0.113.40" }).Validate();
        Assert.Throws<InvalidOperationException>(() => (Settings with { Port = 443 }).Validate());
    }

    [Fact]
    public void Slash27PreservesExactlyHostOneThroughThirty()
    {
        var network = Ipv4SourceCidr.Parse("198.51.100.0/27");
        for (var last = 0; last <= 255; last++)
            Assert.Equal(last is >= 1 and <= 30, network.Contains(IPAddress.Parse($"198.51.100.{last}")));
        Assert.False(default(Ipv4SourceCidr).Contains(IPAddress.Parse("198.51.100.19")));
    }

    [Theory]
    [InlineData("198.51.100.19", HttpStatusCode.OK)]
    [InlineData("::ffff:198.51.100.19", HttpStatusCode.OK)]
    [InlineData("198.51.100.18", HttpStatusCode.Forbidden)]
    [InlineData("198.51.100.20", HttpStatusCode.Forbidden)]
    public async Task ExactProxySourceDoesNotAuthorizeItsNeighbors(string source, HttpStatusCode expected)
    {
        await using var host = await TestBoundary.Start(source, configuration:
            Settings with { AllowedSourceCidrs = ["198.51.100.19/32"] });
        using var response = await host.Send("tools/list", new { });
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData("GUESTBROKER", "GUESTBROKER", true)]
    [InlineData("GUESTBROKER", "LocalBox-Client", false)]
    [InlineData("OTHERHOST", "GUESTBROKER", false)]
    public async Task PortableBoundaryIdentityStillChecksActualHost(string machine, string target, bool allowed)
    {
        await using var host = await TestBoundary.Start(machine: machine, configuration:
            Settings with { HostTarget = "GUESTBROKER" });
        using var response = await host.Send("tools/call",
            new { name = "get_boundary_identity", arguments = new { target } });
        var result = (await ReadRpc(response)).GetProperty("result");
        Assert.Equal(!allowed, result.TryGetProperty("isError", out var error) && error.GetBoolean());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("*")]
    [InlineData("host.example.test")]
    [InlineData("host;whoami")]
    public void InvalidHostTargetIsRejected(string? value) =>
        Assert.Throws<InvalidOperationException>(() => (Settings with { HostTarget = value! }).Validate());

    [Theory]
    [InlineData("198.51.100.0", false)]
    [InlineData("198.51.100.1", true)]
    [InlineData("198.51.100.19", true)]
    [InlineData("198.51.100.254", true)]
    [InlineData("198.51.100.255", false)]
    [InlineData("192.0.2.1", false)]
    [InlineData("203.0.113.1", false)]
    public void FullOctetSubnetAcceptsOnlyItsHosts(string address, bool expected) =>
        Assert.Equal(expected, Ipv4SourceCidr.Parse("198.51.100.0/24").Contains(IPAddress.Parse(address)));

    [Theory]
    [InlineData("203.0.113.64", HttpStatusCode.Forbidden)]
    [InlineData("203.0.113.65", HttpStatusCode.OK)]
    [InlineData("203.0.113.126", HttpStatusCode.OK)]
    [InlineData("203.0.113.127", HttpStatusCode.Forbidden)]
    [InlineData("203.0.113.128", HttpStatusCode.Forbidden)]
    [InlineData("::ffff:203.0.113.65", HttpStatusCode.OK)]
    [InlineData("::ffff:203.0.113.127", HttpStatusCode.Forbidden)]
    [InlineData("2001:db8::65", HttpStatusCode.Forbidden)]
    [InlineData("198.51.100.19", HttpStatusCode.Forbidden)]
    public async Task PipelineUsesConfiguredNetworkNotFormerTestRange(string source, HttpStatusCode expected)
    {
        await using var host = await TestBoundary.Start(source, configuration:
            Settings with { AllowedSourceCidrs = ["203.0.113.64/26"] });
        using var response = await host.Send("tools/list", new { });
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData("198.51.100.19")]
    [InlineData("203.0.113.65")]
    public async Task PipelineAcceptsEitherExplicitNetwork(string source)
    {
        await using var host = await TestBoundary.Start(source, configuration:
            Settings with { AllowedSourceCidrs = ["198.51.100.0/27", "203.0.113.64/26"] });
        using var response = await host.Send("tools/list", new { });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Theory]
    [InlineData("127.0.0.1", false, HttpStatusCode.Forbidden)]
    [InlineData("::ffff:127.0.0.1", false, HttpStatusCode.Forbidden)]
    [InlineData("127.0.0.1", true, HttpStatusCode.OK)]
    [InlineData("::ffff:127.0.0.1", true, HttpStatusCode.OK)]
    public async Task LoopbackNeedsExplicitCidrNotServiceBypass(string source, bool configured, HttpStatusCode expected)
    {
        await using var host = await TestBoundary.Start(source, configuration: Settings with
        {
            AllowedSourceCidrs = configured ? ["127.0.0.0/30"] : Settings.AllowedSourceCidrs
        });
        using var response = await host.Send("tools/list", new { });
        Assert.Equal(expected, response.StatusCode);
    }

    [Theory]
    [InlineData("203.0.113.19", "198.51.100.19", HttpStatusCode.Forbidden)]
    [InlineData("198.51.100.19", "203.0.113.19", HttpStatusCode.OK)]
    public async Task ForwardingHeadersNeverOverridePacketSource(string source, string forwarded, HttpStatusCode expected)
    {
        await using var host = await TestBoundary.Start(source);
        using var response = await host.Send("tools/list", new { }, forwardedSource: forwarded);
        Assert.Equal(expected, response.StatusCode);
    }

    [Fact]
    public async Task OrdinaryServerReadsNeedNoLocalBoxHostOrEnabledNodeCapabilities()
    {
        var executor = new ServerFake();
        await using var host = await TestBoundary.Start(machine: "PORTABLEHOST", serverExecutor: executor,
            serversEnabled: true, configuration: Settings with { NodeIdentityEnabled = false, ReadCapabilitiesEnabled = false });
        foreach (var call in new[]
        {
            ("get_server_facts", """{"target":"server-01"}"""),
            ("get_server_service_state", """{"target":"server-01","service":"Spooler"}"""),
            ("get_server_events", """{"target":"server-01","log":"Application","maxCount":5,"lookbackMinutes":60}""")
        })
        {
            using var response = await host.Send("tools/call",
                new { name = call.Item1, arguments = JsonSerializer.Deserialize<JsonElement>(call.Item2) });
            Assert.Contains("success", (await ReadRpc(response)).ToString());
        }
        Assert.Equal(3, executor.Calls);
        foreach (var name in new[] { "get_node_identity", "get_health_snapshot", "get_vm_checkpoint_inventory" })
        {
            using var response = await host.Send("tools/call", new
            {
                name, arguments = new { target = name == "get_node_identity" ? "AzLHOST1" : "localboxcluster" }
            });
            Assert.True((await ReadRpc(response)).GetProperty("result").GetProperty("isError").GetBoolean());
        }
    }
}
