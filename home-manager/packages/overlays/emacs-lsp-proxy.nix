{
  lib,
  fetchFromGitHub,
  rustPlatform,
  libiconv
}:

rustPlatform.buildRustPackage rec {
  pname = "lsp-proxy";
  version = "0.5.15";

  src = fetchFromGitHub {
    owner = "jadestrong";
    repo = "lsp-proxy";
    rev = "v${version}";
    sha256 = "17ajhzchncc0m3rx3yfdjngz3bwig8sa7xpfkb3qcsnip9cbppsk";
  };

  cargoHash = "sha256-ZWmV/wCMPSuRQNn/7bI3baLYrMcoa35EVikmUDjUguw=";

  buildInputs = [ libiconv ];

  meta = with lib; {
    description = "lsp-proxy's binary server";
    homepage = "https://github.com/jadestrong/lsp-proxy";
    license = licenses.gpl3;
    maintainers = [];
  };
}
