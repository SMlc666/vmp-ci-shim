# android_vmp release package

Included binaries:

- `vmp-lifter`
- `vmp-runner`
- `vmp-bench`
- `maps_dumper`
- `lift_bench`

Current CLI entry points:

- `protect` - protect selected functions in an ARM64 `.so`
- `coverage` - scan ELF coverage and optionally update `README.md`
- `pack` - pack a protected `.so`
- `analyze` - emit advisory capability recommendations
- `oracle` - run the three-way differential oracle

Examples:

- `./bin/vmp-lifter protect --input fixtures/simple_add.so --output /tmp/simple_add_protected.so --funcs simple_add --seed 0x42 --on-unsupported fail`
- `./bin/vmp-lifter protect --input fixtures/simple_add.so --list-symbols`
- `./bin/vmp-lifter coverage --input vmp-lifter/fixtures/corpus/libc.so`
- `./bin/vmp-lifter pack --input /tmp/simple_add_protected.so --output /tmp/simple_add_packed.so --seed 0x42`
- `./bin/vmp-lifter analyze --input vmp-lifter/fixtures/simple_add.so --funcs simple_add`
- `./bin/vmp-lifter oracle --input vmp-lifter/fixtures/e2e/e2e_mba_smoke/orig.so --func mba_smoke --signature '(i32, i32, i32) -> i32' --args '[1,2,3]'`

