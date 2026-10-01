using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace PrivateMcp;

public sealed record ProviderResult<T>
{
    public required string Source { get; init; }
    public required string Status { get; init; }
    public required DateTimeOffset AsOfUtc { get; init; }
    public required DateTimeOffset CompletedUtc { get; init; }
    public required string? ErrorCode { get; init; }
    public required bool Truncated { get; init; }
    public required int Limit { get; init; }
    public required T[] Rows { get; init; }
}

public sealed record NodeRead<T>
{
    public required int SchemaVersion { get; init; }
    public required string Operation { get; init; }
    public required string Machine { get; init; }
    public required string Domain { get; init; }
    public required string OsVersion { get; init; }
    public required string ConnectingIdentity { get; init; }
    public required string ExecutionIdentity { get; init; }
    public required bool IsAdministrator { get; init; }
    public required Guid CorrelationId { get; init; }
    public required DateTimeOffset AsOfUtc { get; init; }
    public required DateTimeOffset CompletedUtc { get; init; }
    public required ProviderResult<T>[] Providers { get; init; }
}

public sealed record HealthRow
{
    public string? Name { get; init; }
    public string? State { get; init; }
    public string? OwnerNode { get; init; }
    public long? CapacityBytes { get; init; }
    public long? FreeBytes { get; init; }
    public string? Reason { get; init; }
    public string? Severity { get; init; }
    public string? RecommendedAction { get; init; }
    public int? PercentComplete { get; init; }
}

public sealed record CheckpointRow
{
    public required Guid Id { get; init; }
    public required string Name { get; init; }
    public required DateTimeOffset? CreationTimeUtc { get; init; }
    public required string? SnapshotType { get; init; }
    public required Guid? ParentId { get; init; }
}

public sealed record VmRow
{
    public required Guid Id { get; init; }
    public required string Name { get; init; }
    public required string State { get; init; }
    public required string ObservedNode { get; init; }
    public required ProviderResult<CheckpointRow> Checkpoints { get; init; }
}

public sealed record NodeObservation<T>(string Target, string Status, string? ErrorCode, NodeRead<T>? Data);
public sealed record HealthSnapshot(int SchemaVersion, string Target, Guid CorrelationId, DateTimeOffset AsOfUtc,
    DateTimeOffset CompletedUtc, string Status, string HealthAssessment, int NodesRequested, int NodesResponded,
    string[] UnassessedSources, NodeObservation<HealthRow>[] Nodes);
public sealed record VmObservation(string Node, DateTimeOffset AsOfUtc, string Name, string State,
    string CheckpointStatus, string? CheckpointErrorCode, CheckpointRow[] Checkpoints);
public sealed record VmInventoryItem(Guid Id, string? OwnerNode, bool MultipleNodeObservations, VmObservation[] Observations);
public sealed record VmCheckpointInventory(int SchemaVersion, string Target, Guid CorrelationId, DateTimeOffset AsOfUtc,
    DateTimeOffset CompletedUtc, string Status, string Scope, int NodesRequested, int NodesResponded,
    int? ObservedVmCount, int? ObservedCheckpointCount, bool CountsAreLowerBounds, string OwnershipStatus,
    NodeObservation<VmRow>[] Nodes, VmInventoryItem[] VirtualMachines);

public interface INodeCapabilityReader
{
    Task<HealthSnapshot> ReadHealthAsync(Guid correlation, CancellationToken cancellationToken);
    Task<VmCheckpointInventory> ReadInventoryAsync(Guid correlation, CancellationToken cancellationToken);
}

