# XIOM Package Ecosystem

> Compiled from `docs/STDLIB_EXTENSION.md` (v0.56.0, 2026-08-07; audit refreshed 2026-08-11)
> and verified against the live `packages/` directory on 2026-08-11.
> Status legend: **IMPLEMENTED** = real `.xi` source exists on disk /
> **STUB** = folder + placeholder README only (no implementation) /
> **PLANNED** = doc mention only (no folder yet).

## 1. What is a "package"?

The XIOM standard library is split into two layers:

| Layer | Location | External dependencies | Rule |
|-------|----------|----------------------|------|
| **Stdlib** | `stdlib/xiom/` | **ZERO** | Only pure XIOM + OS syscalls via minimal FFI + the compiler substrate (LLVM/clang, NASM). |
| **Package** | `packages/` | **YES** | Built **ON the stdlib**; may wrap third-party C libraries via FFI. |

- A **package** is anything that needs an external library, a C binding, a
  protocol peer, or a domain-specific runtime. It is not stdlib material.
- Packages share the `xiom.*` namespace with the stdlib (e.g. `xiom.json`,
  `xiom.http.client`); name collisions are guarded by the reserved-name list
  (`STDLIB_EXTENSION.md` sec.3).
- **External projects** (frameworks/engines/apps such as `xiom-pulse`,
  `xiom-game-engine`, `xiom-db`) live at the **repo top level** and are NOT
  packages. They consume packages like any user.
- Policy in the docs (sec.0, sec.5, sec.6, sec.7): pure/formatting/text logic -> stdlib;
  anything needing OpenSSL/ICU/libcurl/zlib-C/OS-heavy bindings or a protocol
  peer -> package.

## 2. On-disk reality vs docs

| Source | Count |
|--------|-------|
| Doc sec.8.1 "Existing (66)" | 66 dirs (15 pure-XIOM + 51 FFI-bound) |
| Doc sec.8.2 "Planned placeholders" | 260 planned folders |
| Doc sec.9 README-assignment packages | +31 more names |
| **Live `packages/` directory (2026-08-11)** | **365 dirs** |
| **Doc-only (no folder)** | 1 (`xiom-jdbc`) |
| **Total unique package names** | **366** |

Every on-disk folder has a README.md (365/365). 70 have real `.xi` source
(IMPLEMENTED). 295 are placeholder-only (STUB). 56 have a SPEC.md.

## 3. Status legend

| Status | Meaning |
|--------|---------|
| **IMPLEMENTED** | Folder has actual source files (e.g. `src/*.xi`), not just `package.xi`. |
| **STUB** | Folder + README.md exists ("PLACEHOLDER - reserved, spec pending"); no implementation. |
| **PLANNED** | Mentioned in docs only; no folder on disk yet. |

## 4. Categorized catalog

Columns: **Package | Purpose | Key dependencies | Status**
(Status shorthand: I = IMPLEMENTED, S = STUB, P = PLANNED.)

### 4.1 Crypto / Security (20)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-openssl | OpenSSL - TLS/cryptography | OpenSSL/libssl/libcrypto | I |
| xiom-libsodium | libsodium secure crypto bindings | libsodium | I |
| xiom-pki | Cert/PKI tooling (x509, pkcs*, cms, smime) | OpenSSL | S |
| xiom-tls | TLS client/server | OpenSSL / stdlib crypto | S |
| xiom-pgp | PGP/GPG encryption | GnuPG / OpenSSL | S |
| xiom-jwt | JWT generation and validation | stdlib crypto | S |
| xiom-oauth | OAuth 1.0/2.0 protocol | stdlib http | S |
| xiom-zkp | Zero-knowledge proofs | libsodium / liboqs | S |
| xiom-auth | Authentication protocols | varies | S |
| xiom-rbac | Role-based access control | stdlib | S |
| xiom-password | Password hashing (bcrypt/argon2) | libsodium / argon2 | S |
| xiom-sanitize | Input sanitization | stdlib | S |
| xiom-escape | Escaping (HTML/XML/URL/shell) | stdlib | S |
| xiom-audit | Security audit trail | stdlib | S |
| xiom-keymgmt | Key management | OpenSSL | S |
| xiom-secret | Secret handling | varies | S |
| xiom-vault | HashiCorp Vault client | libcurl / stdlib http | S |
| xiom-saml | SAML protocol | OpenSSL | S |
| xiom-ldap | LDAP client | OpenLDAP | S |
| xiom-chaincrypto | Blockchain crypto (chains/signatures) | libsodium / secp256k1 | S |

