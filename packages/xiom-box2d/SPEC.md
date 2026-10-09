# SPEC: xiom.box2d -- Box2D physics bindings (vendored C, v3.1.1)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.box2d` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Box2D -- https://github.com/erincatto/box2d |
| Upstream version | **v3.1.1** (tag; the v3 C API) |
| Upstream license | MIT (`vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); the vendored C path is portable |
| Compiler pin | v0.64.2 |

## 2. Vendored path (G2 pin)

The upstream v3.1.1 `src/` sources plus `include/box2d/` public headers are
vendored **unmodified** in `vendor/` in a flat layout: `src/*.c|h` at the
`vendor/` root and the public headers at `vendor/box2d/`. Quoted includes
(`"box2d/types.h"`, `"body.h"`) then resolve against each file's own
directory, so the xiom link line needs no `-I` passthrough. All 35 C sources
and our bridge (`src/box2d_bridge.c`) compile into the test binary with
`--c-source` (`port.args.json`). No system library, no DLL, no SDK.

### Pinned archive

| Artifact | Value |
|----------|-------|
| Download | https://github.com/erincatto/box2d/archive/refs/tags/v3.1.1.tar.gz |
| Size | 780,115 bytes |
| SHA256 (computed at vendor time) | `FB6EF914B50F4312D7D921A600EABC12318BB3C55A0B8C0B90608FA4488EF2E4` |

### Re-pin procedure

1. Download the new tag archive and record its SHA256.
2. Verify the hash before extracting.
3. Re-copy `src/*.c|h` to `vendor/` and `include/box2d/*.h` to
   `vendor/box2d/` byte-for-byte (plus `LICENSE`); do not edit vendored
   files.
4. Recompute the per-file SHA256 table below and update the version rows in
   this SPEC, `README.md`, and `AUDIT.md` in the same commit.
5. Re-run `scripts/port.ps1 -Package xiom.box2d` x2 and update
   `STATUS.json`; the version check asserts the tag (`3.1.x`).

### Per-file SHA256 (vendor tree, LF-normalized upstream bytes)

```
vendor/box2d/base.h                 20180151E976CCE32D493614D4FE47E15F3ACA982B97A7BAF8C23F80EB843479
vendor/box2d/box2d.h                F84E07C7A7DD049ACD734C9CB355F9D91E5ECCCA39AEBFD4510B13DC7B48EB6F
vendor/box2d/collision.h            EE1995FF2460E036C7DABEDDDD028D6D2F40B8FE3976B4405D611AA6C6CA8CC9
vendor/box2d/id.h                   19AE35F2B248951BC40E0BB56E23E0768063930D3A74BBFB4D433D219A0C1B27
vendor/box2d/math_functions.h       334EAB5CD04B8E7BCDB6D4D2575AA17F5E07BEE63FD92084E9759D57B6BCAE89
vendor/box2d/types.h                EA3DA532CB49978123DCA81BB3C76D66D912F89486BA1FCA9AC9C9D54D28CF60
vendor/aabb.c                       F7962C7F73D6F1AC84E96A6EAC9D1FFAE03B568E33903A1896C3AD1BC8636CB5
vendor/aabb.h                       81FD633EB290FBE6BFF18E0DB47E8BE198CE6CFCB203873F0E5D71B4D881D4A0
vendor/arena_allocator.c            A134E8BADAC17EFB8B0ECAE1A4627B90D15F3C2689669C69025F53070A838A03
vendor/arena_allocator.h            AA117611AE55D2E13DBFA3CE4562FEAD9F092EB52B0BA2B3A0FFC3CC63840A8A
vendor/array.c                      677B98644DA1C59ABF6859528AD8EBE997F5E97C225F2CCC5330C8A7F23DB157
vendor/array.h                      84F2FB5787163B58F7901A778C97D18E062F42FE9B4BA0C93CAA3A1C0E6BFBE1
vendor/atomic.h                     FAEAF41A6F88E6FAF5C804B4F610CFC33311153481D0B1FD48CC7DFA676891AF
vendor/bitset.c                     8DBAA9C8C20ED67482F5BDB3686206DE3A21AC8F34D65003997569B7A05E28CD
vendor/bitset.h                     62C5024722C2E62C9CAE21B55DFA1BD11E93302C8D061EB5DC1093C1B5E7F7D8
vendor/body.c                       EB29B16F2060BB730AD1A5936C4C61FF99B91CB3F8B55E742D8F3784600F626E
vendor/body.h                       BE819C268DF5370E93CDA1FBB096C30D8A56D976B5B514FFB353B534AA131A7C
vendor/broad_phase.c                B03D37A0FA9BA79E70B794C0ACF17568388B3AD11A30186B446701010DA38676
vendor/broad_phase.h                37E9D1649E5EFA2F56B3725CD28E24EC56A10EBB0BFE839A02C989249A29358D
vendor/constants.h                  CBAD16C4DD09B6AF9F5A1007E07A10C0B4A49AAB4E213840895E50CA81020817
vendor/constraint_graph.c           E515CB6E4196FE00F84B8E9E5D84067DB47312A68CF61309F0B462198B932455
vendor/constraint_graph.h           4887073345515772629093B199C2842631F886678986F10D53F774DEC6A7C465
vendor/contact.c                    98993EE57A91ED2FEDF9F018E47098F2C99B13E288E4C79587465C2164FD5C66
vendor/contact.h                    B3D0C7AD195DD21D515E3659EE0E922E861E2A0D3335D354ECAE27467A2F3412
vendor/contact_solver.c             6B8899FB2135FA13022F2C99776E835E076602920CBF1577E5933D994E364C34
vendor/contact_solver.h             13C456C528A326B57C3FB74E8FD834513932DDDFFD6BD071C02DCF008B3CF4BF
vendor/core.c                       7706E710A9C138A3FBA4654DB93729CBA4F321EB4FE788C613047D3B05BBF784
vendor/core.h                       11F408D604DD27C6E7605577F56B2402FDEEFEC83D7CF81EBE73B183F5E25EEB
vendor/ctz.h                        B30E72708882D80D19B9D73A201C90681BB245A58E5B40384DF9B30B6CAD8FD3
vendor/distance.c                   6E44C7B8268EF585EF92E7C96E9F3749922F410A9B5FF709D1879C8D9F911668
vendor/distance_joint.c             15E56DB2C924964B11A65A1209BC9B248D8092470BFD51DC11CC926567124548
vendor/dynamic_tree.c               A9C9BBB6567594CB6D4FBC4F8628F86B2DD2D94370822E96B34D4F6C76D99173
vendor/geometry.c                   BE4421F07DD380E841B7970F1F63C0A0C5D4B0CCCBD310DA357629678446E42F
vendor/hull.c                       C21D1C24241589A07F7C85B33909B9ACA1C3DCBEC2C26DF831BBB0298D5A4E0F
vendor/id_pool.c                    384C1795268CEAF1C91F3D3179512406133864544A62A9E61CFAF0F7BFFF0A4D
vendor/id_pool.h                    E11D6CFB00CE3D6FB2086F3F69E8FEAC626901062C43CA7659693CFED9DB012E
vendor/island.c                     D67C19D451BFD7AD6FFCB8F0636BFB124643E050E520F777600DCF946EC46A2E
vendor/island.h                     951CE8401D427432A29D132B910EB3FD1043A5BD074B6384F7A8ECC096B1C4AF
vendor/joint.c                      4843C656B1B4CEAC3886CB75DF4536E098713B1B4AEE47F27355C44F37BA5270
vendor/joint.h                      C1679DE54FCD7BDDB2D3ADCED4D2C1E7DA9F4DA82F02ABA9DEFFBBD17868986F
vendor/LICENSE                       68A3E676D7E94093B102D5CBA0D4E04AF812040D6F230C3DB67A6664574E43D2
vendor/manifold.c                   4EBA05144D4CF7ACE6B92339B20CD55D85D8D93BAC3972292B90B31161BE1A99
vendor/math_functions.c             699916979FFC3C8570FE765DC095A313F94DA6604EABEA1810BECC1AC29CA8BE
vendor/motor_joint.c                90D3BDD6657749916E6ECB1D1E5EB5A5122CCCD8E0D4A822CC7DBC1C27B0E3BA
vendor/mouse_joint.c                4A7AFEAC9EBF471540BE0F35673027A8C37B9D03E3413ED0AB738973CA999D92
vendor/mover.c                      8FC92803559612981EA19BBC8FDA675E33EFFC94D5D0A8B7F2BD17BA06C619B2
vendor/prismatic_joint.c            0779A482035286C46903502367882FE64E256F84FA480D6BAB514C77618EFFA9
vendor/revolute_joint.c             369E2B11E8B68E0831191B198D7EC9EDE1903E42560F96FF9F7E0E55EC695C40
vendor/sensor.c                     EFFFE17470D5D2C93398540D66E1941F974CBBBF54E34AF25D876A48627DE515
vendor/sensor.h                     783E9EA7F1FB22C57DAE2D331CFA324BAFEEB99D1E486B466910646038B53A32
vendor/shape.c                      7F21CAE5AE2CFC519AD43BDCE9DE01ACDD1CCAA01CB5BF976D0ADB256CE3BB00
vendor/shape.h                      05EF245B103848460F0BBEEABA63685215D545E0B60878ADAEF64299E3D21B05
vendor/solver.c                     1E48185B231A15A2FC9A2327E8CD421B95488418FE55579D5D41056229823663
vendor/solver.h                     E49B4EFAB22E904B52D48439672EA968D88D9D0FF7F3D4D7AE1E8BE4D8A6965B
vendor/solver_set.c                 8C9BF12C3513CD1996E804BC164AC5F0723DDED4BD03B43E1EFB7C4641A4387B
vendor/solver_set.h                 60DDEFA8EC81BC1EFDE1BB47F1E475B7EEFB51D7DFBDA4B01EB731A5A7646EA1
vendor/table.c                      9D7535C536BABEB9E89AD036FF8F9124F4BF77FFC6F0D14FAC1FB7B503BE5560
vendor/table.h                      F2D7F741EBE9650731DC9F11362B0E31F0CB6CCA6BDCCFF07A8EAF834C387F7B
vendor/timer.c                      FC5398F7776756ED98B61703EBB8D321BF0D84BA585691B4109CDD8B70A27008
vendor/types.c                      BFF50BE52B9F6C685F38918A70811C0DAF55EE1CB367D76FD6127E6683FABCA8
vendor/weld_joint.c                 EB05E26002CA83349020642EA8E0CE5EB30D9B36CFBE96DF670C5B90CC6EB05D
vendor/wheel_joint.c                7E21C2CCDD451BE540D76022E865909F2FA98BBADD55DC5D25456B22AF920D36
vendor/world.c                      E14E55CBA52F50FEDF9B572AEB03658331D2E95F5375EE2B4BDE5185BAC90E3A
vendor/world.h                      EE8F553EA810FE5AEC82ADAEFD913992CA46E62A4B54143FFC0E93AC733F6427
```

## 3. Design and safe boundary (G5)

`box2d.xi` is the only module with `unsafe`/`extern "C"`; it calls a small
integer-only C bridge (`src/box2d_bridge.c`) that owns the float and
struct-by-value ABI of the Box2D v3 C API internally. Values cross the
boundary as thousandths (milli); out-params are written into XIOM-owned
8-byte `Vec[UInt8]` slots (no malloc/free -- finding B-05) and read with a
signed 32-bit helper. Public surface: `b2_version`, `b2_version_str`,
`b2_gravity`, `b2_drop`, `b2_impulse` (+ `B2Gravity`, `B2DropResult`,
`B2_DEFAULT_STEPS`). There is no SKIP path: the vendored sources are always
compiled in, so the suite runs the real simulation on every platform.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 5 checks: version pin (3.1.x), default
gravity (0, -10000 milli), resting-drop settle (1x1 box from y=10 lands at
~0.5 within [0.4, 0.6]), impulse->velocity (5000 milli impulse on the 1 kg
box yields vx in [4500, 5500]), and drop determinism (repeated run
identical).

Command (cwd = this package directory; the runner hook adds the C sources):

```
scripts/port.ps1 -Package xiom.box2d
```

Watchdog: allow >=180 s -- clang compiles 35 small C files plus the bridge
(observed well under a minute on the development machine).

## 5. Scope

Pilot: version/world/body basics with a real stepping simulation and an
impulse check. Joint APIs beyond the drop scenario, broad-phase queries,
callbacks, world snapshots, and sample scenes are Phase 2 (`ROADMAP.md`).
The pre-pilot v4-era static-extern module (`box2d.xi`, `box2d_safe.xi`,
`demo_box2d.xi`, `box2d.xiom-bind`) is preserved in git history.
