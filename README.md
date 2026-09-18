# vfox-pub

A [mise](https://mise.jdx.dev) backend plugin for Dart packages from [pub.dev](https://pub.dev).

The plugin installs a package with `dart pub global activate` into a separate directory for
each version. Then it puts the package executables on your PATH.

## Install

```sh
mise plugin install pub https://github.com/hleinone/vfox-pub
```

## Use

```sh
mise use pub:protoc_plugin@22.3.0
```

This adds the tool to your `mise.toml`:

```toml
[tools]
"pub:protoc_plugin" = "22.3.0"
```

Other commands:

```sh
mise ls-remote pub:protoc_plugin
mise install pub:melos@latest
mise exec pub:melos -- melos --version
```

## Requirements

- The `dart` executable must be on PATH when a tool is installed and when it runs. Install
  Dart with mise (`mise use dart@latest` or `mise use flutter@latest`) or in another way.
- Network access to pub.dev.

## How it works

1. `BackendListVersions` reads `https://pub.dev/api/packages/<name>`. It returns all versions
   that are not retracted.
2. `BackendInstall` runs `dart pub global activate <name> <version>` with `PUB_CACHE` set to
   the mise install directory. Each version has its own pub cache. The plugin then adds
   `export PUB_CACHE=...` to each launcher script that pub created. Without this line, a
   launcher fails after a Dart SDK upgrade, because pub rebuilds the snapshot from the default
   cache, where the package is not active.
3. `BackendExecEnv` adds `<install directory>/bin` to PATH.

Each installed version downloads its own copy of the package dependencies.

## Limitations

- Only pub.dev is supported. Private pub servers are not supported yet.
- Windows is not supported yet.

## Develop

```sh
mise install       # stylua, lua-language-server, actionlint
mise run format
mise run lint
mise run test      # links this directory as the pub plugin and installs protoc_plugin
mise run ci        # lint and test
```

`mise run test` replaces a plugin named `pub` on your machine with a link to this directory.

## License

MIT
