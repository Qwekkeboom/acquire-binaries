# Acquire Binaries
Standalone Windows, Linux and MacOS binaries for Fox-IT's [acquire](https://github.com/fox-it/acquire) tool.

**PLEASE BE AWARE!**

These binaries are not well tested and this repository is not associated with Fox-IT or NCC Group Plc under any circumstances. Please see the original repository for [copyright and license](https://github.com/fox-it/acquire#copyright-and-license) informations.

## Releasing

1. Bump `VERSION` in `.github/workflows/binaries.yml` to the acquire release to package.
2. Commit and push to `main` (every push builds; only tags release).
3. Tag the same number and push it: `git tag <VERSION> && git push origin <VERSION>`.
4. After all four builds pass, a **draft** GitHub Release appears with the renamed
   binaries and a `SHA256SUMS` file. Review and publish it.

## Known limitations

- `pycryptodome` is not packaged, so output encryption is unavailable.
- The native Rust extensions of `dissect.util` (lz4/lzo decompression, crc32c) are
  excluded; the pure-Python fallbacks are used.
- The Linux (musl) build uses the `esxi-compatibility` branch of fox-it's PyOxidizer fork.
- Local builds require `pyoxidizer build ... --var flavor <flavor> --var version <X>`.