### 4.2 Testing / QA (13)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-test | Unit test framework (asserts, discovery) | pure XIOM | I |
| xiom-itest | Integration testing | stdlib | S |
| xiom-fuzz | Fuzz testing | libFuzzer / AFL | S |
| xiom-mock | Mocking framework | stdlib | S |
| xiom-stub | Stubbing framework | stdlib | S |
| xiom-coverage | Coverage measurement | llvm-cov | S |
| xiom-property | Property-based testing | stdlib | S |
| xiom-golden | Golden file testing | stdlib | S |
| xiom-snapshot | Snapshot testing | stdlib | S |
| xiom-perf | Performance testing | stdlib bench | S |
| xiom-sectest | Security testing | varies | S |
| xiom-compliance | Compliance checks | varies | S |
| xiom-report | Test/report generation | stdlib | S |

### 4.3 Protocols & Clients (43)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-http | HTTP types/parse/client/server | pure XIOM | I |
| xiom-net | TCP/UDP primitives, DNS | pure XIOM | I |
| xiom-websocket | WebSocket transport | xiom-http/net | I |
| xiom-graphql | Schema-first GraphQL server | xiom-http | I |
| xiom-rest | REST routing/OpenAPI helpers | xiom-http | I |
| xiom-grpc | gRPC C Core bindings | grpc (C) | I |
| xiom-zeromq | ZeroMQ messaging | libzmq | I |
| xiom-kafka | Apache Kafka client | librdkafka | I |
| xiom-micro | Microservices resilience (retry/circuit breaker) | xiom-http | I |
| xiom-realtime | Channels/rooms/presence/broadcast | xiom-websocket | I |
| xiom-libuv | libuv async I/O | libuv | I |
| xiom-ftp | FTP client | pure/OpenSSL | S |
| xiom-smtp | SMTP client | stdlib | S |
| xiom-pop3 | POP3 client | stdlib | S |
| xiom-imap | IMAP client | stdlib | S |
| xiom-dhcp | DHCP client | stdlib net | S |
| xiom-telnet | Telnet protocol | stdlib net | S |
| xiom-irc | IRC client | stdlib net | S |
| xiom-mqtt | MQTT client | mosquitto / pure | S |
| xiom-amqp | AMQP (RabbitMQ) | rabbitmq-c | S |
| xiom-rpc | RPC (SunRPC/ONC, JSON-RPC) | stdlib | S |
| xiom-proxy | HTTP/SOCKS proxy | stdlib | S |
| xiom-ntp | NTP client | stdlib net | S |
| xiom-snmp | SNMP | net-snmp | S |
| xiom-tftp | TFTP | stdlib net | S |
| xiom-upnp | UPnP discovery | stdlib net | S |
| xiom-bonjour | Bonjour/mDNS (zeroconf) | stdlib net | S |
| xiom-multicast | Multicast networking | stdlib net | S |
| xiom-nats | NATS messaging | nats.c | S |
| xiom-pulsar | Apache Pulsar client | pulsar-c | S |
| xiom-memcached | Memcached protocol | stdlib net | S |
| xiom-socks | SOCKS5 proxy | stdlib | S |
| xiom-tor | Tor (SOCKS/onion) | stdlib | S |
| xiom-i2p | I2P anonymous network | stdlib | S |
| xiom-ssh2 | SSH/SFTP/SCP client | libssh2 | S |
| xiom-curl | HTTP client via libcurl | libcurl | S |
| xiom-messaging | XMPP/Matrix/SIP/IRC/NNTP umbrella | varies | S |
| xiom-discovery | mDNS/UPnP/SSDP/WS-Discovery | stdlib | S |
| xiom-streaming | WebRTC/RTP/RTSP/RTMP/HLS/DASH | gstreamer/webrtc | S |
| xiom-legacy-proto | DHCP/BootP/NFS/SMB/NetBIOS/legacy | varies | S |
| xiom-aviation | GNSS/ADS-B/ACARS/VDL/aviation | varies | S |
| xiom-packet | libpcap/netlink/nf* capture | libpcap | S |
| xiom-wireless | iw/WPA/hostapd/driver bindings | nl80211 | S |

