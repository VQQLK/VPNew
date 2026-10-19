using System.Text.Json;

namespace MyVPN
{
    public class RealitySettings
    {
        public bool   AllowInsecure { get; set; } = false;
        public string Fingerprint   { get; set; } = "chrome";
        public string ServerName    { get; set; } = string.Empty;
        public string PublicKey     { get; set; } = string.Empty;
        public string ShortId       { get; set; } = string.Empty;
        public string SpiderX       { get; set; } = "/";
    }

    public static class VpnConfig
    {
        public static RealitySettings CreateRealityConfig(string publicKey, string shortId)
        {
            return new RealitySettings
            {
                ServerName    = "www.microsoft.com",
                PublicKey     = publicKey,
                ShortId       = shortId,
                AllowInsecure = false,
                Fingerprint   = "chrome"
            };
        }

        public static string BuildClientJson(string uuid, string serverIp,
                                             string publicKey, string shortId)
        {
            var r = CreateRealityConfig(publicKey, shortId);
            var json = new
            {
                outbounds = new[]
                {
                    new
                    {
                        protocol = "vless",
                        settings = new
                        {
                            vnext = new[]
                            {
                                new
                                {
                                    address = serverIp,
                                    port = 443,
                                    users = new[]
                                    {
                                        new
                                        {
                                            id = uuid,
                                            encryption = "none",
                                            flow = "xtls-rprx-vision"
                                        }
                                    }
                                }
                            }
                        },
                        streamSettings = new
                        {
                            network = "tcp",
                            security = "reality",
                            realitySettings = new
                            {
                                allowInsecure = r.AllowInsecure,
                                fingerprint   = r.Fingerprint,
                                serverName    = r.ServerName,
                                publicKey     = r.PublicKey,
                                shortId       = r.ShortId,
                                spiderX       = r.SpiderX
                            }
                        },
                        tag = "proxy"
                    }
                }
            };
            return JsonSerializer.Serialize(json, new JsonSerializerOptions { WriteIndented = true });
        }
    }
}
