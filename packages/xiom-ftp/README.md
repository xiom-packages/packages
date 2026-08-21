# xiom-ftp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** FTP/SFTP client and server for file transfer.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `ftp-client` | FTP client with connect, list, get, and put operations. |
| `ftp-server` | FTP server with virtual filesystem and access control. |
| `sftp` | SFTP client using the SSH2 secure transport. |
| `data-channel` | Active/passive data connection handling. |
| `auth` | Anonymous and credential-based login handling. |
