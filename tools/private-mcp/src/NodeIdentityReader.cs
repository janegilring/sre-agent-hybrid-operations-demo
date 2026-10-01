using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Security;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace PrivateMcp;

public sealed record NodeIdentity(string Target, string Machine, string Domain, string OsVersion,
    string ConnectingIdentity, string ExecutionIdentity, bool IsAdministrator, string Authentication,
    string CorrelationId);

public interface INodeIdentityReader
{
    Task<NodeIdentity> ReadAsync(Guid correlation, CancellationToken cancellationToken);
    Task<NodeIdentity> ReadAsync(string target, Guid correlation, CancellationToken cancellationToken) =>
        target == NodeIdentityReader.NodeName ? ReadAsync(correlation, cancellationToken) :
            throw new InvalidOperationException("Node target unsupported.");
}

public sealed class NodeIdentityReader : INodeIdentityReader
{
    private readonly SemaphoreSlim gate = new(1, 1);
    public const string NodeName = "AzLHOST1";
    public const string NodeFqdn = "AzLHOST1.jumpstart.local";
    public const string Endpoint = "LocalBox.NodeIdentity";
    public const int MaximumResponseBytes = 8192;

    public async Task<NodeIdentity> ReadAsync(Guid correlation, CancellationToken cancellationToken)
        => await ReadAsync(NodeName, correlation, cancellationToken);

    public async Task<NodeIdentity> ReadAsync(string target, Guid correlation, CancellationToken cancellationToken)
    {
        RequireTarget(target);
        if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("Windows transport required.");
        if (!await gate.WaitAsync(0, cancellationToken))
            throw new InvalidOperationException("Node diagnostic already in progress.");
        // Hold the gate until the native operation exits, even if the HTTP caller disconnects.
        var operation = Task.Run(() =>
        {
            try { return Read(target, correlation); }
            finally { gate.Release(); }
        }, CancellationToken.None);
        return await operation.WaitAsync(TimeSpan.FromSeconds(25), cancellationToken);
    }

    private static NodeIdentity Read(string target, Guid correlation)
    {
        if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("Windows transport required.");
        using var password = LoadPassword();
        var connection = CreateConnection(new PSCredential("svcMcpNodeRead@jumpstart.local", password), target);
        using var runspace = RunspaceFactory.CreateRunspace(connection);
        runspace.Open();
        using var command = PowerShell.Create();
        command.Runspace = runspace;
        command.AddCommand("Get-NodeIdentity").AddParameter("CorrelationId", correlation);
        var result = command.Invoke();
        if (command.HadErrors || result.Count != 1) throw new InvalidOperationException("Invalid diagnostic result.");
        return Validate(result[0], correlation, target);
    }

    internal static SecureString LoadPassword()
    {
        if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("Windows transport required.");
        const string path = @"C:\ProgramData\LocalBoxPrivateMcp\NodeCredential\password.dpapi";
        if (new FileInfo(path).Length is < 1 or > 2048) throw new InvalidOperationException("Invalid credential store.");
        var bytes = ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.LocalMachine);
        var password = new SecureString();
        try
        {
            if (bytes.Length is < 32 or > 256 || bytes.Length % 2 != 0)
                throw new InvalidOperationException("Invalid credential encoding.");
            for (var i = 0; i < bytes.Length; i += 2)
                password.AppendChar((char)(bytes[i] | bytes[i + 1] << 8));
            password.MakeReadOnly();
        }
        catch { password.Dispose(); throw; }
        finally { CryptographicOperations.ZeroMemory(bytes); }
        return password;
    }

    public static void RequireTarget(string target)
    {
        if (target is not ("AzLHOST1" or "AzLHOST2")) throw new InvalidOperationException("Node target not allowed.");
    }

    public static WSManConnectionInfo CreateConnection(PSCredential credential, string target = NodeName)
    {
        RequireTarget(target);
        return new(
        new Uri($"http://{target}.jumpstart.local:5985/wsman"),
        $"http://schemas.microsoft.com/powershell/{Endpoint}", credential)
    {
        AuthenticationMechanism = AuthenticationMechanism.Kerberos,
        OpenTimeout = 10000,
        OperationTimeout = 10000,
        CancelTimeout = 1000,
        MaximumReceivedDataSizePerCommand = MaximumResponseBytes,
        MaximumReceivedObjectSize = 4096,
        MaximumConnectionRedirectionCount = 0,
        NoEncryption = false
        };
    }

    public static NodeIdentity Validate(PSObject result, Guid correlation, string target = NodeName)
    {
        RequireTarget(target);
        string Text(string name, int max)
        {
            var text = result.Properties[name]?.Value as string;
            if (string.IsNullOrEmpty(text) || text.Length > max || text.Any(char.IsControl))
                throw new InvalidOperationException("Invalid diagnostic field.");
            return text;
        }
        var machine = Text("Machine", 32);
        var domain = Text("Domain", 64);
        var os = Text("OsVersion", 32);
        var caller = Text("ConnectingIdentity", 80);
        var execution = Text("ExecutionIdentity", 160);
        var returnedCorrelation = Text("CorrelationId", 36);
        if (!machine.Equals(target, StringComparison.OrdinalIgnoreCase) || domain != "jumpstart.local" ||
            !Regex.IsMatch(os, @"^\d{1,5}\.\d{1,5}\.\d{1,5}\.\d{1,5}$") ||
            !caller.Equals(@"jumpstart\svcMcpNodeRead", StringComparison.OrdinalIgnoreCase) ||
            !Regex.IsMatch(execution, @"^WinRM Virtual Users\\WinRM VA_\d+_jumpstart_svcMcpNodeRead$", RegexOptions.IgnoreCase) ||
            result.Properties["IsAdministrator"]?.Value is not false ||
            returnedCorrelation != correlation.ToString("D"))
            throw new InvalidOperationException("Diagnostic identity validation failed.");
        return new(target, machine, domain, os, caller, execution, false, "Kerberos", returnedCorrelation);
    }
}
