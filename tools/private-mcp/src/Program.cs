using System.Net;
using System.Security.Principal;
using Microsoft.Extensions.Logging.EventLog;
using PrivateMcp;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.Sources.Clear();
builder.Configuration.AddJsonFile(Path.Combine(AppContext.BaseDirectory, "boundary.local.json"),
    optional: false, reloadOnChange: false);
builder.Services.AddWindowsService(options => options.ServiceName = "LocalBoxPrivateMcp");
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(options => options.SingleLine = true);
if (OperatingSystem.IsWindows())
    builder.Logging.AddEventLog(options =>
    {
        if (!OperatingSystem.IsWindows()) return;
        options.SourceName = "LocalBoxPrivateMcp";
        options.LogName = "Application";
        options.Filter = (category, _) =>
            category == "BoundaryAudit" || category == typeof(BoundaryTools).FullName;
    });
builder.Logging.AddFilter((category, _) =>
    category == "BoundaryAudit" || category == typeof(BoundaryTools).FullName);
// Windows service hosting otherwise defaults the Event Log provider to Warning.
if (OperatingSystem.IsWindows())
{
    builder.Logging.AddFilter<EventLogLoggerProvider>("BoundaryAudit", LogLevel.Information);
    builder.Logging.AddFilter<EventLogLoggerProvider>(typeof(BoundaryTools).FullName, LogLevel.Information);
}
var settings = builder.Configuration.Get<BoundarySettings>()
    ?? throw new InvalidOperationException("Boundary configuration is required.");
settings.Validate();
if (!OperatingSystem.IsWindows())
    throw new InvalidOperationException("The production host must be Windows.");
using (var identity = WindowsIdentity.GetCurrent())
{
    if (identity.IsSystem || new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator) ||
        identity.Groups?.Contains(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null)) == true)
        throw new InvalidOperationException("Run under a dedicated non-administrator service identity.");
}
var certificate = settings.LoadCertificate();
builder.WebHost.ConfigureKestrel(options =>
{
    options.AddServerHeader = false;
    options.Limits.MaxRequestBodySize = 8192;
    options.Limits.MaxRequestHeadersTotalSize = 8192;
    options.Limits.MaxConcurrentConnections = 16;
    options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(10);
    options.Listen(IPAddress.Parse(settings.ListenAddress), settings.Port, listen => listen.UseHttps(https =>
    {
        https.ServerCertificate = certificate;
        https.SslProtocols = System.Security.Authentication.SslProtocols.Tls12 | System.Security.Authentication.SslProtocols.Tls13;
        https.HandshakeTimeout = TimeSpan.FromSeconds(10);
    }));
});
BoundaryApplication.ConfigureServices(builder, settings);
await BoundaryApplication.ConfigurePipeline(builder.Build(), settings).RunAsync();
