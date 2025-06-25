{ stdenvNoCC, src, neovim }:
stdenvNoCC.mkDerivation {
  name = "vim-dirtytalk";
  inherit src;

  nativeBuildInputs = [ neovim ];

  buildPhase = ''
    cat wordlists/*.words > allwords
    nvim -u NONE -i NONE -n --headless -c ":mkspell programming allwords" -c ':q'
  '';

  installPhase = ''
    mkdir -p $out/spell
    cp *.spl $out/spell
  '';
}

