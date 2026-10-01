using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Security;
using PrivateMcp;
using Xunit;

namespace PrivateMcpTests;

public sealed class NodeIdentityTests
{
    [Fact]
    public void TransportIsFixedKerberosEncryptedBoundedAndDoesNotRedirect()
    {
        using var password = new SecureString();
        var connection = NodeIdentityReader.CreateConnection(new PSCredential("test", password));
        Assert.Equal(AuthenticationMechanism.Kerberos, connection.AuthenticationMechanism);
        Assert.Equal("azlhost1.jumpstart.local", connection.ComputerName);
        Assert.Equal(5985, connection.Port);
        Assert.EndsWith("/LocalBox.NodeIdentity", connection.ShellUri);
        Assert.False(connection.NoEncryption);
        Assert.False(connection.SkipCACheck);
        Assert.False(connection.SkipCNCheck);
        Assert.False(connection.SkipRevocationCheck);
        Assert.Equal(0, connection.MaximumConnectionRedirectionCount);
        Assert.Equal(10000, connection.OpenTimeout);
        Assert.Equal(10000, connection.OperationTimeout);
        Assert.Equal(8192, connection.MaximumReceivedDataSizePerCommand);
        Assert.Equal(4096, connection.MaximumReceivedObjectSize);
    }

    [Theory]
    [InlineData("Machine", "AzLHOST2")]
    [InlineData("Machine", "")]
    [InlineData("Domain", "other.local")]
    [InlineData("OsVersion", "arbitrary-output")]
    [InlineData("ConnectingIdentity", "jumpstart\\Administrator")]
    [InlineData("ExecutionIdentity", "NT AUTHORITY\\SYSTEM")]
    [InlineData("ExecutionIdentity", "WinRM Virtual Users\\WinRM VA_1_jumpstart_svcMcpNodeRead\r\nforged")]
    [InlineData("CorrelationId", "00000000-0000-0000-0000-000000000000")]
    [InlineData("IsAdministrator", true)]
    [InlineData("IsAdministrator", "False")]
    public void InvalidNodeFieldsAreRejected(string field, object value)
    {
        var correlation = Guid.NewGuid();
        var result = Valid(correlation);
        result.Properties[field].Value = value;
        Assert.Throws<InvalidOperationException>(() => NodeIdentityReader.Validate(result, correlation));
    }

    [Fact]
    public void ValidResultHasFixedIdentityAndNoAdministrator()
    {
        var correlation = Guid.NewGuid();
        var identity = NodeIdentityReader.Validate(Valid(correlation), correlation);
        Assert.Equal("AzLHOST1", identity.Target);
        Assert.Equal("Kerberos", identity.Authentication);
        Assert.False(identity.IsAdministrator);
    }

    [Fact]
    public void OversizeFieldIsRejected()
    {
        var correlation = Guid.NewGuid();
        var result = Valid(correlation);
        result.Properties["Machine"].Value = new string('A', 8193);
        Assert.Throws<InvalidOperationException>(() => NodeIdentityReader.Validate(result, correlation));
    }

    private static PSObject Valid(Guid correlation)
    {
        var result = new PSObject();
        foreach (var (name, value) in new Dictionary<string, object>
        {
            ["Machine"] = "AZLHOST1",
            ["Domain"] = "jumpstart.local",
            ["OsVersion"] = "10.0.26100.0",
            ["ConnectingIdentity"] = @"jumpstart\svcMcpNodeRead",
            ["ExecutionIdentity"] = @"WinRM Virtual Users\WinRM VA_1_jumpstart_svcMcpNodeRead",
            ["IsAdministrator"] = false,
            ["CorrelationId"] = correlation.ToString("D")
        }) result.Properties.Add(new PSNoteProperty(name, value));
        return result;
    }
}
