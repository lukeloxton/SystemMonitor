# System Monitor

Menu bar app for macOS that shows CPU, memory, and disk usage.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- CPU, memory, and disk usage at a glance
- Circular gauges with colour-coded thresholds (green / yellow / red)
- Lives in the menu bar -- no dock icon
- Updates every 3 seconds
- Zero dependencies, pure SwiftUI

## Install

### Download

Grab the latest `.app.zip` from [Releases](../../releases), unzip, and drag to `/Applications`.

### Build from source

```bash
git clone https://github.com/lukeloxton/SystemMonitor.git
cd SystemMonitor
bash build.sh
```

This builds a release binary, assembles `System Monitor.app`, copies it to `/Applications`, and launches it.

## License

MIT