public sealed class NodeCapabilityReader : INodeCapabilityReader
{
    public const int MaximumResponseBytes = 196608;
    public const int MaximumToolResponseBytes = 262144;
    public const string Endpoint = "LocalBox.ReadOnly";
    public static readonly string[] ApprovedNodes = ["AzLHOST1", "AzLHOST2"];
    private static readonly string[] HealthSources = ["FailoverClusters.Get-ClusterNode",
        "FailoverClusters.Get-ClusterSharedVolume", "FailoverClusters.Get-HealthFault", "Storage.Get-StorageJob"];
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 16
    };
    private readonly SemaphoreSlim gate = new(1, 1);

    public async Task<HealthSnapshot> ReadHealthAsync(Guid correlation, CancellationToken cancellationToken)
    {
        var start = DateTimeOffset.UtcNow;
        var nodes = await ReadNodes<HealthRow>("health_snapshot", correlation, cancellationToken);
        return SummarizeHealth(nodes, correlation, start, DateTimeOffset.UtcNow);
    }

    public async Task<VmCheckpointInventory> ReadInventoryAsync(Guid correlation, CancellationToken cancellationToken)
    {
        var start = DateTimeOffset.UtcNow;
        var nodes = await ReadNodes<VmRow>("vm_checkpoint_inventory", correlation, cancellationToken);
        return SummarizeInventory(nodes, correlation, start, DateTimeOffset.UtcNow);
    }

    private async Task<NodeObservation<T>[]> ReadNodes<T>(string operation, Guid correlation, CancellationToken cancellationToken)
    {
        if (!await gate.WaitAsync(0, cancellationToken))
            return ApprovedNodes.Select(target => new NodeObservation<T>(target, "partial", "CollectorBusy", null)).ToArray();
        // Own one bounded native runspace at a time. Caller cancellation never releases
        // the gate while a provider is still stopping.
        var worker = Task.Run(() =>
        {
            try
            {
                var results = new List<NodeObservation<T>>();
                foreach (var target in ApprovedNodes)
                {
                    if (cancellationToken.IsCancellationRequested)
                    {
                        results.Add(new(target, "partial", "Cancelled", null));
                        continue;
                    }
                    try
                    {
                        var data = ReadNode<T>(target, operation, correlation, cancellationToken);
                        results.Add(new(target, "success", null, data));
                    }
                    catch (TimeoutException) { results.Add(new(target, "timedout", "TransportTimeout", null)); }
                    catch (OperationCanceledException) { results.Add(new(target, "partial", "Cancelled", null)); }
                    catch { results.Add(new(target, "unsupported", "TransportOrContractFailure", null)); }
                }
                return results.ToArray();
            }
            finally { gate.Release(); }
        }, CancellationToken.None);
        _ = worker.ContinueWith(task => _ = task.Exception, CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        try { return await worker.WaitAsync(TimeSpan.FromSeconds(55), cancellationToken); }
        catch (TimeoutException)
        {
            return ApprovedNodes.Select(target => new NodeObservation<T>(target, "timedout", "CollectorTimeout", null)).ToArray();
        }
    }

    public static WSManConnectionInfo CreateConnection(PSCredential credential, string target)
    {
        var connection = NodeIdentityReader.CreateConnection(credential, target);
        connection.ShellUri = $"http://schemas.microsoft.com/powershell/{Endpoint}";
        connection.MaximumReceivedDataSizePerCommand = 262144;
        connection.MaximumReceivedObjectSize = 262144;
        return connection;
    }

    private static NodeRead<T> ReadNode<T>(string target, string operation, Guid correlation, CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("Windows transport required.");
        using var password = NodeIdentityReader.LoadPassword();
        using var runspace = RunspaceFactory.CreateRunspace(
            CreateConnection(new PSCredential("svcMcpNodeRead@jumpstart.local", password), target));
        runspace.Open();
        using var command = PowerShell.Create();
        command.Runspace = runspace;
        command.AddCommand(operation switch
        {
            "health_snapshot" => "Get-LocalBoxHealthSnapshot",
            "vm_checkpoint_inventory" => "Get-LocalBoxVmCheckpointInventory",
            _ => throw new InvalidOperationException("Operation not allowed.")
        }).AddParameter("CorrelationId", correlation);
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
            throw new InvalidOperationException("Unexpected response.");
        return Parse<T>(json, target, operation, correlation, DateTimeOffset.UtcNow);
    }

    public static NodeRead<T> Parse<T>(string json, string target, string operation, Guid correlation, DateTimeOffset now)
    {
        NodeIdentityReader.RequireTarget(target);
        if (Encoding.UTF8.GetByteCount(json) > MaximumResponseBytes) throw new InvalidOperationException("Response limit.");
        var result = JsonSerializer.Deserialize<NodeRead<T>>(json, JsonOptions) ?? throw new InvalidOperationException("Missing result.");
        if (result.SchemaVersion != 1 || result.Operation != operation || result.CorrelationId != correlation ||
            !result.Machine.Equals(target, StringComparison.OrdinalIgnoreCase) || result.Domain != "jumpstart.local" ||
            result.IsAdministrator || !result.ConnectingIdentity.Equals(@"jumpstart\svcMcpNodeRead", StringComparison.OrdinalIgnoreCase) ||
            !Regex.IsMatch(result.ExecutionIdentity, @"^WinRM Virtual Users\\WinRM VA_\d+_jumpstart_svcMcpNodeRead$", RegexOptions.IgnoreCase) ||
            !Regex.IsMatch(result.OsVersion, @"^\d{1,5}\.\d{1,5}\.\d{1,5}\.\d{1,5}$"))
            throw new InvalidOperationException("Identity mismatch.");
        ValidateTime(result.AsOfUtc, result.CompletedUtc, now);
        var sources = operation switch
        {
            "health_snapshot" when typeof(T) == typeof(HealthRow) => HealthSources,
            "vm_checkpoint_inventory" when typeof(T) == typeof(VmRow) => ["Hyper-V.Get-VM/Get-VMSnapshot"],
            _ => throw new InvalidOperationException("Operation mismatch.")
        };
        if (result.Providers is null || !result.Providers.Select(p => p.Source).SequenceEqual(sources))
            throw new InvalidOperationException("Provider coverage mismatch.");
        foreach (var provider in result.Providers)
        {
            ValidateProvider(provider, now);
            var limit = provider.Source switch
            {
                "FailoverClusters.Get-ClusterNode" => 8,
                "Hyper-V.Get-VM/Get-VMSnapshot" => 128,
                _ => 32
            };
            if (provider.Limit != limit) throw new InvalidOperationException("Provider limit mismatch.");
            foreach (var row in provider.Rows)
            {
                if (row is HealthRow health) ValidateHealthRow(health, provider.Source);
                else if (row is VmRow vm)
                {
                    if (vm.Id == Guid.Empty || !vm.ObservedNode.Equals(target, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("VM identity mismatch.");
                    Text(vm.Name, 160); Text(vm.State, 32);
                    ValidateProvider(vm.Checkpoints, now);
                    if (vm.Checkpoints.Source != "Hyper-V.Get-VMSnapshot" || vm.Checkpoints.Limit != 16 ||
                        vm.Checkpoints.Rows.Select(s => s.Id).Distinct().Count() != vm.Checkpoints.Rows.Length)
                        throw new InvalidOperationException("Checkpoint contract mismatch.");
                    foreach (var checkpoint in vm.Checkpoints.Rows)
                    {
                        if (checkpoint.Id == Guid.Empty || checkpoint.ParentId == Guid.Empty) throw new InvalidOperationException("Checkpoint identity missing.");
                        Text(checkpoint.Name, 160); Text(checkpoint.SnapshotType, 32, true);
                        // Future/missing creation times remain raw observations; never derive an age or deletion advice.
                    }
                }
            }
        }
        return result;
    }

    private static void ValidateTime(DateTimeOffset start, DateTimeOffset completed, DateTimeOffset now)
    {
        if (start.Offset != TimeSpan.Zero || completed.Offset != TimeSpan.Zero || start > completed ||
            start < now.AddMinutes(-2) || completed > now.AddSeconds(5))
            throw new InvalidOperationException("Stale or invalid observation time.");
    }

    private static void ValidateProvider<T>(ProviderResult<T> p, DateTimeOffset now)
    {
        ValidateTime(p.AsOfUtc, p.CompletedUtc, now);
        if (p.Rows is null || p.Limit is < 1 or > 128 || p.Rows.Length > p.Limit ||
            p.Status is not ("success" or "partial" or "unsupported" or "accessdenied" or "timedout") ||
            p.Status == "success" && (p.ErrorCode is not null || p.Truncated) ||
            p.Status == "partial" && (!p.Truncated || p.ErrorCode != "RowLimit") ||
            p.Status is "unsupported" or "accessdenied" or "timedout" && (p.Rows.Length != 0 || p.Truncated) ||
            p.Status == "unsupported" && p.ErrorCode is not ("ProviderFailure" or "ProviderUnavailable") ||
            p.Status == "accessdenied" && p.ErrorCode != "ProviderAccessDenied" ||
            p.Status == "timedout" && p.ErrorCode != "ProviderTimeout")
            throw new InvalidOperationException("Invalid provider result.");
    }

    private static void Text(string? value, int limit, bool optional = false)
    {
        if (value is null && optional) return;
        if (value is null || value.Length > limit || value.Any(char.IsControl))
            throw new InvalidOperationException("Invalid text field.");
    }

    private static void ValidateHealthRow(HealthRow row, string source)
    {
        Text(row.Name, 160, true); Text(row.State, 160, true); Text(row.OwnerNode, 160, true);
        Text(row.Reason, 256, true); Text(row.Severity, 32, true); Text(row.RecommendedAction, 256, true);
        if (row.CapacityBytes < 0 || row.FreeBytes < 0 || row.FreeBytes > row.CapacityBytes || row.PercentComplete is < 0 or > 100)
            throw new InvalidOperationException("Invalid numeric observation.");
        if (source == HealthSources[0] && (row.Name is null || row.State is null ||
                !ApprovedNodes.Contains(row.Name, StringComparer.OrdinalIgnoreCase)) ||
            source == HealthSources[1] && (row.Name is null || row.State is null) ||
            source == HealthSources[2] && (row.Reason is null || row.Severity is null) ||
            source == HealthSources[3] && (row.Name is null || row.State is null))
            throw new InvalidOperationException("Missing source fields.");
    }

    private static string Status<T>(NodeObservation<T>[] nodes)
    {
        if (nodes.Length != 2 || !nodes.Select(n => n.Target).SequenceEqual(ApprovedNodes))
            throw new InvalidOperationException("Incomplete node envelope.");
        return nodes.All(n => n.Status == "success" && n.Data is not null &&
            n.Data.Providers.All(p => p.Status == "success")) ? "success" :
            nodes.Any(n => n.Data?.Providers.Any(p => p.Status == "success" || p.Rows.Length > 0) == true) ? "partial" : "unsupported";
    }

    public static HealthSnapshot SummarizeHealth(NodeObservation<HealthRow>[] nodes, Guid correlation,
        DateTimeOffset start, DateTimeOffset completed)
    {
        var status = Status(nodes);
        var providers = nodes.Where(n => n.Data is not null).SelectMany(n => n.Data!.Providers).ToArray();
        var missingClusterNodes = providers.Where(p => p.Source == HealthSources[0])
            .Any(p => !p.Rows.Select(r => r.Name).Order().SequenceEqual(ApprovedNodes.Order(), StringComparer.OrdinalIgnoreCase));
        var missingCsv = providers.Any(p => p.Source == HealthSources[1] && p.Rows.Length == 0);
        if ((missingClusterNodes || missingCsv) && status == "success") status = "partial";
        var issue = providers.Any(p => p.Source == HealthSources[2] && p.Rows.Length > 0 ||
            p.Source == HealthSources[0] && p.Rows.Any(r => r.State != "Up") ||
            p.Source == HealthSources[1] && p.Rows.Any(r => r.State != "Online"));
        var result = new HealthSnapshot(1, "localboxcluster", correlation, start, completed, status,
            status != "success" ? "UNKNOWN" : issue ? "IssuesObserved" : "NoIssuesObserved",
            2, nodes.Count(n => n.Data is not null),
            ["AzureMonitor", "Performance", "Events", "WorkloadControlPlane", "BackupRecoverability"],
            nodes);
        return JsonSerializer.SerializeToUtf8Bytes(result).Length <= MaximumToolResponseBytes ? result :
            result with { Status = "partial", HealthAssessment = "UNKNOWN",
                Nodes = nodes.Select(n => new NodeObservation<HealthRow>(n.Target, "partial", "ResponseByteLimit", null)).ToArray() };
    }

    public static VmCheckpointInventory SummarizeInventory(NodeObservation<VmRow>[] nodes, Guid correlation,
        DateTimeOffset start, DateTimeOffset completed)
    {
        var status = Status(nodes);
        var observations = nodes.Where(n => n.Data is not null)
            .SelectMany(n => n.Data!.Providers.SelectMany(p => p.Rows.Select(vm => new { n.Target, p.AsOfUtc, Vm = vm }))).ToArray();
        var items = observations.GroupBy(o => o.Vm.Id).Select(group =>
            new VmInventoryItem(group.Key, null, group.Select(o => o.Target).Distinct().Count() > 1,
                group.Select(o => new VmObservation(o.Target, o.AsOfUtc, o.Vm.Name, o.Vm.State,
                    o.Vm.Checkpoints.Status, o.Vm.Checkpoints.ErrorCode, o.Vm.Checkpoints.Rows)).ToArray())).ToArray();
        if (status == "success" && (items.Any(v => v.MultipleNodeObservations) ||
            observations.Any(o => o.Vm.Checkpoints.Status != "success"))) status = "partial";
        var vmKnown = nodes.Any(n => n.Data?.Providers.Any(p => p.Status is "success" or "partial") == true);
        var checkpointKnown = vmKnown && (items.Length == 0 || observations.Any(o => o.Vm.Checkpoints.Status is "success" or "partial"));
        var result = new VmCheckpointInventory(1, "localboxcluster", correlation, start, completed, status,
            "Hyper-V registered VMs observed on AzLHOST1 and AzLHOST2; includes offline VMs, not Azure Local control-plane inventory",
            2, nodes.Count(n => n.Data is not null), vmKnown ? items.Length : null,
            checkpointKnown ? observations.SelectMany(o => o.Vm.Checkpoints.Rows.Select(s => (o.Vm.Id, s.Id))).Distinct().Count() : null,
            status != "success", "NotRetrieved; node observations are not authoritative clustered ownership",
            nodes, items);
        return JsonSerializer.SerializeToUtf8Bytes(result).Length <= MaximumToolResponseBytes ? result :
            result with { Status = "partial", CountsAreLowerBounds = true, VirtualMachines = [],
                Nodes = nodes.Select(n => new NodeObservation<VmRow>(n.Target, "partial", "ResponseByteLimit", null)).ToArray() };
    }
}
