using System.Net;
using System.Text.Json;
using PrivateMcp;
using Xunit;

namespace PrivateMcpTests;

internal static class ServerTestData
{
    internal static readonly ServerTarget Target = new()
    {
        Id = "server-01", Hostname = "server01.example.test", Machine = "SERVER01",
        ConnectingIdentity = @"EXAMPLE\mcpRead$"
    };
    internal static string Json(ServerRequest request, Guid correlation)
    {
        var now = DateTimeOffset.UtcNow;
        var sources = request.Operation switch
        {
            "facts" => new[] { "Computer", "OS", "NIC", "Disk", "CPU" },
            "service" => ["Service"], _ => ["Events"]
        };
        return JsonSerializer.Serialize(new NodeRead<JsonElement>
        {
            SchemaVersion = 1, Operation = request.Operation, Machine = Target.Machine, Domain = "EXAMPLE",
            OsVersion = "10.0.20348.0", ConnectingIdentity = Target.ConnectingIdentity,
            ExecutionIdentity = @"WinRM Virtual Users\WinRM VA_1_EXAMPLE_mcpRead$", IsAdministrator = false,
            CorrelationId = correlation, AsOfUtc = now, CompletedUtc = now,
            Providers = sources.Select(source => new ProviderResult<JsonElement>
            {
                Source = source, Status = "success", ErrorCode = null, AsOfUtc = now, CompletedUtc = now, Truncated = false,
                Limit = source switch { "NIC" or "Disk" => 16, "CPU" => 8, "Events" => request.MaxCount, _ => 1 },
                Rows = source switch
                {
                    "Service" => [JsonSerializer.SerializeToElement(new { Name = "Spooler", State = "Running" })],
                    "Computer" => [JsonSerializer.SerializeToElement(new { Hostname = Target.Machine, UUID = Guid.NewGuid() })],
                    "OS" => [JsonSerializer.SerializeToElement(new { Caption = "Windows Server", Version = "10.0", TotalMemoryKiB = 1024, FreeMemoryKiB = 512 })],
                    _ => []
                }
            }).ToArray()
        });
    }
}

public sealed partial class BoundaryTests
{
    private sealed class ServerFake(string? failure = null) : IServerExecutor
    {
        public int Calls;
        public Task<string> ExecuteAsync(ServerTarget target, ServerRequest request, Guid correlation, CancellationToken token)
        {
            Calls++;
            Assert.Equal(ServerTestData.Target, target);
            request.Validate();
            if (failure == "throw") throw new InvalidOperationException("secret-executor-details");
            if (failure == "cancel") throw new OperationCanceledException();
            if (failure == "oversized") return Task.FromResult(new string('a', 131073));
            if (failure == "denied")
            {
                var data = JsonSerializer.Deserialize<NodeRead<JsonElement>>(ServerTestData.Json(request, correlation))!;
                return Task.FromResult(JsonSerializer.Serialize(data with
                {
                    Providers = data.Providers.Select(p => p with
                    {
                        Status = "denied", ErrorCode = "ProviderAccessDenied", Rows = []
                    }).ToArray()
                }));
            }
            return Task.FromResult(ServerTestData.Json(request, correlation));
        }
    }

    [Fact]
    public async Task ServerToolsAreNotRegisteredWithoutConfiguration()
    {
        await using var host = await TestBoundary.Start();
        using var response = await host.Send("tools/list", new { });
        Assert.DoesNotContain("get_server_", (await ReadRpc(response)).ToString());
        using var call = await host.Send("tools/call", new { name = "get_server_facts", arguments = new { target = "server-01" } });
        Assert.True((await ReadRpc(call)).GetProperty("result").GetProperty("isError").GetBoolean());
    }

    [Fact]
    public async Task ConfiguredServerToolsExecuteThroughAuthenticatedProtocolAndExecutor()
    {
        var executor = new ServerFake();
        await using var host = await TestBoundary.Start(serverExecutor: executor, serversEnabled: true);
        using var list = await host.Send("tools/list", new { });
        Assert.Equal(7, (await ReadRpc(list)).GetProperty("result").GetProperty("tools").GetArrayLength());
        foreach (var call in new[]
        {
            ("get_server_facts", """{"target":"server-01"}"""),
            ("get_server_service_state", """{"target":"server-01","service":"Spooler"}"""),
            ("get_server_events", """{"target":"server-01","log":"System","maxCount":5,"lookbackMinutes":60}""")
        })
        {
            using var response = await host.Send("tools/call", new { name = call.Item1, arguments = JsonSerializer.Deserialize<JsonElement>(call.Item2) });
            var rpc = await ReadRpc(response);
            Assert.False(rpc.GetProperty("result").TryGetProperty("isError", out var error) && error.GetBoolean());
            Assert.Contains("success", rpc.ToString());
            Assert.Contains(response.Headers.GetValues("X-Correlation-ID").Single(), rpc.ToString());
        }
        Assert.Equal(3, executor.Calls);
    }

