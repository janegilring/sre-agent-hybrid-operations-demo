using System.ComponentModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace PrivateMcp;

public sealed record ServerTarget
{
    public required string Id { get; init; }
    public required string Hostname { get; init; }
    public required string Machine { get; init; }
    public required string ConnectingIdentity { get; init; }
    public void Validate()
    {
        if (!Regex.IsMatch(Id, "^[a-z][a-z0-9-]{0,31}$") ||
            Hostname.Length > 253 || Uri.CheckHostName(Hostname) != UriHostNameType.Dns ||
            !Hostname.Contains('.') || Hostname.EndsWith('.') ||
            !Regex.IsMatch(Machine, "^[A-Za-z0-9][A-Za-z0-9-]{0,14}$") ||
            !Regex.IsMatch(ConnectingIdentity, @"^[A-Za-z0-9._-]{1,64}\\[A-Za-z0-9._$-]{1,64}$"))
            throw new InvalidOperationException("Invalid approved server configuration.");
    }
}

public sealed record ServerRequest(string Operation, string? Service = null, string? Log = null,
    int MaxCount = 20, int LookbackMinutes = 60)
{
    public void Validate()
    {
        if (Operation is not ("facts" or "service" or "events") ||
            (Operation == "service" ? Service != "Spooler" : Service is not null) ||
            (Operation == "events" ? Log is not ("System" or "Application") : Log is not null) ||
            MaxCount is < 1 or > 50 || LookbackMinutes is < 1 or > 1440)
            throw new InvalidOperationException("Server request denied.");
    }
    public string Command => Operation switch
    {
        "facts" => "Get-HybridServerFacts",
        "service" => "Get-HybridServerServiceState",
        "events" => "Get-HybridServerEvents",
        _ => throw new InvalidOperationException("Server command denied.")
    };
}

public interface IServerExecutor
{
    Task<string> ExecuteAsync(ServerTarget target, ServerRequest request, Guid correlation, CancellationToken cancellationToken);
}

public sealed class ServerExecutor : IServerExecutor
{
    public const string Endpoint = "HybridServer.ReadOnly";
    private readonly SemaphoreSlim gate = new(1, 1);
    public static WSManConnectionInfo CreateConnection(ServerTarget target)
    {
        target.Validate();
        // Integrated service identity only: no saved node password, delegation or authentication fallback.
        return new(new Uri($"http://{target.Hostname}:5985/wsman"),
            $"http://schemas.microsoft.com/powershell/{Endpoint}", (PSCredential?)null)
        {
            AuthenticationMechanism = AuthenticationMechanism.Kerberos,
            OpenTimeout = 10000, OperationTimeout = 10000, CancelTimeout = 1000,
            MaximumReceivedDataSizePerCommand = 262144, MaximumReceivedObjectSize = 262144,
            MaximumConnectionRedirectionCount = 0, NoEncryption = false
        };
    }
    public async Task<string> ExecuteAsync(ServerTarget target, ServerRequest request, Guid correlation, CancellationToken cancellationToken)
    {
        target.Validate(); request.Validate();
        if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("Windows transport required.");
        if (!await gate.WaitAsync(0, cancellationToken)) throw new InvalidOperationException("Collector busy.");
        var worker = Task.Run(() =>
        {
            try
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var runspace = RunspaceFactory.CreateRunspace(CreateConnection(target));
                runspace.Open();
                using var command = PowerShell.Create();
                command.Runspace = runspace;
                command.AddCommand(request.Command).AddParameter("CorrelationId", correlation);
                if (request.Operation == "service") command.AddParameter("Service", request.Service);
                if (request.Operation == "events")
                    command.AddParameter("Log", request.Log).AddParameter("MaxCount", request.MaxCount)
                        .AddParameter("LookbackMinutes", request.LookbackMinutes);
                var pending = command.BeginInvoke();
                var signalled = WaitHandle.WaitAny([pending.AsyncWaitHandle, cancellationToken.WaitHandle], 15000);
                if (signalled != 0)
                {
                    var stopping = command.BeginStop(null, null);
                    if (stopping.AsyncWaitHandle.WaitOne(1000)) command.EndStop(stopping);
                    if (signalled == 1) throw new OperationCanceledException(cancellationToken);
                    throw new TimeoutException();
                }
                var output = command.EndInvoke(pending);
                if (command.HadErrors || output.Count != 1 || output[0].BaseObject is not string json)
                    throw new InvalidOperationException("Invalid server response.");
                return json;
            }
            finally { gate.Release(); }
        }, CancellationToken.None);
        _ = worker.ContinueWith(t => _ = t.Exception, CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        return await worker.WaitAsync(TimeSpan.FromSeconds(30), cancellationToken);
    }
}

