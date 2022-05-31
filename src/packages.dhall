let upstream =
      https://github.com/purescript/package-sets/releases/download/psc-0.15.2-20220531/packages.dhall
        sha256:278d3608439187e51136251ebf12fabda62d41ceb4bec9769312a08b56f853e3

in  upstream
  with purescript-threejs =
    { dependencies = [ "prelude", "effect" ]
    , repo = "https://github.com/dktr0/purescript-threejs"
    , version = "44e33bc16138ddf0492d4939ed5b993751b298c5"
    }
  with purescript-tempi =
    { dependencies = [ "console", "datetime", "effect", "now", "prelude", "psci-support", "rationals"]
    , repo = "https://github.com/dktr0/purescript-tempi"
    , version = "7021e7e7c3e55fd1be7558f7853ee213b1960bf0"
    }