    [Theory]
    [InlineData("get_server_facts", """{"target":"http://arbitrary.test"}""")]
    [InlineData("get_server_facts", """{"target":"server-01","command":"whoami"}""")]
    [InlineData("get_server_service_state", """{"target":"server-01","service":"WinRM"}""")]
    [InlineData("get_server_service_state", """{"target":"server-01","service":"Spooler;whoami"}""")]
    [InlineData("get_server_events", """{"target":"server-01","log":"Security","maxCount":5,"lookbackMinutes":60}""")]
    [InlineData("get_server_events", """{"target":"server-01","log":"System","maxCount":51,"lookbackMinutes":60}""")]
    [InlineData("get_server_events", """{"target":"server-01","log":"System","maxCount":0,"lookbackMinutes":60}""")]
    [InlineData("get_server_events", """{"target":"server-01","log":"System","maxCount":5,"lookbackMinutes":1441}""")]
    [InlineData("get_server_events", """{"target":"server-01","log":"System","maxCount":5,"lookbackMinutes":0}""")]
    [InlineData("get_server_events", """{"target":"server-01","log":"Application","maxCount":5,"lookbackMinutes":60,"xpath":"*"}""")]
    public async Task InvalidServerArgumentsNeverReachExecutor(string name, string json)
    {
        var executor = new ServerFake();
        await using var host = await TestBoundary.Start(serverExecutor: executor, serversEnabled: true);
        using var response = await host.Send("tools/call", new { name, arguments = JsonSerializer.Deserialize<JsonElement>(json) });
        var rpc = await ReadRpc(response);
        Assert.True(rpc.TryGetProperty("error", out _) || rpc.GetProperty("result").GetProperty("isError").GetBoolean());
        Assert.Equal(0, executor.Calls);
    }

    [Theory]
    [InlineData("none", HttpStatusCode.Unauthorized)]
    [InlineData("object", HttpStatusCode.Forbidden)]
    public async Task ServerAuthenticationPrecedesExecution(string mutation, HttpStatusCode status)
    {
        var executor = new ServerFake();
        await using var host = await TestBoundary.Start(serverExecutor: executor, serversEnabled: true);
        using var response = await host.Send("tools/call", new { name = "get_server_facts", arguments = new { target = "server-01" } }, mutation);
        Assert.Equal(status, response.StatusCode);
        Assert.Equal(0, executor.Calls);
    }

    [Theory]
    [InlineData("throw")]
    [InlineData("oversized")]
    [InlineData("cancel")]
    [InlineData("denied")]
    public async Task ServerFailuresAreBoundedUnknownNeverHealthy(string failure)
    {
        await using var host = await TestBoundary.Start(serverExecutor: new ServerFake(failure), serversEnabled: true);
        using var response = await host.Send("tools/call", new { name = "get_server_facts", arguments = new { target = "server-01" } });
        var text = (await ReadRpc(response)).ToString();
        Assert.Contains("unknown", text);
        Assert.DoesNotContain("secret-executor-details", text);
        Assert.DoesNotContain("success", text);
        Assert.True(text.Length < 4096);
    }

    [Fact]
    public void ServerConfigurationRejectsSelectorsAndDuplicates()
    {
        foreach (var target in new[]
        {
            ServerTestData.Target with { Id = "http://other" },
            ServerTestData.Target with { Hostname = "server.test:5985/path" },
            ServerTestData.Target with { Hostname = "127.0.0.1" },
            ServerTestData.Target with { Machine = "x; whoami" },
            ServerTestData.Target with { ConnectingIdentity = "*" }
        }) Assert.Throws<InvalidOperationException>(() => (Settings with { Servers = [target] }).Validate());
        Assert.Throws<InvalidOperationException>(() => (Settings with { Servers = [ServerTestData.Target, ServerTestData.Target] }).Validate());
    }

    [Theory]
    [InlineData("IsAdministrator", "false", "true")]
    [InlineData("Machine", "\"SERVER01\"", "\"OTHER\"")]
    [InlineData("Status", "\"success\"", "\"denied\"")]
    [InlineData("Limit", "1", "999")]
    public void ServerResponseContractFailsClosed(string property, string before, string after)
    {
        var id = Guid.NewGuid();
        var request = new ServerRequest("service", Service: "Spooler");
        var json = ServerTestData.Json(request, id).Replace($"\"{property}\":{before}", $"\"{property}\":{after}");
        Assert.Throws<InvalidOperationException>(() => ServerReader.Parse(json, ServerTestData.Target, request, id));
    }

    [Fact]
    public void OversizedStringsMissingSourcesAndArbitraryRowFieldsFailClosed()
    {
        var id = Guid.NewGuid();
        var request = new ServerRequest("service", Service: "Spooler");
        var json = ServerTestData.Json(request, id);
        foreach (var invalid in new[]
        {
            json.Replace("\"State\":\"Running\"", "\"State\":\"" + new string('x', 1025) + "\""),
            json.Replace("\"State\":\"Running\"", "\"State\":\"Running\",\"Command\":\"whoami\""),
            json.Replace("\"Source\":\"Service\"", "\"Source\":\"Other\"")
        }) Assert.Throws<InvalidOperationException>(() => ServerReader.Parse(invalid, ServerTestData.Target, request, id));
    }

    [Fact]
    public void TransportUsesFixedKerberosEndpointWithoutNodeCredentialOrRedirects()
    {
        var connection = ServerExecutor.CreateConnection(ServerTestData.Target);
        Assert.Equal("server01.example.test", connection.ConnectionUri.Host);
        Assert.EndsWith("/HybridServer.ReadOnly", connection.ShellUri);
        Assert.Equal(System.Management.Automation.Runspaces.AuthenticationMechanism.Kerberos, connection.AuthenticationMechanism);
        Assert.Null(connection.Credential);
        Assert.Equal(0, connection.MaximumConnectionRedirectionCount);
        Assert.False(connection.NoEncryption);
        Assert.Equal(262144, connection.MaximumReceivedDataSizePerCommand);
        Assert.Equal("Get-HybridServerEvents", new ServerRequest("events", Log: "System").Command);
        Assert.Throws<InvalidOperationException>(() => new ServerRequest("Invoke-Expression").Validate());
    }
}
