# RADE (FreeDV neural voice) — vendored dependency

Pure-C port of RADE V1 ("no Python"), the neural Radio Autoencoder that is the
default on-air FreeDV HF voice mode as of FreeDV 2.0.0. This is the same C
implementation the official FreeDV GUI 2.2.x uses — NOT the PyTorch reference.

- `src/` — librade library sources (compiled directly into the app target).
  Built with `-DRADE_PYTHON_FREE=1 -DIS_BUILDING_RADE_API=1`. Neural-net weights
  are compiled in (`rade_dec_data.c`); `rade_open()` ignores its model-file arg,
  so there is no external model/weights file to ship.
- Tool/test `main()` files and `kiss_fft*` are intentionally not vendored
  (librade uses opus's FFT; the kiss names collide with the vendored codec2).

Depends on `../opus` (universal `libopus.a` built with FARGAN/OSCE/DRED).

Pinned upstream: peterbmarks/radae_nopy @ b2891023f3aecdf8b1793618000b1be6bcb2c4d1
Rebuild both this and opus with: `scripts/build_librade_opus.sh`
