# Embedded Lyon region

CI downloads the signed Lyon package from the `region-lyon` release into
this folder before building the app (see `.github/workflows/ci.yml`). The
app installs it on first launch, after checking the signature and every
file hash. Local builds without these files simply have no embedded region.

The data files are not committed.
