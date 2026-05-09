# SCHEDULING — Tool execution cadence and automation

## Overview

Tool scheduling is orthogonal to the tools framework. Any tool CLI can be scheduled by an external scheduler (launchd, systemd, cron, or Claude Code's `schedule` skill).

## Scheduling options by platform

### macOS (preferred)

**launchd** (native, recommended)
- Create a `.plist` file in `~/Library/LaunchAgents/` or `~/Library/LaunchDaemons/`
- Survives restarts, runs as background daemon
- No `caffeinate` wrapper needed for background execution
- See Apple's LaunchAgents documentation for syntax

**Claude Code `schedule` skill** (agent-level)
- Create scheduled remote agents (triggers) on cron schedule
- Runs Claude as orchestrator; can handle complex logic
- See Claude Code documentation for `schedule` skill

**cron** (not recommended on macOS)
- Legacy Unix approach; awkward on macOS
- Requires `caffeinate` wrapper to prevent sleep during execution
- High friction; prefer launchd or `schedule` skill

### Linux

**systemd timers** (native, recommended)
- Create `.service` and `.timer` files in `/etc/systemd/system/` or `~/.config/systemd/user/`
- Persistent, well-integrated with system boot

**cron** (acceptable)
- Standard Unix scheduler; no special wrappers needed
- Simple for periodic tasks; less powerful than systemd

## Registry metadata

The `schedule` field in `registry.json` is informational only:
```json
{
  "name": "my-tool",
  "actions": [
    {
      "name": "my_action",
      "schedule": null
    }
  ]
}
```

- `null` or omitted: No automatic execution; on-demand only
- `"0 9 * * *"` (cron format): Intended cadence (documentation only)

**No scheduler reads this field automatically.** It is metadata for developers and operators to understand intended usage.

## Example: Scheduling a tool with launchd

1. Create `~/Library/LaunchAgents/com.lilo.my-tool.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.lilo.my-tool</string>
       <key>ProgramArguments</key>
       <array>
           <string>/path/to/python</string>
           <string>-m</string>
           <string>adapters.cli</string>
           <string>action-name</string>
       </array>
       <key>StartCalendarInterval</key>
       <dict>
           <key>Hour</key>
           <integer>9</integer>
           <key>Minute</key>
           <integer>0</integer>
       </dict>
   </dict>
   </plist>
   ```

2. Load the agent:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.lilo.my-tool.plist
   ```

## Example: Scheduling with Claude Code `schedule` skill

```
/schedule create --cron "0 9 * * *" --prompt "Run my-tool action"
```

This delegates scheduling to Claude Code's remote trigger infrastructure.

## No cron.sh files

Do not create `cron.sh`, `cron.sh.template`, or other shell wrapper scripts in tool repos. All scheduling is external to the tool framework.