### 4.4 Databases (22)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-sqlite | SQLite database bindings | sqlite3 | I |
| xiom-postgres | PostgreSQL bindings | libpq | I |
| xiom-libpq | libpq - PostgreSQL C client | libpq | I |
| xiom-redis | Redis client | hiredis | I |
| xiom-sql | SQL library / embedded SQL | varies | I |
| xiom-mysql | MySQL client | libmysqlclient | S |
| xiom-mongo | MongoDB wire protocol | stdlib / mongo-c | S |
| xiom-cassandra | Cassandra driver | cassandra-cpp | S |
| xiom-elastic | Elasticsearch client | stdlib http | S |
| xiom-oracle | Oracle DB client | OCI | S |
| xiom-mssql | SQL Server client | msodbc / TDS | S |
| xiom-db2 | IBM DB2 client | db2 | S |
| xiom-firebird | Firebird client | fbclient | S |
| xiom-leveldb | LevelDB key-value store | leveldb | S |
| xiom-rocksdb | RocksDB key-value store | rocksdb | S |
| xiom-badger | Badger embedded KV (Go) | badger | S |
| xiom-bolt | BoltDB embedded KV | bolt | S |
| xiom-etcd | etcd distributed KV client | etcd | S |
| xiom-consul | HashiCorp Consul client | stdlib http | S |
| xiom-zookeeper | ZooKeeper client | zookeeper-c | S |
| xiom-dynamo | DynamoDB client | stdlib http | S |
| xiom-odbc | ODBC connectivity | unixODBC | S |

### 4.5 File Formats (23)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-json | Pure-XIOM JSON parser/serializer | pure XIOM | I |
| xiom-protobuf | Protocol Buffers serialization | protobuf-c | I |
| xiom-arrow | Apache Arrow columnar format | arrow-c | I |
| xiom-xml | XML parsing | libxml2 / expat | S |
| xiom-yaml | YAML parsing | libyaml | S |
| xiom-toml | TOML parsing | stdlib | S |
| xiom-csv | CSV parsing/writing | stdlib | S |
| xiom-tsv | TSV parsing/writing | stdlib | S |
| xiom-msgpack | MessagePack | msgpack-c | S |
| xiom-thrift | Apache Thrift | thrift-c | S |
| xiom-bson | BSON encoding | bson-c | S |
| xiom-avro | Apache Avro | avro-c | S |
| xiom-parquet | Apache Parquet | parquet-cpp | S |
| xiom-orc | Apache ORC | orc | S |
| xiom-xlsx | XLSX spreadsheets | stdlib (zip+xml) | S |
| xiom-pdf | PDF generation | haru / pure | S |
| xiom-docx | DOCX documents | stdlib | S |
| xiom-pptx | PPTX presentations | stdlib | S |
| xiom-markdown | Markdown parsing/rendering | stdlib | S |
| xiom-html | HTML parsing/rendering | stdlib | S |
| xiom-xml2 | libxml2 bindings | libxml2 | S |
| xiom-expat | Expat XML parser bindings | expat | S |
| xiom-text-markup | Markdown/HTML/Textile/RTF/LaTeX/troff | varies | S |