public sealed record ServerObservation(string Target, string Operation, Guid CorrelationId, string Status,
    string? ErrorCode, NodeRead<JsonElement>? Data);

public sealed class ServerReader(BoundarySettings settings, IServerExecutor executor)
{
    public async Task<ServerObservation> ReadAsync(string id, ServerRequest request, Guid correlation, CancellationToken cancellationToken)
    {
        request.Validate();
        var target = settings.Servers.SingleOrDefault(s => s.Id == id) ?? throw new McpException("Server target denied.");
        try
        {
            var json = await executor.ExecuteAsync(target, request, correlation, cancellationToken);
            var data = Parse(json, target, request, correlation);
            return new(id, request.Operation, correlation,
                data.Providers.All(p => p.Status == "success") ? "success" : "unknown", null, data);
        }
        catch (OperationCanceledException) { return new(id, request.Operation, correlation, "unknown", "Cancelled", null); }
        catch (TimeoutException) { return new(id, request.Operation, correlation, "unknown", "Timeout", null); }
        catch { return new(id, request.Operation, correlation, "unknown", "TransportOrContractFailure", null); }
    }

    public static NodeRead<JsonElement> Parse(string json, ServerTarget target, ServerRequest request, Guid correlation)
    {
        target.Validate(); request.Validate();
        if (Encoding.UTF8.GetByteCount(json) > 131072) throw new InvalidOperationException("Response limit.");
        var data = JsonSerializer.Deserialize<NodeRead<JsonElement>>(json, new JsonSerializerOptions
        {
            MaxDepth = 10, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
        }) ?? throw new InvalidOperationException("Missing response.");
        var now = DateTimeOffset.UtcNow;
        if (data.SchemaVersion != 1 || data.Operation != request.Operation || data.CorrelationId != correlation ||
            !string.Equals(data.Machine, target.Machine, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(data.ConnectingIdentity, target.ConnectingIdentity, StringComparison.OrdinalIgnoreCase) ||
            data.IsAdministrator || data.ExecutionIdentity is null ||
            !Regex.IsMatch(data.ExecutionIdentity, @"^WinRM Virtual Users\\WinRM VA_[A-Za-z0-9_.$-]{1,180}$") ||
            data.AsOfUtc < now.AddMinutes(-2) || data.CompletedUtc < data.AsOfUtc || data.CompletedUtc > now.AddSeconds(30))
            throw new InvalidOperationException("Server identity or time mismatch.");
        var sources = request.Operation switch
        {
            "facts" => new[] { "Computer", "OS", "NIC", "Disk", "CPU" },
            "service" => ["Service"],
            "events" => ["Events"],
            _ => throw new InvalidOperationException("Operation denied.")
        };
        if (data.Providers is null || !data.Providers.Select(p => p.Source).SequenceEqual(sources))
            throw new InvalidOperationException("Missing provider coverage.");
        foreach (var p in data.Providers)
        {
            var limit = p.Source switch { "NIC" or "Disk" => 16, "CPU" => 8, "Events" => request.MaxCount, _ => 1 };
            if (p.Limit != limit || p.Rows is null || p.Rows.Length > limit ||
                p.AsOfUtc < data.AsOfUtc || p.CompletedUtc < p.AsOfUtc || p.CompletedUtc > data.CompletedUtc ||
                p.Status is not ("success" or "partial" or "denied" or "unknown") ||
                (p.Status == "success" && (p.ErrorCode is not null || p.Truncated)) ||
                (p.Status != "success" && string.IsNullOrEmpty(p.ErrorCode)) ||
                (p.Status is "denied" or "unknown" && p.Rows.Length != 0) ||
                (p.Status == "partial" && !p.Truncated) ||
                (p.ErrorCode is not (null or "RowLimit" or "ProviderAccessDenied" or "ProviderFailure")) ||
                (p.Status == "success" && p.Source is "Computer" or "OS" or "Service" && p.Rows.Length != 1))
                throw new InvalidOperationException("Provider contract invalid.");
            foreach (var row in p.Rows)
            {
                if (row.ValueKind != JsonValueKind.Object) throw new InvalidOperationException("Invalid row.");
                if (p.Source == "Service" && row.GetProperty("Name").GetString() != request.Service)
                    throw new InvalidOperationException("Service mismatch.");
                if (p.Source == "Events" && row.GetProperty("Log").GetString() != request.Log)
                    throw new InvalidOperationException("Log mismatch.");
                ValidateRow(row, p.Source, target, request, data.AsOfUtc, data.CompletedUtc);
            }
        }
        CheckText(JsonSerializer.SerializeToElement(data));
        return data;
    }

    private static void ValidateRow(JsonElement row, string source, ServerTarget target, ServerRequest request,
        DateTimeOffset start, DateTimeOffset end)
    {
        var fields = source switch
        {
            "Computer" => new[] { "Hostname", "UUID" },
            "OS" => ["Caption", "Version", "TotalMemoryKiB", "FreeMemoryKiB"],
            "NIC" => ["Description", "MACAddress", "DHCPEnabled", "IPAddress", "Subnet", "Gateway", "DNS"],
            "Disk" => ["Device", "SizeBytes", "FreeBytes"],
            "CPU" => ["Name", "LogicalProcessors", "LoadPercent"],
            "Service" => ["Name", "State"],
            "Events" => ["Log", "RecordId", "Id", "TimeCreatedUtc", "Level", "Provider", "Message"],
            _ => throw new InvalidOperationException("Source denied.")
        };
        if (!row.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(fields.Order()))
            throw new InvalidOperationException("Row fields invalid.");
        long Number(string name) => row.GetProperty(name).TryGetInt64(out var value) && value >= 0
            ? value : throw new InvalidOperationException("Numeric observation invalid.");
        if (source == "Computer" &&
            (!string.Equals(row.GetProperty("Hostname").GetString(), target.Machine, StringComparison.OrdinalIgnoreCase) ||
             !Guid.TryParse(row.GetProperty("UUID").GetString(), out var uuid) || uuid == Guid.Empty))
            throw new InvalidOperationException("Computer identity invalid.");
        if (source == "OS" && Number("FreeMemoryKiB") > Number("TotalMemoryKiB") ||
            source == "Disk" && Number("FreeBytes") > Number("SizeBytes"))
            throw new InvalidOperationException("Capacity observation invalid.");
        if (source == "CPU" && (Number("LogicalProcessors") is < 1 or > 65536 ||
            row.GetProperty("LoadPercent").ValueKind != JsonValueKind.Null && Number("LoadPercent") > 100))
            throw new InvalidOperationException("CPU observation invalid.");
        if (source == "Service" && row.GetProperty("State").GetString() is not
            ("Running" or "Stopped" or "Paused" or "StartPending" or "StopPending" or "ContinuePending" or "PausePending"))
            throw new InvalidOperationException("Service state invalid.");
        if (source == "Events")
        {
            _ = Number("RecordId"); _ = Number("Id");
            var time = row.GetProperty("TimeCreatedUtc").GetDateTimeOffset();
            if (time < start.AddMinutes(-request.LookbackMinutes) || time > end)
                throw new InvalidOperationException("Event time outside request.");
        }
        if (source == "NIC")
        {
            _ = row.GetProperty("DHCPEnabled").GetBoolean();
            foreach (var field in new[] { "IPAddress", "Subnet", "Gateway", "DNS" })
                if (row.GetProperty(field).ValueKind != JsonValueKind.Array || row.GetProperty(field).GetArrayLength() > 8 ||
                    row.GetProperty(field).EnumerateArray().Any(v => v.ValueKind != JsonValueKind.String || v.GetString()!.Length > 64))
                    throw new InvalidOperationException("NIC address bound.");
        }
    }

    private static void CheckText(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.String && (element.GetString()!.Length > 1024 ||
            element.GetString()!.Any(char.IsControl))) throw new InvalidOperationException("Text limit.");
        if (element.ValueKind == JsonValueKind.Object)
            foreach (var property in element.EnumerateObject()) CheckText(property.Value);
        if (element.ValueKind == JsonValueKind.Array)
        {
            if (element.GetArrayLength() > 50) throw new InvalidOperationException("Array limit.");
            foreach (var item in element.EnumerateArray()) CheckText(item);
        }
    }
}

