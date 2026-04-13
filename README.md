Overlay file system with detection system integrated.

Installation guide:
1. install requirements.txt from MA/custom/filesystems/python_classifier/
2. run: python3 detection_system.py
3. navigate to rename_fs directory inside MA_custom_filesystems
4. within the folder MA_custom_filesystems, add files into filesystem_dir that should be included within the overlay file system.
5. within MA/custom_filesystems/rename_fs/main.go, change the mountPoint directory to the directory where the overlay fileststem should be run
6. compile the code within rename_fs dir by running "go build" within the directory
7. run the generated binary rename_fs, by running the command: ./rename_fs

If running a Ransomware in the mounted directory is desired, following needs to be configured:
  - for DarkRadiation, adjust the path on line 165 and 171 to the overlay file system path
  - for Roar, change global variables LINUX_STARTDIRS and USER in rwpoc.py to correspond to the path to overlay filesystem
  - Ransomware PoC, has to be run with an argument -e "{path to overlay file system}"

---

## Running inside a Docker container with host-side kill on detection

When the filesystem runs inside a Docker container, `watch_detection.sh` can be
used to automatically kill the container as soon as malware is detected.
Communication between container and host uses a single named pipe (FIFO) mounted
into the container. No network port is opened.

### How it works

```
┌─────────────────────────────────┐          ┌──────────────────────────┐
│  Docker container               │          │  Host                    │
│                                 │          │                          │
│  rename_fs (FUSE)               │          │  watch_detection.sh      │
│    detects malware              │          │    blocks on read        │
│    writes "1\n" to FIFO  ───────┼──────────┼──► wakes up             │
│                                 │  (FIFO)  │    docker kill <name>   │
└─────────────────────────────────┘          └──────────────────────────┘
         write-only                                    read-only
```

The FIFO lives in `MA_custom_filesystems/signal/kill_signal` on the host and is
bind-mounted into the container at `/signal/kill_signal`. The container can only
write to it; the host script only reads from it.

### Setup

**1. Start the watcher on the host before launching the container.**

```bash
./MA_custom_filesystems/watch_detection.sh <container-name-or-id>
```

The script creates the `signal/` directory and the FIFO automatically on first
run. It then blocks (zero CPU) until the filesystem sends a detection signal.

**2. Launch the container with the signal directory bind-mounted.**

```bash
docker run \
  --mount type=bind,source="$(pwd)/MA_custom_filesystems/signal",target=/signal \
  ... \
  <image>
```

The `signal/` directory must be bind-mounted separately from the filesystem
directory that the malware operates on so the malware cannot interact with the
pipe directly.

**3. When malware is detected**, the filesystem writes to the pipe, the watcher
wakes up, prints a log line, and calls `docker kill <container-name>`.

### Security properties

| Property | Detail |
|---|---|
| No network | Communication is entirely through a host-local FIFO |
| Write-only from container | FIFO permissions are set to `220`; the container cannot read host data through the pipe |
| Single signal | The Go code uses `sync.Once` — the pipe is written to exactly once regardless of how many filesystem operations trigger detection |
| Non-blocking write | `O_NONBLOCK` is used when opening the pipe, so the filesystem never stalls if the watcher is not running |