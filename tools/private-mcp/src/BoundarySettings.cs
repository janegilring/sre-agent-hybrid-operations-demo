using System.Net;
using System.Net.Sockets;
using System.Globalization;
using System.Security.Cryptography.X509Certificates;

namespace PrivateMcp;

public sealed record BoundarySettings
{
    public required Guid TenantId { get; init; }
    public required Guid Audience { get; init; }
    public required Guid CallerClientId { get; init; }
    public required Guid CallerObjectId { get; init; }
    public required string Hostname { get; init; }
    public required string CertificateThumbprint { get; init; }
    public required string ListenAddress { get; init; }
    public required string[] AllowedSourceCidrs { get; init; }
    public string HostTarget { get; init; } = "LocalBox-Client";
    public int Port { get; init; } = 8443;
    public bool NodeIdentityEnabled { get; init; }
    public bool ReadCapabilitiesEnabled { get; init; }
    public ServerTarget[] Servers { get; init; } = [];
    public const string RequiredRole = "LocalBox.Diagnostics.Read";
    public string Issuer => $"https://login.microsoftonline.com/{TenantId:D}/v2.0";

    public void Validate()
    {
        if (HostTarget is null || !System.Text.RegularExpressions.Regex.IsMatch(HostTarget, "^[A-Za-z0-9][A-Za-z0-9-]{0,14}$"))
            throw new InvalidOperationException("An explicit bounded host identity is required.");
        if (Servers is null || Servers.Length > 8 || Servers.Select(s => s.Id).Distinct(StringComparer.Ordinal).Count() != Servers.Length)
            throw new InvalidOperationException("Invalid server allowlist.");
        foreach (var server in Servers) server.Validate();
        if (new[] { TenantId, Audience, CallerClientId, CallerObjectId }.Any(id => id == Guid.Empty))
            throw new InvalidOperationException("Explicit tenant, audience and caller identifiers are required.");
        if (Uri.CheckHostName(Hostname) != UriHostNameType.Dns || !Hostname.Contains('.') ||
            Hostname.EndsWith(".local", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("A controlled TLS DNS hostname is required.");
        if (!System.Text.RegularExpressions.Regex.IsMatch(CertificateThumbprint, "^[0-9A-Fa-f]{40}$"))
            throw new InvalidOperationException("A LocalMachine certificate thumbprint is required.");
        var address = Ipv4SourceCidr.ParseAddress(ListenAddress);
        if (!Ipv4SourceCidr.IsUnicast(address) || Port != 8443)
            throw new InvalidOperationException("An explicit unicast IPv4 listener and port 8443 are required.");
        _ = ParseAllowedSourceCidrs();
    }

    public Ipv4SourceCidr[] ParseAllowedSourceCidrs()
    {
        if (AllowedSourceCidrs is not { Length: >= 1 and <= 16 })
            throw new InvalidOperationException("One to sixteen explicit source CIDRs are required.");
        return AllowedSourceCidrs.Select(Ipv4SourceCidr.Parse).ToArray();
    }

    public X509Certificate2 LoadCertificate()
    {
        using var store = new X509Store(StoreName.My, StoreLocation.LocalMachine);
        store.Open(OpenFlags.ReadOnly);
        var matches = store.Certificates.Find(X509FindType.FindByThumbprint, CertificateThumbprint, false);
        if (matches.Count != 1)
            throw new InvalidOperationException("The configured machine certificate was not found uniquely.");
        var certificate = matches[0];
        var serverAuthentication = certificate.Extensions.OfType<X509EnhancedKeyUsageExtension>()
            .Any(extension => extension.EnhancedKeyUsages.Cast<System.Security.Cryptography.Oid>()
                .Any(usage => usage.Value == "1.3.6.1.5.5.7.3.1"));
        using var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = X509RevocationMode.Online;
        chain.ChainPolicy.UrlRetrievalTimeout = TimeSpan.FromSeconds(10);
        chain.ChainPolicy.ApplicationPolicy.Add(new("1.3.6.1.5.5.7.3.1"));
        if (!certificate.HasPrivateKey || !serverAuthentication ||
            !certificate.MatchesHostname(Hostname, allowCommonName: false) ||
            !chain.Build(certificate))
            throw new InvalidOperationException("TLS key, SAN, validity, server EKU or chain validation failed.");
        return certificate;
    }

    public readonly record struct Ipv4SourceCidr
    {
        private readonly uint network;
        private readonly uint broadcast;

        private Ipv4SourceCidr(uint network, uint broadcast)
        {
            this.network = network;
            this.broadcast = broadcast;
        }

        public static Ipv4SourceCidr Parse(string cidr)
        {
            var parts = cidr?.Split('/');
            if (parts is not { Length: 2 } ||
                !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var prefix) ||
                prefix is < 1 or > 32 or 31 || parts[1] != prefix.ToString(CultureInfo.InvariantCulture))
                throw new InvalidOperationException("A canonical IPv4 source CIDR with prefix /1 through /30 or an exact /32 host is required.");
            var network = ParseAddress(parts[0]);
            var mask = uint.MaxValue << (32 - prefix);
            var broadcast = network | ~mask;
            if ((network & mask) != network || !IsUnicast(network) || !IsUnicast(broadcast))
                throw new InvalidOperationException("Source CIDRs must be canonical unicast IPv4 networks with no host bits.");
            return new(network, broadcast);
        }

        public bool Contains(IPAddress? address)
        {
            if (address is null) return false;
            if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
            if (address.AddressFamily != AddressFamily.InterNetwork) return false;
            var value = ToUInt32(address);
            // Preserve subnet host semantics: neither the network nor broadcast is a caller.
            return network == broadcast ? value == network && IsUnicast(value) : value > network && value < broadcast;
        }

        internal static uint ParseAddress(string address)
        {
            // IPAddress also accepts abbreviated, integer and hexadecimal forms; only canonical dotted decimal is configuration.
            if (!IPAddress.TryParse(address, out var parsed) || parsed.AddressFamily != AddressFamily.InterNetwork ||
                !string.Equals(address, parsed.ToString(), StringComparison.Ordinal))
                throw new InvalidOperationException("A canonical dotted-decimal IPv4 address is required.");
            return ToUInt32(parsed);
        }

        internal static bool IsUnicast(uint address) => address >= 0x01000000 && address < 0xe0000000;

        private static uint ToUInt32(IPAddress address)
        {
            var bytes = address.GetAddressBytes();
            return ((uint)bytes[0] << 24) | ((uint)bytes[1] << 16) | ((uint)bytes[2] << 8) | bytes[3];
        }
    }
}