### 4.6 Graphics / Media (38)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-vulkan | Vulkan GPU bindings | Vulkan SDK | I |
| xiom-opengl | OpenGL 4.6 bindings | OpenGL | I |
| xiom-directx11 | Direct3D 11 bindings | DirectX SDK | I |
| xiom-directx12 | Direct3D 12 bindings | DirectX SDK | I |
| xiom-vma | Vulkan Memory Allocator | VMA | I |
| xiom-dxc | DirectX Shader Compiler | DXC | I |
| xiom-ffmpeg | FFmpeg audio/video codecs | libavcodec/libavformat | I |
| xiom-miniaudio | MiniAudio playback/capture | miniaudio | I |
| xiom-openal | OpenAL 3D audio | OpenAL | I |
| xiom-portaudio | PortAudio audio I/O | portaudio | I |
| xiom-phonon | Steam Audio (Phonon) spatial audio | phonon | I |
| xiom-imgui | Dear ImGui immediate-mode GUI | imgui | I |
| xiom-ui | XIOM immediate-mode GUI library | pure XIOM | I |
| xiom-stb | stb_image loading | stb | I |
| xiom-meshopt | meshoptimizer bindings | meshoptimizer | I |
| xiom-image | Image loading/saving umbrella | stdlib/stb | S |
| xiom-png | PNG codec | libpng / pure | S |
| xiom-jpeg | JPEG codec | libjpeg | S |
| xiom-gif | GIF codec | giflib | S |
| xiom-bmp | BMP codec | stdlib | S |
| xiom-webp | WebP codec | libwebp | S |
| xiom-svg | SVG rendering | cairo / resvg | S |
| xiom-mp3 | MP3 decode | libmpg123 / pure | S |
| xiom-wav | WAV codec | stdlib | S |
| xiom-ogg | Ogg container | libogg | S |
| xiom-flac | FLAC codec | libFLAC | S |
| xiom-aac | AAC codec | libavcodec / fdk-aac | S |
| xiom-video | Video processing | ffmpeg | S |
| xiom-mp4 | MP4/MOV container | mp4v2 | S |
| xiom-avi | AVI container | stdlib | S |
| xiom-mkv | Matroska (MKV) container | libmatroska | S |
| xiom-codec | Codec umbrella | varies | S |
| xiom-subtitle | Subtitle formats (srt/vtt/ass) | stdlib | S |
| xiom-charts | Chart rendering (bar/line/pie/... ) | cairo / pure | S |
| xiom-diagrams | UML/Mermaid/PlantUML/Graphviz DSLs | pure | S |
| xiom-audio-meta | Audio/chiptune metadata (midi/mod/xm/nsf) | varies | S |
| xiom-typography | Fonts/glyphs/kerning/shaping | harfbuzz/freetype | S |
| xiom-metadata | Media metadata tags (exif/id3/vorbis) | libexif / pure | S |