[McpServerToolType]
public sealed class ServerTools(IHttpContextAccessor accessor, BoundarySettings settings, ServerReader reader,
    ILogger<BoundaryTools> logger)
{
    public static bool IsTool(string name) => name is "get_server_facts" or "get_server_service_state" or "get_server_events";
    public static bool AllowedArguments(BoundarySettings settings, string name, IDictionary<string, JsonElement>? arguments)
    {
        var keys = name switch
        {
            "get_server_facts" => new[] { "target" },
            "get_server_service_state" => ["target", "service"],
            "get_server_events" => ["target", "log", "maxCount", "lookbackMinutes"],
            _ => []
        };
        return settings.Servers.Length > 0 && arguments is not null && arguments.Count == keys.Length &&
            keys.All(arguments.ContainsKey);
    }
    private async Task<ServerObservation> Read(string target, ServerRequest request, CancellationToken token)
    {
        var context = accessor.HttpContext;
        if (context is null || !BoundaryApplication.IsAuthorized(context.User, settings)) throw new McpException("Caller not authorized.");
        var correlation = Guid.Parse((string)context.Items["correlation"]!);
        var result = await reader.ReadAsync(target, request, correlation, token);
        logger.LogInformation("Boundary server read {Correlation} target {Target} operation {Operation} outcome {Status}",
            correlation, result.Target, result.Operation, result.Status);
        return result;
    }
    [McpServerTool(Name = "get_server_facts", ReadOnly = true, Destructive = false, OpenWorld = false)]
    [Description("Read current bounded server identity, OS/memory, NIC, disk and CPU observations. Missing providers remain unknown. No Arc dependency.")]
    public Task<ServerObservation> Facts(string target, CancellationToken cancellationToken) =>
        Read(target, new("facts"), cancellationToken);
    [McpServerTool(Name = "get_server_service_state", ReadOnly = true, Destructive = false, OpenWorld = false)]
    [Description("Read only the fixed Spooler service state. Does not start, stop or repair services.")]
    public Task<ServerObservation> Service(string target, string service, CancellationToken cancellationToken) =>
        Read(target, new("service", Service: service), cancellationToken);
    [McpServerTool(Name = "get_server_events", ReadOnly = true, Destructive = false, OpenWorld = false)]
    [Description("Read System/Application events, 1-50 records within 1-1440 minutes. Messages may contain private data; never publish raw logs.")]
    public Task<ServerObservation> Events(string target, string log, int maxCount, int lookbackMinutes, CancellationToken cancellationToken) =>
        Read(target, new("events", Log: log, MaxCount: maxCount, LookbackMinutes: lookbackMinutes), cancellationToken);
}
