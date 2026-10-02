using System.ComponentModel;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using ModelContextProtocol;
using ModelContextProtocol.Server;
using ModelContextProtocol.Protocol;

namespace PrivateMcp;

public static class BoundaryApplication
{
    public static void ConfigureServices(WebApplicationBuilder builder, BoundarySettings settings)
    {
        settings.Validate();
        builder.Services.AddSingleton(settings);
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddSingleton<IHostIdentity, HostIdentity>();
        builder.Services.AddSingleton<INodeIdentityReader, NodeIdentityReader>();
        builder.Services.AddSingleton<INodeCapabilityReader, NodeCapabilityReader>();
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.Authority = settings.Issuer;
                options.Audience = settings.Audience.ToString("D");
                options.RequireHttpsMetadata = true;
                options.MapInboundClaims = false;
                options.SaveToken = false;
                options.IncludeErrorDetails = false;
                options.BackchannelTimeout = TimeSpan.FromSeconds(15);
                options.TokenValidationParameters = new()
                {
                    ValidateIssuer = true,
                    ValidIssuer = settings.Issuer,
                    ValidateAudience = true,
                    ValidAudience = settings.Audience.ToString("D"),
                    IgnoreTrailingSlashWhenValidatingAudience = false,
                    ValidateIssuerSigningKey = true,
                    RequireSignedTokens = true,
                    RequireExpirationTime = true,
                    ValidateLifetime = true,
                    ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
                    ClockSkew = TimeSpan.FromSeconds(30),
                    RoleClaimType = "roles",
                    NameClaimType = "oid"
                };
            });
        builder.Services.AddAuthorization(options =>
            options.AddPolicy("DiagnosticCaller", policy => policy
                .RequireAuthenticatedUser()
                .RequireAssertion(context => IsAuthorized(context.User, settings))));
        builder.Services.AddSingleton<IServerExecutor, ServerExecutor>();
        builder.Services.AddSingleton<ServerReader>();
        var mcp = builder.Services.AddMcpServer()
            .WithHttpTransport()
            .WithRequestFilters(filters => filters.AddCallToolFilter(next => async (context, cancellationToken) =>
            {
                var parameters = context.Params;
                if (parameters is not null && ServerTools.IsTool(parameters.Name))
                {
                    if (ServerTools.AllowedArguments(settings, parameters.Name, parameters.Arguments))
                        return await next(context, cancellationToken);
                    return new CallToolResult
                    {
                        IsError = true,
                        Content = [new TextContentBlock { Text = "Server action or arguments not allowed." }]
                    };
                }
                if ((parameters?.Name != "get_boundary_identity" &&
                     !(settings.NodeIdentityEnabled && parameters?.Name == "get_node_identity") &&
                     !(settings.ReadCapabilitiesEnabled && parameters?.Name is "get_health_snapshot" or "get_vm_checkpoint_inventory")) ||
                    parameters.Arguments is not { Count: 1 } arguments ||
                    !arguments.ContainsKey("target"))
                {
                    var http = context.Services?.GetService<IHttpContextAccessor>()?.HttpContext;
                    context.Services?.GetService<ILogger<BoundaryTools>>()?.LogInformation(
                        "Boundary tool {Correlation} outcome ActionDenied", http?.Items["correlation"]);
                    return new CallToolResult
                    {
                        IsError = true,
                        Content = [new TextContentBlock { Text = "Action or arguments not allowed." }]
                    };
                }
                return await next(context, cancellationToken);
            }))
            .WithTools<BoundaryTools>();
        if (settings.Servers.Length > 0) mcp.WithTools<ServerTools>();
    }

    public static bool IsAuthorized(ClaimsPrincipal user, BoundarySettings settings) =>
        user.Identity?.IsAuthenticated == true &&
        SingleClaim(user, "ver", "2.0") &&
        SingleClaim(user, "tid", settings.TenantId.ToString("D")) &&
        SingleClaim(user, "azp", settings.CallerClientId.ToString("D")) &&
        SingleClaim(user, "oid", settings.CallerObjectId.ToString("D")) &&
        !user.HasClaim(c => c.Type == "scp") &&
        user.HasClaim("roles", BoundarySettings.RequiredRole);

    private static bool SingleClaim(ClaimsPrincipal user, string type, string value)
    {
        var claims = user.FindAll(type).ToArray();
        return claims.Length == 1 && string.Equals(claims[0].Value, value, StringComparison.Ordinal);
    }

    public static WebApplication ConfigurePipeline(WebApplication app, BoundarySettings settings)
    {
        var allowedSources = settings.ParseAllowedSourceCidrs();
        app.Use(async (context, next) =>
        {
            var correlation = Guid.NewGuid().ToString("D");
            context.Items["correlation"] = correlation;
            context.Response.Headers["X-Correlation-ID"] = correlation;
            var logger = context.RequestServices.GetRequiredService<ILoggerFactory>().CreateLogger("BoundaryAudit");
            try
            {
                // No forwarded headers are trusted. This service terminates TLS itself.
                if (!context.Request.IsHttps || context.Request.Host.Host != settings.Hostname ||
                    !allowedSources.Any(network => network.Contains(context.Connection.RemoteIpAddress)) ||
                    context.Request.Headers.ContainsKey("Origin"))
                {
                    context.Response.StatusCode = StatusCodes.Status403Forbidden;
                    return;
                }
                await next(context);
            }
            catch
            {
                if (!context.Response.HasStarted) context.Response.StatusCode = 500;
                else context.Abort();
            }
            finally
            {
                logger.LogInformation("Boundary request {Correlation} source {Source} status {Status}",
                    correlation, context.Connection.RemoteIpAddress?.ToString(), context.Response.StatusCode);
            }
        });
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapMcp("/mcp").RequireAuthorization("DiagnosticCaller");
        return app;
    }
}