### 4.7 ML / Cloud SDKs (47)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-tensorflow | TensorFlow C API | libtensorflow | I |
| xiom-torch | LibTorch (PyTorch C++) inference | libtorch | I |
| xiom-libtorch | LibTorch full ML/DL framework | libtorch | I |
| xiom-onnx | ONNX Runtime inference | onnxruntime | I |
| xiom-numpy | NumPy C API | numpy | I |
| xiom-pandas | Pandas (Arrow-backed DataFrame) | pandas/arrow | I |
| xiom-scipy | SciPy scientific computing | scipy | I |
| xiom-blas | BLAS/LAPACK linear algebra | BLAS/LAPACK | I |
| xiom-openblas | OpenBLAS bindings | OpenBLAS | I |
| xiom-cuda | NVIDIA CUDA (cuBLAS/cuDNN/cuFFT) | CUDA Toolkit | I |
| xiom-eigen | Eigen C++ linear algebra | Eigen | I |
| xiom-opencv | OpenCV computer vision | OpenCV | I |
| xiom-ml | ML models (regression/Bayesian/MCMC) | stdlib stats | S |
| xiom-tensor | Tensor type | stdlib | S |
| xiom-neural | Neural network layers | stdlib | S |
| xiom-deep | Deep learning | stdlib | S |
| xiom-training | Training loops | stdlib | S |
| xiom-inference | Inference runtime | stdlib | S |
| xiom-optimizer | Optimizers (SGD/Adam/...) | stdlib | S |
| xiom-layers | NN layer library | stdlib | S |
| xiom-activation | Activation functions | stdlib | S |
| xiom-loss | Loss functions | stdlib | S |
| xiom-metrics | ML metrics (accuracy/precision/f1/auc) | stdlib | S |
| xiom-data | Dataset/data loading | stdlib | S |
| xiom-preprocess | Data preprocessing | stdlib | S |
| xiom-feature | Feature engineering | stdlib | S |
| xiom-selection | Feature selection | stdlib | S |
| xiom-ensemble | Ensemble methods | stdlib | S |
| xiom-boosting | Boosting (XGBoost-style) | stdlib | S |
| xiom-randomforest | Random forest | stdlib | S |
| xiom-svm | Support vector machines | libsvm | S |
| xiom-clustering | Clustering (k-means/DBSCAN) | stdlib | S |
| xiom-dimred | Dimensionality reduction | stdlib | S |
| xiom-aws | AWS SDK (S3/EC2/Lambda/...) | stdlib http + auth | S |
| xiom-azure | Azure SDK | stdlib http | S |
| xiom-gcp | Google Cloud SDK | stdlib http | S |
| xiom-docker | Docker API | stdlib http | S |
| xiom-k8s | Kubernetes API | stdlib http | S |
| xiom-terraform | Terraform provider framework | stdlib | S |
| xiom-ansible | Ansible modules | stdlib | S |
| xiom-puppet | Puppet integration | stdlib | S |
| xiom-chef | Chef integration | stdlib | S |
| xiom-salt | SaltStack integration | stdlib | S |
| xiom-helm | Helm chart tooling | stdlib | S |
| xiom-serverless | Serverless deploy tooling | stdlib | S |
| xiom-cfn | AWS CloudFormation | stdlib | S |
| xiom-cloud | Cloud SDK umbrella (vendor APIs) | varies | S |

### 4.8 Geospatial (8)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-geo | GeoJSON/KML/GPX/geohash/UTM/projections | stdlib / proj | S |
| xiom-geography | Geographic utilities | stdlib | S |
| xiom-geology | Geology data | stdlib | S |
| xiom-geom3d | 3D geometry (mesh/subdivision/NURBS) | stdlib | S |
| xiom-weather | Weather data/metrology | stdlib | S |
| xiom-climate | Climate data | stdlib | S |
| xiom-meteorology | Meteorology | stdlib | S |
| xiom-astronomy | Astronomy calculations | stdlib | S |

### 4.9 Game Engine / Physics / Robotics (16)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-box2d | Box2D 2D physics | box2d | I |
| xiom-bullet | Bullet physics | bullet3 | I |
| xiom-jolt | Jolt Physics (joltc C bridge) | joltc | I |
| xiom-raylib | Raylib game framework | raylib | I |
| xiom-glfw | GLFW windowing/input | glfw | I |
| xiom-sdl3 | SDL3 bindings | SDL3 | I |
| xiom-ozz | Ozz-Animation skeletal animation | ozz | I |
| xiom-assimp | 3D model import (OBJ/FBX/glTF) | assimp | I |
| xiom-ros2 | ROS 2 middleware | rcl | I |
| xiom-gazebo | Gazebo robot simulation | gz-sim | I |
| xiom-moveit | MoveIt motion planning | moveit | I |
| xiom-sensor | Sensor fusion (IMU/GPS) | stdlib | I |
| xiom-control | Control systems (PID/state machines) | stdlib | I |
| xiom-physics | Physics umbrella | stdlib | S |
| xiom-particle | Particle systems | stdlib | S |
| xiom-robotics | Robotics umbrella | varies | S |

