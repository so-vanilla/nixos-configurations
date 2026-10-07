{
  stdenv,
  fetchzip,
  lib,
}:
stdenv.mkDerivation rec {
  pname = "kotlin-lsp";
  version = "261.13587.0";

  src = fetchzip {
    url = "https://download-cdn.jetbrains.com/kotlin-lsp/${version}/kotlin-lsp-${version}-mac-aarch64.zip";
    stripRoot = false;
    hash = "sha256-zwlzVt3KYN0OXKr6sI9XSijXSbTImomSTGRGa+3zCK8=";
  };

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/lib/kotlin-lsp $out/bin
    cp -r lib jre native kotlin-lsp.sh $out/lib/kotlin-lsp/
    chmod +x $out/lib/kotlin-lsp/kotlin-lsp.sh
    chmod +x $out/lib/kotlin-lsp/jre/Contents/Home/bin/java
    ln -s $out/lib/kotlin-lsp/kotlin-lsp.sh $out/bin/kotlin-lsp
  '';

  meta = with lib; {
    description = "JetBrains Kotlin Language Server";
    homepage = "https://www.jetbrains.com/";
    platforms = [ "aarch64-darwin" ];
  };
}
