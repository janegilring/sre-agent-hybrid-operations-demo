using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Security;
using System.Text.Json;
using System.Text.Json.Nodes;
using PrivateMcp;
using Xunit;

namespace PrivateMcpTests;

public sealed class NodeCapabilityTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;
    private static readonly Guid Correlation = Guid.NewGuid();

    [Theory]
    [InlineData("AzLHOST1")]
    [InlineData("AzLHOST2")]
    public void FixedConnectionsUseEncryptedKerberosAndBoundedObjects(string target)
    {
        using var password = new SecureString();
        var connection = NodeCapabilityReader.CreateConnection(new PSCredential("test", password), target);
        Assert.Equal(AuthenticationMechanism.Kerberos, connection.AuthenticationMechanism);
        Assert.Equal($"{target.ToLowerInvariant()}.jumpstart.local", connection.ComputerName);
        Assert.EndsWith("/LocalBox.ReadOnly", connection.ShellUri);
        Assert.False(connection.NoEncryption);
        Assert.Equal(0, connection.MaximumConnectionRedirectionCount);
        Assert.Equal(262144, connection.MaximumReceivedObjectSize);
    }

    [Theory]
    [InlineData("AzLHOST3")]
    [InlineData("AzLHOST1.jumpstart.local")]
    [InlineData("AzLHOST1;whoami")]
    [InlineData("")]
    public void NoArbitraryEndpoint(string target)
    {
        using var password = new SecureString();
        Assert.Throws<InvalidOperationException>(() => NodeCapabilityReader.CreateConnection(new PSCredential("test", password), target));
    }

    [Fact]
    public void UnknownProvidersNeverMeanZeroVmsOrHealthy()
    {
        var health = NodeCapabilityReader.SummarizeHealth(Failed<HealthRow>(), Correlation, Now, Now);
        Assert.Equal("UNKNOWN", health.HealthAssessment);
        Assert.Equal(0, health.NodesResponded);
        var inventory = NodeCapabilityReader.SummarizeInventory(Failed<VmRow>(), Correlation, Now, Now);
        Assert.Null(inventory.ObservedVmCount);
        Assert.Null(inventory.ObservedCheckpointCount);
        Assert.True(inventory.CountsAreLowerBounds);
    }

    [Fact]
    public async Task PreCancelledCallNeverStartsCredentialOrProviderWork()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new NodeCapabilityReader().ReadHealthAsync(Correlation, cancellation.Token));
    }

    [Fact]
    public void EmptyFaultsDoNotOverrideMissingStorageOrNodeCoverage()
    {
        var nodes = HealthNodes();
        var good = NodeCapabilityReader.SummarizeHealth(nodes, Correlation, Now, Now);
        Assert.Equal("NoIssuesObserved", good.HealthAssessment);
        nodes[0] = nodes[0] with
        {
            Data = nodes[0].Data! with
            {
                Providers = nodes[0].Data!.Providers.Select(p => p.Source == "Storage.Get-StorageJob"
                    ? p with { Status = "accessdenied", ErrorCode = "ProviderAccessDenied" } : p).ToArray()
            }
        };
        Assert.Equal("UNKNOWN", NodeCapabilityReader.SummarizeHealth(nodes, Correlation, Now, Now).HealthAssessment);
        nodes = HealthNodes();
        nodes[0] = nodes[0] with
        {
            Data = nodes[0].Data! with
            {
                Providers = nodes[0].Data!.Providers.Select(p => p.Source == "FailoverClusters.Get-ClusterNode"
                    ? p with { Rows = [p.Rows[0]] } : p).ToArray()
            }
        };
        Assert.Equal("UNKNOWN", NodeCapabilityReader.SummarizeHealth(nodes, Correlation, Now, Now).HealthAssessment);
    }

    [Fact]
    public void ValidHealthSchemaContainsBoundedCapacityAndExplicitSources()
    {
        var data = HealthNodes()[0].Data!;
        var parsed = NodeCapabilityReader.Parse<HealthRow>(JsonSerializer.Serialize(data), "AzLHOST1", "health_snapshot", Correlation, Now);
        Assert.Equal(4, parsed.Providers.Length);
        Assert.Equal(100L, parsed.Providers[1].Rows[0].CapacityBytes);
    }

    [Fact]
    public void SuccessfulEmptyInventoryIsExplicitZeroOnBothNodes()
    {
        var nodes = InventoryNodes([]);
        var inventory = NodeCapabilityReader.SummarizeInventory(nodes, Correlation, Now, Now);
        Assert.Equal("success", inventory.Status);
        Assert.Equal(0, inventory.ObservedVmCount);
        Assert.Equal(0, inventory.ObservedCheckpointCount);
        Assert.False(inventory.CountsAreLowerBounds);
    }

    [Fact]
    public void MissingNodeAndTruncationArePartial()
    {
        var nodes = InventoryNodes([]);
        nodes[1] = new("AzLHOST2", "timedout", "TransportTimeout", null);
        var inventory = NodeCapabilityReader.SummarizeInventory(nodes, Correlation, Now, Now);
        Assert.Equal("partial", inventory.Status);
        Assert.Equal(1, inventory.NodesResponded);
        Assert.True(inventory.CountsAreLowerBounds);
        nodes = InventoryNodes([]);
        nodes[0] = nodes[0] with
        {
            Data = nodes[0].Data! with
            {
                Providers = [nodes[0].Data!.Providers[0] with { Status = "partial", ErrorCode = "RowLimit", Truncated = true }]
            }
        };
        Assert.Equal("partial", NodeCapabilityReader.SummarizeInventory(nodes, Correlation, Now, Now).Status);
    }

    [Fact]
    public void StableVmAndCheckpointIdsDeduplicateButPreserveMigrationObservations()
    {
        var vm = Vm();
        var nodes = InventoryNodes([vm]);
        var inventory = NodeCapabilityReader.SummarizeInventory(nodes, Correlation, Now, Now);
        Assert.Equal(1, inventory.ObservedVmCount);
        Assert.Equal(1, inventory.ObservedCheckpointCount);
        Assert.Equal("partial", inventory.Status);
        Assert.True(inventory.VirtualMachines[0].MultipleNodeObservations);
        Assert.Equal(2, inventory.VirtualMachines[0].Observations.Length);
        Assert.Null(inventory.VirtualMachines[0].OwnerNode);
        Assert.All(inventory.VirtualMachines[0].Observations, observation => Assert.Equal("Off", observation.State));
    }

    [Fact]
    public void VmWithoutCheckpointsRetainsVmRow()
    {
        var vm = Vm() with { Checkpoints = Provider<CheckpointRow>("Hyper-V.Get-VMSnapshot", 16, []) };
        var nodes = InventoryNodes([]);
        nodes[0] = new("AzLHOST1", "success", null, Envelope("AzLHOST1", "vm_checkpoint_inventory",
            [Provider("Hyper-V.Get-VM/Get-VMSnapshot", 128, new[] { vm })]));
        var inventory = NodeCapabilityReader.SummarizeInventory(nodes, Correlation, Now, Now);
        Assert.Equal(1, inventory.ObservedVmCount);
        Assert.Equal(0, inventory.ObservedCheckpointCount);
        Assert.Empty(inventory.VirtualMachines[0].Observations[0].Checkpoints);
    }

    [Fact]
    public void CheckpointDenialPreservesVmAndUnknownCheckpointCount()
    {
        var vm = Vm() with
        {
            Checkpoints = Provider<CheckpointRow>("Hyper-V.Get-VMSnapshot", 16, []) with
            { Status = "accessdenied", ErrorCode = "ProviderAccessDenied" }
        };
        var nodes = InventoryNodes([vm]);
        var inventory = NodeCapabilityReader.SummarizeInventory(nodes, Correlation, Now, Now);
        Assert.Equal(1, inventory.ObservedVmCount);
        Assert.Null(inventory.ObservedCheckpointCount);
        Assert.Equal("partial", inventory.Status);
    }

    [Theory]
    [InlineData("IsAdministrator", "true")]
    [InlineData("SchemaVersion", "2")]
    [InlineData("Machine", "\"AZLHOST2\"")]
    [InlineData("ConnectingIdentity", "\"jumpstart\\\\Administrator\"")]
    [InlineData("ExecutionIdentity", "\"NT AUTHORITY\\\\SYSTEM\"")]
    [InlineData("CorrelationId", "\"00000000-0000-0000-0000-000000000000\"")]
    [InlineData("Operation", "\"run_command\"")]
    [InlineData("UnexpectedField", "\"secret-must-not-pass\"")]
    public void UntrustedEnvelopeCannotForgeIdentityOrAddFields(string field, string value)
    {
        var json = JsonNode.Parse(JsonSerializer.Serialize(InventoryNodes([])[0].Data))!;
        json[field] = JsonNode.Parse(value);
        Assert.ThrowsAny<Exception>(() => ParseInventory(json.ToJsonString()));
    }

    [Fact]
    public void MissingFieldStaleClockOversizeAndMissingProviderAreRejected()
    {
        var data = InventoryNodes([])[0].Data!;
        var json = JsonNode.Parse(JsonSerializer.Serialize(data))!.AsObject();
        json.Remove("IsAdministrator");
        Assert.Throws<JsonException>(() => ParseInventory(json.ToJsonString()));
        Assert.Throws<InvalidOperationException>(() => ParseInventory(JsonSerializer.Serialize(data with { AsOfUtc = Now.AddMinutes(-3) })));
        Assert.Throws<InvalidOperationException>(() => ParseInventory(new string('x', NodeCapabilityReader.MaximumResponseBytes + 1)));
        Assert.Throws<InvalidOperationException>(() => ParseInventory(JsonSerializer.Serialize(data with { Providers = [] })));
    }

    [Fact]
    public void FalseSuccessAndRawErrorsCannotPassContract()
    {
        var data = InventoryNodes([])[0].Data!;
        Assert.Throws<InvalidOperationException>(() => ParseInventory(JsonSerializer.Serialize(data with
        { Providers = [data.Providers[0] with { ErrorCode = "secret-error" }] })));
        Assert.Throws<InvalidOperationException>(() => ParseInventory(JsonSerializer.Serialize(data with
        { Providers = [data.Providers[0] with { Status = "accessdenied", ErrorCode = "raw-error" }] })));
    }

    [Fact]
    public void ValidOffVmRecoveryAndFutureTimestampRemainMetadataNotDeletionAdvice()
    {
        var vm = Vm();
        var data = Envelope("AzLHOST1", "vm_checkpoint_inventory", new[] { Provider("Hyper-V.Get-VM/Get-VMSnapshot", 128, new[] { vm }) });
        var parsed = ParseInventory(JsonSerializer.Serialize(data));
        Assert.Equal("Off", parsed.Providers[0].Rows[0].State);
        Assert.Equal("Recovery", parsed.Providers[0].Rows[0].Checkpoints.Rows[0].SnapshotType);
        Assert.True(parsed.Providers[0].Rows[0].Checkpoints.Rows[0].CreationTimeUtc > Now);
    }

    private static NodeRead<VmRow> ParseInventory(string json) =>
        NodeCapabilityReader.Parse<VmRow>(json, "AzLHOST1", "vm_checkpoint_inventory", Correlation, Now);
    private static NodeObservation<T>[] Failed<T>() =>
        NodeCapabilityReader.ApprovedNodes.Select(n => new NodeObservation<T>(n, "unsupported", "Unavailable", null)).ToArray();
    private static NodeObservation<VmRow>[] InventoryNodes(VmRow[] vms) =>
        NodeCapabilityReader.ApprovedNodes.Select(n => new NodeObservation<VmRow>(n, "success", null,
            Envelope(n, "vm_checkpoint_inventory", new[] { Provider("Hyper-V.Get-VM/Get-VMSnapshot", 128,
                vms.Select(vm => vm with { ObservedNode = n }).ToArray()) }))).ToArray();
    private static NodeObservation<HealthRow>[] HealthNodes() =>
        NodeCapabilityReader.ApprovedNodes.Select(n => new NodeObservation<HealthRow>(n, "success", null,
            Envelope(n, "health_snapshot", new[]
            {
                Provider("FailoverClusters.Get-ClusterNode", 8, NodeCapabilityReader.ApprovedNodes.Select(node => new HealthRow { Name = node, State = "Up" }).ToArray()),
                Provider("FailoverClusters.Get-ClusterSharedVolume", 32, new[] { new HealthRow { Name = "SyntheticCsv", State = "Online", OwnerNode = "AzLHOST1", CapacityBytes = 100, FreeBytes = 50 } }),
                Provider<HealthRow>("FailoverClusters.Get-HealthFault", 32, []),
                Provider<HealthRow>("Storage.Get-StorageJob", 32, [])
            }))).ToArray();
    private static NodeRead<T> Envelope<T>(string node, string operation, ProviderResult<T>[] providers) => new()
    {
        SchemaVersion = 1,
        Operation = operation,
        Machine = node,
        Domain = "jumpstart.local",
        OsVersion = "10.0.26100.0",
        ConnectingIdentity = @"jumpstart\svcMcpNodeRead",
        ExecutionIdentity = @"WinRM Virtual Users\WinRM VA_1_jumpstart_svcMcpNodeRead",
        IsAdministrator = false,
        CorrelationId = Correlation,
        AsOfUtc = Now,
        CompletedUtc = Now,
        Providers = providers
    };
    private static ProviderResult<T> Provider<T>(string source, int limit, T[] rows) => new()
    {
        Source = source,
        Status = "success",
        ErrorCode = null,
        Truncated = false,
        Limit = limit,
        AsOfUtc = Now,
        CompletedUtc = Now,
        Rows = rows
    };
    private static VmRow Vm() => new()
    {
        Id = Guid.NewGuid(),
        Name = "Synthetic-offline-vm",
        State = "Off",
        ObservedNode = "AZLHOST1",
        Checkpoints = Provider("Hyper-V.Get-VMSnapshot", 16, new[]
        {
            new CheckpointRow { Id = Guid.NewGuid(), Name = "Synthetic-recovery", SnapshotType = "Recovery",
                CreationTimeUtc = Now.AddMinutes(5), ParentId = null }
        })
    };
}