[McpServerToolType]
public sealed class BoundaryTools(IHttpContextAccessor accessor, BoundarySettings settings, ILogger<BoundaryTools> logger,
    IHostIdentity host, INodeIdentityReader node, INodeCapabilityReader capabilities)
{
    [McpServerTool(Name = "get_health_snapshot", ReadOnly = true, Destructive = false, OpenWorld = false)]
    [Description("Bounded read-only localboxcluster health observations from both approved nodes. Explicit provider denials, missing sources and UNKNOWN health; never repairs or claims exhaustive health.")]
    public async Task<HealthSnapshot> GetHealthSnapshot(
        [Description("Exact approved environment: localboxcluster.")] string target, CancellationToken cancellationToken)
    {
        var correlation = AuthorizeCapability(target);
        var result = await capabilities.ReadHealthAsync(correlation, cancellationToken);
        AuditCapability(correlation, "health_snapshot", result.Status);
        return result;
    }

    [McpServerTool(Name = "get_vm_checkpoint_inventory", ReadOnly = true, Destructive = false, OpenWorld = false)]
    [Description("Read-only Hyper-V VM/checkpoint observations across both approved nodes, including offline VMs, stable ID deduplication and explicit incomplete coverage. No disk contents, Azure control-plane ownership or checkpoint changes.")]
    public async Task<VmCheckpointInventory> GetVmCheckpointInventory(
        [Description("Exact approved environment: localboxcluster.")] string target, CancellationToken cancellationToken)
    {
        var correlation = AuthorizeCapability(target);
        var result = await capabilities.ReadInventoryAsync(correlation, cancellationToken);
        AuditCapability(correlation, "vm_checkpoint_inventory", result.Status);
        return result;
    }

    private Guid AuthorizeCapability(string target)
    {
        var context = accessor.HttpContext;
        if (context is null || !BoundaryApplication.IsAuthorized(context.User, settings))
            throw new McpException("Caller not authorized.");
        if (!settings.ReadCapabilitiesEnabled || target != "localboxcluster")
            throw new McpException("Capability target not allowed.");
        return Guid.Parse((string)context.Items["correlation"]!);
    }

    private void AuditCapability(Guid correlation, string operation, string status) =>
        logger.LogInformation("Boundary tool {Correlation} operation {Operation} outcome {Status} source {Source} callerObject {CallerObject} callerClient {CallerClient} audience {Audience}",
            correlation, operation, status, accessor.HttpContext?.Connection.RemoteIpAddress?.ToString(),
            settings.CallerObjectId, settings.CallerClientId, settings.Audience);

    [McpServerTool(Name = "get_node_identity", ReadOnly = true, Destructive = false, OpenWorld = false)]
    [Description("Read AzLHOST1 or AzLHOST2 identity via server-side Kerberos and a nonadministrator, fixed JEA diagnostic. No commands, scripts or arbitrary endpoints accepted.")]
    public async Task<NodeIdentity> GetNodeIdentity(
        [Description("Exact allowlisted node: AzLHOST1 or AzLHOST2.")] string target, CancellationToken cancellationToken)
    {
        var context = accessor.HttpContext;
        if (context is null || !BoundaryApplication.IsAuthorized(context.User, settings))
            throw new McpException("Caller not authorized.");
        var correlation = (string)context.Items["correlation"]!;
        if (!settings.NodeIdentityEnabled || target is not ("AzLHOST1" or "AzLHOST2"))
        {
            logger.LogInformation("Boundary tool {Correlation} outcome NodeTargetDenied", correlation);
            throw new McpException("Node target not allowed.");
        }
        try
        {
            var identity = await node.ReadAsync(target, Guid.Parse(correlation), cancellationToken);
            logger.LogInformation(
                "Boundary tool {Correlation} outcome NodeReadSucceeded target {Target} authentication Kerberos execution {Execution} source {Source} callerObject {CallerObject} callerClient {CallerClient} audience {Audience}",
                correlation, target, identity.ExecutionIdentity, context.Connection.RemoteIpAddress?.ToString(),
                settings.CallerObjectId, settings.CallerClientId, settings.Audience);
            return identity;
        }
        catch
        {
            logger.LogInformation("Boundary tool {Correlation} outcome NodeReadFailed", correlation);
            throw new McpException("Node diagnostic unavailable; no authentication fallback attempted.");
        }
    }

    [McpServerTool(Name = "get_boundary_identity", ReadOnly = true, Destructive = false, OpenWorld = false)]
    [Description("Read the identity of the server-configured MCP host. Does not execute commands or contact nested nodes.")]
    public BoundaryIdentity GetBoundaryIdentity(
        [Description("Exact operator-configured host target.")] string target)
    {
        var context = accessor.HttpContext;
        if (context is null || !BoundaryApplication.IsAuthorized(context.User, settings))
            throw new McpException("Caller not authorized.");
        var correlation = (string)context.Items["correlation"]!;
        if (target != settings.HostTarget)
        {
            logger.LogInformation("Boundary tool {Correlation} outcome TargetDenied", correlation);
            throw new McpException("Target not allowed.");
        }
        var machine = host.MachineName;
        if (!string.Equals(machine, target, StringComparison.OrdinalIgnoreCase))
        {
            logger.LogInformation("Boundary tool {Correlation} outcome HostMismatch", correlation);
            throw new McpException("Host identity does not match the configured target.");
        }
        logger.LogInformation(
            "Boundary tool {Correlation} outcome ReadSucceeded source {Source} callerObject {CallerObject} callerClient {CallerClient} audience {Audience}",
            correlation, context.Connection.RemoteIpAddress?.ToString(), settings.CallerObjectId,
            settings.CallerClientId, settings.Audience);
        return new(settings.HostTarget, machine, OperatingSystem.IsWindows(), correlation);
    }
}

public sealed record BoundaryIdentity(string Target, string Machine, bool Windows, string CorrelationId);

public interface IHostIdentity
{
    string MachineName { get; }
}

public sealed class HostIdentity : IHostIdentity
{
    public string MachineName => Environment.MachineName;
}
