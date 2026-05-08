using System;

namespace MyVPN
{
    /// <summary>
    /// RealitySettings — настройки XTLS-Reality для клиента.
    ///
    /// Изменения по инструкции AC_3:
    /// - Fingerprint: "chrome" (было "firefox")
    /// - PublicKey вместо PrivateKey (клиент использует публичный ключ сервера)
    /// - CreateRealityConfig принимает publicKey напрямую (не из файла)
    /// </summary>
    public class RealitySettings
    {
        public bool   AllowInsecure { get; set; } = false;
        public string Fingerprint   { get; set; } = "chrome";
        public string ServerName    { get; set; } = string.Empty;
        public string PublicKey     { get; set; } = string.Empty;
        public string ShortId       { get; set; } = string.Empty;
        public string SpiderX       { get; set; } = "/";
    }

    public class VpnConfig
    {
        /// <summary>
        /// Фабрика, встраивающая публичный ключ напрямую (не через файл).
        /// publicKey берётся из client_config.json, сгенерированного setup_xray.sh.
        /// </summary>
        public static RealitySettings CreateRealityConfig(string publicKey, string shortId)
        {
            return new RealitySettings
            {
                ServerName    = "www.microsoft.com",
                PublicKey     = publicKey,   // публичный ключ сервера (не приватный!)
                ShortId       = shortId,
                AllowInsecure = false,
                Fingerprint   = "chrome"
            };
        }

        /// <summary>
        /// Строит полный JSON-конфиг для Xray-клиента.
        /// </summary>
        public static string BuildClientJson(string uuid, string serverIp,
                                             string publicKey, string shortId)
        {
            var r = CreateRealityConfig(publicKey, shortId);
            return $@"{{
  ""outbounds"": [{{
    ""protocol"": ""vless"",
    ""settings"": {{
      ""vnext"": [{{
        ""address"": ""{serverIp}"",
        ""port"": 443,
        ""users"": [{{
          ""id"": ""{uuid}"",
          ""encryption"": ""none"",
          ""flow"": ""xtls-rprx-vision""
        }}]
      }}]
    }},
    ""streamSettings"": {{
      ""network"": ""tcp"",
      ""security"": ""reality"",
      ""realitySettings"": {{
        ""allowInsecure"": {r.AllowInsecure.ToString().ToLower()},
        ""fingerprint"": ""{r.Fingerprint}"",
        ""serverName"": ""{r.ServerName}"",
        ""publicKey"": ""{r.PublicKey}"",
        ""shortId"": ""{r.ShortId}"",
        ""spiderX"": ""{r.SpiderX}""
      }}
    }},
    ""tag"": ""proxy""
  }}]
}}";
        }
    }
}
