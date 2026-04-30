_args:

let
  # Helper to create a packages entry
  mkPackages = { buckets ? [ ], apps ? [ ], global_apps ? [ ] }: {
    inherit buckets apps global_apps;
  };

  # Helper to create a firewall rule
  mkFirewallRule = { name, proto, port, remote ? "Any" }: {
    inherit name proto port remote;
  };

  # Helper to create a file enforcement entry
  mkFile = { path, content, encoding ? "utf8" }: {
    inherit path content encoding;
  };

  # Helper to create a registry entry
  mkRegistry = { path, name, value, type ? "String" }: {
    inherit path name value type;
  };

  # Helper to create a service entry
  mkService = { name, state ? "Running", startup ? "Automatic" }: {
    inherit name state startup;
  };

  # Helper to create a download entry
  mkDownload = { url, path, hash ? null, hashAlgorithm ? "SHA256" }: {
    inherit url path hash hashAlgorithm;
  };

  # Helper to create a script entry
  mkScript = { name, command ? null, path ? null, unless ? null, creates ? null }: {
    inherit name command path unless creates;
  };

in
{
  # Generate the full Bifrost configuration
  mkConfig =
    { users ? [ ]
    , packages ? { }
    , system ? { }
    , networking ? { }
    , files ? [ ]
    , registry ? [ ]
    , services ? [ ]
    , downloads ? [ ]
    , scripts ? [ ]
    }: {
      inherit users packages system networking files registry services downloads scripts;
    };

  # Standard helpers
  inherit mkPackages mkFirewallRule mkFile mkRegistry mkService mkDownload mkScript;
}
