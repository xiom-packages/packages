# Vec[Vec[UInt8]] inner-buffer corruption on v0.65.3 candidates

Observed while re-measuring `xiom.transport` on the source candidates
`46f7f50aa` (sha256 `8BB859BB...`) and `ab97014d9` (sha256 `6D9F2ED0...`).

The conformance check `sim: drop table drops, dup table duplicates (+1ms),
reorder displaces deterministically` (`tests/suite_backends.xi`, b4) fails
35/36 on both candidates; it is green on the official v0.65.1 binary and was
green on the earlier `e8180229f` build.

Repro: compile/run `sim_vecvec_corruption.xi` from the package root with the
candidate compiler (`--run docs/repro/sim_vecvec_corruption.xi`).

Expected (v0.65.1):

```
r1[0]=k1
r2[0]=k2
r2[1]=k2
r2[2]=k0
k0=1 k2=2
```

`46f7f50aa`:

```
r1[0]=k2
r2[0]=r2
r2[1]=k2
r2[2]=k0
k0=1 k2=1
```

`ab97014d9`:

```
r1[0]=k2
r2[0]=k2
r2[1]=k2
r2[2]=k2
k0=0 k2=3
```

The function under test returns `Vec[Vec[UInt8]]` built by pushing inner
buffers. The values are overwritten/aliased, so the suspect is the
`Vec[Vec]` element-drop ownership transfer (`46f7f50aa`); the earlier
`Vec[Struct{Vec}]` tag (`6a58a60e1`) is also in both failing candidates.
Nothing in this package changed between the green and red runs.
