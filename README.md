# PipeWire with AAC support

Debian packages for PipeWire with AAC (FDK-AAC) Bluetooth codec enabled,
built from official Debian sid sources.

## Using the apt repository

Add the repository:
```bash
sudo tee /etc/apt/sources.list.d/pipewire-aac.sources <<'EOF'
Types: deb
URIs: https://andersfugmann.github.io/pipewire-aac
Suites: ./
Trusted: yes
EOF
sudo apt-get update
```

Upgrade PipeWire:
```bash
sudo apt-get upgrade
```

## Building locally

```bash
make deps      # install build dependencies
make all       # fetch, patch, build, generate repo
sudo make install-repo  # register as local apt source
```

See `make help` for all targets.