> Note: the top-level external project **xiom-game-engine** (doc sec.9, line ~304)
> is NOT a package; it consumes the binding packages above (raylib, sdl3, jolt,
> bullet, imgui, miniaudio, ...). Same for **xiom-pulse** (consumes
> xiom-http/json/websocket/graphql/rest).

### 4.10 Compression (2)

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-zstd | zstd fast lossless compression | libzstd | I |
| xiom-lzfse | Apple LZFSE compression | lzfse | I |

### 4.11 Miscellaneous (133)

**Foundational / pure-XIOM**

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-algo | Algorithm library (sort/search/math utils) | pure XIOM | I |
| xiom-core | Durable-systems core (config/errors/WAL/txn) | pure XIOM | I |
| xiom-ffi | Foundational FFI module for C bindings | pure XIOM | I |
| xiom-log | Structured logging | pure XIOM | I |
| xiom-math | Vec/Mat/Quat math (column-major Vulkan) | pure XIOM | I |
| xiom-logging | Syslog/journald/eventlog/log agents | varies | S |

**C bindings umbrella**

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-c-binding | libcurl/libgit2/libxml2/... umbrella | varies | S |
| xiom-jansson | Jansson JSON C library | jansson | S |
| xiom-git2 | libgit2 bindings | libgit2 | S |

**Platform frameworks**

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-apple | Apple frameworks (Metal/ARKit/Vision/...) | macOS/iOS SDKs | S |
| xiom-windows | Windows registry/authenticode/pki tools | Win32 API | S |
| xiom-wasmtime | Wasmtime WebAssembly runtime | wasmtime | I |

**Stats / Finance**

| Package | Purpose | Key dependencies | Status |
|---------|---------|------------------|--------|
| xiom-finance | Financial formatting/models | stdlib | S |
| xiom-stats-ml | Statistical metrics/plots | stdlib stats | S |
| xiom-stats-tests | Statistical tests (~150) | stdlib stats | S |
| xiom-timeseries | AR/VAR/VECM/cointegration | stdlib | S |

**i18n / Locale (15)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-locale | Locale management | S |
| xiom-translate | Translation | S |
| xiom-plural | Pluralization | S |
| xiom-l10n-date | Localized dates | S |
| xiom-l10n-time | Localized time | S |
| xiom-l10n-number | Localized numbers | S |
| xiom-l10n-currency | Localized currency | S |
| xiom-l10n-name | Name formatting | S |
| xiom-l10n-address | Address formatting | S |
| xiom-l10n-phone | Phone number formatting | S |
| xiom-l10n-unit | Unit formatting | S |
| xiom-collation | Collation | S |
| xiom-l10n-unicode | Unicode data | S |
| xiom-transliteration | Transliteration | S |
| xiom-icu | ICU bindings (full Unicode) | ICU | S |

**Concurrency (10)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-forkjoin | Fork/join parallelism | S |
| xiom-actor | Actor model | S |
| xiom-stm | Software transactional memory | S |
| xiom-lockfree | Lock-free data structures | S |
| xiom-barrier | Barriers | S |
| xiom-countdown | CountDownLatch | S |
| xiom-exchanger | Exchangers | S |
| xiom-phaser | Phaser synchronization | S |
| xiom-executor | Executors | S |
| xiom-scheduler | Task schedulers | S |

**Utilities (16)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-config | Configuration loading | S |
| xiom-flags | Command-line flags | S |
| xiom-option | Options parsing | S |
| xiom-retry | Retry policies | S |
| xiom-cache | Caching | S |
| xiom-pool | Resource pooling | S |
| xiom-worker | Worker pools | S |
| xiom-lru | LRU cache | S |
| xiom-ttl | TTL caches | S |
| xiom-semaphore | Semaphores | S |
| xiom-backoff | Backoff strategies | S |
| xiom-timeout | Timeouts | S |
| xiom-context | Context propagation | S |
| xiom-cancel | Cancellation | S |
| xiom-profiling | Profiling | S |
| xiom-tracing | Distributed tracing | S |

