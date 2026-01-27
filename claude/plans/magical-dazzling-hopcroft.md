# Plan: Modify `tron dev` Command Behavior

## Goal

Change `tron dev` from a blocking build-test-start-tail workflow to a quick server start with optional flags.

## Current Behavior

```bash
tron dev
# 1. Build workspace (bun run build)
# 2. Run tests (bun run test)
# 3. Check/rebuild native modules
# 4. Start server in foreground (blocks, tails logs)
```

## New Behavior

```bash
tron dev           # Just start server in background, no build/test
tron dev -t        # Start server in foreground (tail logs)
tron dev -b        # Build + test, then start server in background
tron dev -bt       # Build + test, then start server + tail logs
tron build         # Build + test only (no server)
```

## Changes to `scripts/tron`

### 1. Add `tron build` command (~15 lines)

New command that runs build and tests:

```bash
cmd_build() {
    require_project_dir
    cd "$PROJECT_DIR"

    print_header "Building and Testing"

    build_workspace

    if ! run_tests; then
        print_warning "Tests failed!"
        exit 1
    fi

    print_success "Build and tests complete"
}
```

Add to dispatch:
```bash
build)     cmd_build ;;
```

### 2. Modify `cmd_dev()` function (lines 737-791)

Replace current implementation with flag parsing:

```bash
cmd_dev() {
    require_project_dir
    cd "$PROJECT_DIR"

    # Parse flags
    local do_build=false
    local do_tail=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--build) do_build=true; shift ;;
            -t|--tail)  do_tail=true; shift ;;
            -bt|-tb)    do_build=true; do_tail=true; shift ;;
            -h|--help)
                echo "Usage: tron dev [options]"
                echo ""
                echo "Options:"
                echo "  -b, --build   Build and test before starting"
                echo "  -t, --tail    Run in foreground (tail logs)"
                echo ""
                return 0
                ;;
            *) shift ;;
        esac
    done

    # Check if beta port is already in use
    if is_beta_running; then
        print_error "Beta server already running on port $BETA_WS_PORT"
        echo "  Kill it: kill \$(lsof -t -i :$BETA_WS_PORT)"
        exit 1
    fi

    # Optional build step
    if [ "$do_build" = true ]; then
        print_header "Building and Testing"
        build_workspace

        if ! run_tests; then
            print_warning "Tests failed!"
            if ! confirm_action "Continue anyway?"; then
                exit 1
            fi
        fi

        if ! check_native_module; then
            rebuild_native_modules
        fi
    fi

    # Set beta environment
    export TRON_WS_PORT=$BETA_WS_PORT
    export TRON_HEALTH_PORT=$BETA_HEALTH_PORT
    export TRON_BUILD_TIER=beta
    export TRON_EVENT_STORE_DB="$TRON_HOME/db/beta.db"
    export LOG_LEVEL="${LOG_LEVEL:-trace}"
    export NODE_ENV=development

    if [ "$do_tail" = true ]; then
        # Foreground mode (tail logs)
        echo ""
        echo -e "${CYAN}Starting Beta Server (foreground)${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  WebSocket: ws://localhost:$BETA_WS_PORT/ws"
        echo "  Health:    http://localhost:$BETA_HEALTH_PORT/health"
        echo ""
        echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exec node packages/server/dist/index.js
    else
        # Background mode (default)
        echo ""
        echo -e "${CYAN}Starting Beta Server (background)${NC}"

        node packages/server/dist/index.js &
        local pid=$!

        sleep 2

        if kill -0 $pid 2>/dev/null; then
            print_success "Beta server started (PID: $pid)"
            echo "  WebSocket: ws://localhost:$BETA_WS_PORT/ws"
            echo "  Health:    http://localhost:$BETA_HEALTH_PORT/health"
            echo ""
            echo "  Stop with: kill $pid"
            echo "  Tail logs: tron dev -t (after killing current)"
        else
            print_error "Server failed to start"
            exit 1
        fi
    fi
}
```

### 3. Update help text

In `cmd_help()`, change:
```bash
echo "  dev        Build, test, and start beta development server"
```
To:
```bash
echo "  dev        Start beta server (-b to build, -t to tail)"
echo "  build      Build workspace and run tests"
```

## File Modified

| File | Changes |
|------|---------|
| `scripts/tron` | Modify `cmd_dev()`, add `cmd_build()`, update help |

## Verification

```bash
# Test new build command
tron build
# Should: build workspace, run tests, exit

# Test dev without flags (quick start)
tron dev
# Should: start server in background, return to prompt
curl http://localhost:8083/health  # verify running
kill $(lsof -t -i :8082)  # stop it

# Test dev with tail
tron dev -t
# Should: start server in foreground, Ctrl+C to stop

# Test dev with build
tron dev -b
# Should: build, test, then start in background

# Test combined flags
tron dev -bt
# Should: build, test, then start in foreground
```