**Compiler tools (15)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-parser-fw | Parser framework | S |
| xiom-lexer-fw | Lexer framework | S |
| xiom-ast | AST tooling | S |
| xiom-codegen-fw | Codegen framework | S |
| xiom-optimizer-fw | Optimizer framework | S |
| xiom-linter | Linter | S |
| xiom-formatter-fw | Formatter framework | S |
| xiom-analyzer | Static analyzer | S |
| xiom-refactor | Refactoring | S |
| xiom-plugin | Plugin system | S |
| xiom-macro | Macros | S |
| xiom-inline-asm | Inline assembly | S |
| xiom-jit-fw | JIT framework | S |
| xiom-wasm | WebAssembly tooling | S |
| xiom-llvm | LLVM bindings | LLVM | S |

**Embedded / IoT (15)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-gpio | GPIO | S |
| xiom-i2c | I2C bus | S |
| xiom-spi | SPI bus | S |
| xiom-uart | UART serial | S |
| xiom-adc | ADC | S |
| xiom-dac | DAC | S |
| xiom-pwm | PWM | S |
| xiom-interrupt | Interrupts | S |
| xiom-timer | Timers | S |
| xiom-rtc | Real-time clock | S |
| xiom-eeprom | EEPROM | S |
| xiom-flash | Flash memory | S |
| xiom-sd | SD card | S |
| xiom-ble | Bluetooth LE | S |
| xiom-zigbee | Zigbee | S |

**Blockchain / Web3 (13)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-chaincore | Blockchain core | S |
| xiom-ethereum | Ethereum client | S |
| xiom-bitcoin | Bitcoin client | S |
| xiom-smartcontract | Smart contracts | S |
| xiom-wallet | Wallets | S |
| xiom-transaction | Transactions | S |
| xiom-consensus | Consensus algorithms | S |
| xiom-merkle | Merkle trees | S |
| xiom-hashchain | Hash chains | S |
| xiom-nft | NFTs | S |
| xiom-defi | DeFi | S |
| xiom-web3 | Web3 | S |
| xiom-bridge | Cross-chain bridges | S |

> Doc sec.8.2 also lists `xiom-oracle` in the Blockchain group (an oracle service);
> the on-disk single `xiom-oracle` folder is classified under Databases (Oracle DB).

**Science / Engineering (15)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-chemistry | Chemistry | S |
| xiom-biology | Biology | S |
| xiom-materials | Materials science | S |
| xiom-mechanics | Mechanics | S |
| xiom-thermo | Thermodynamics | S |
| xiom-quantum | Quantum | S |
| xiom-nuclear | Nuclear physics | S |
| xiom-relativity | Relativity | S |
| xiom-electronics | Electronics | S |
| xiom-signal | Signal processing | S |
| xiom-imaging | Raster imaging (tiff/jpeg2000/geotiff) | S |
| xiom-spectroscopy | Spectroscopy | S |
| xiom-chromatography | Chromatography | S |
| xiom-microscopy | Microscopy | S |
| xiom-environment | Environment data | S |

**Text / NLP (14)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-parsing | Parsing | S |
| xiom-lexing | Lexing | S |
| xiom-template | Template strings | S |
| xiom-diff | Diff (Myers) | S |
| xiom-patch | Patch | S |
| xiom-stemming | Stemming | S |
| xiom-lemmatization | Lemmatization | S |
| xiom-nlp | NLP | S |
| xiom-tokenizer | Tokenizer | S |
| xiom-ngram | N-grams | S |
| xiom-sentiment | Sentiment analysis | S |
| xiom-summary | Summarization | S |
| xiom-translation | Translation | S |
| xiom-spell | Spelling | S |

**Observability (4)**

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-monitoring | Monitoring | S |
| xiom-cloudlog | Cloud log aggregation | S |
| xiom-alerting | Alerting | S |
| xiom-autoscale | Autoscaling | S |

### 4.12 Doc-only, no folder yet

| Package | Purpose | Status |
|---------|---------|--------|
| xiom-jdbc | JDBC bridge (`net/jdbc` in wish-list sec.5) | P |

## 5. Pure-XIOM packages (15)

The docs (sec.2.2, sec.8.1) mark these 15 as **pure-XIOM** - no C dependencies. They
build only on the stdlib. By owner decision they could be either stdlib or
package; they are currently packaged. All 15 exist on disk with real source.

| # | Package | Purpose |
|---|---------|---------|
| 1 | xiom-json | Pure JSON parser/serializer |
| 2 | xiom-http | HTTP types/parse/client/server |
| 3 | xiom-net | TCP/UDP/DNS primitives |
| 4 | xiom-rest | REST routing/OpenAPI helpers (on xiom-http) |
| 5 | xiom-graphql | GraphQL server (on xiom-http) |
| 6 | xiom-websocket | WebSocket transport (on xiom-http/net) |
| 7 | xiom-micro | Microservices resilience (on xiom-http) |
| 8 | xiom-realtime | Realtime channels/rooms (on xiom-websocket) |
| 9 | xiom-algo | Algorithm library |
| 10 | xiom-math | Vec/Mat/Quat math |
| 11 | xiom-core | Durable-systems core (WAL/txn substrate) |
| 12 | xiom-ffi | Foundational FFI module |
| 13 | xiom-log | Structured logging |
| 14 | xiom-test | Unit test framework |
| 15 | xiom-arrow | Apache Arrow columnar format |

> Caveat: doc sec.8.1 lists xiom-arrow as pure-XIOM, but the registry description
> mentions a Pandas/Arrow backend, so an optional FFI path may apply.

## 6. Category summary

| Category | Total | IMPLEMENTED | STUB | PLANNED |
|----------|------:|------------:|-----:|--------:|
| Crypto / Security | 20 | 2 | 18 | 0 |
| Testing / QA | 13 | 1 | 12 | 0 |
| Protocols & Clients | 43 | 11 | 32 | 0 |
| Databases | 22 | 5 | 17 | 0 |
| File Formats | 23 | 3 | 20 | 0 |
| Graphics / Media | 38 | 15 | 23 | 0 |
| ML / Cloud SDKs | 47 | 12 | 35 | 0 |
| Geospatial | 8 | 0 | 8 | 0 |
| Game Engine / Physics / Robotics | 16 | 13 | 3 | 0 |
| Compression | 2 | 2 | 0 | 0 |
| Miscellaneous | 133 | 6 | 127 | 0 |
| Doc-only (no folder) | 1 | 0 | 0 | 1 |
| **TOTAL (unique names)** | **366** | **70** | **295** | **1** |

> On-disk: 365 dirs (70 IMPLEMENTED + 295 STUB). The single PLANNED name is
> xiom-jdbc (doc-only, no folder yet); it is not part of the 365 on-disk count.

## 7. Implementation status by doc phase

- Phase 0-4 (stdlib) all COMPLETE as of 2026-08-11 (64+ modules, ~2,215 pub fns).
- Packages remain "half-done, revisit later" (sec.8.1, sec.11): the 70 implemented
  packages are registry-listed (v0.1.0, `packages/index.json`, 70 entries) and
  the remaining 295 folders are placeholder READMEs awaiting SPECs (sec.8.2, sec.9).
- The audit (sec.13, 2026-08-11) re-affirms: wire protocols that need external
  peers/C libs = PACKAGE; everything pure stays stdlib.

## 8. Sources

- `docs/STDLIB_EXTENSION.md` sec.2.2, sec.3, sec.5, sec.6, sec.7, sec.8.1, sec.8.2, sec.9, sec.11, sec.13
- `packages/` directory scan (365 dirs, 2026-08-11)
- `packages/index.json` (70 registry entries, v0.1.0)
