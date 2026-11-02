#!/usr/bin/env bash

# lean.sh — Turn off background services an always-on headless Mac doesn't need.
# Mirrors what was switched off by hand on mooses-macbook-server (audited Nov 2026)
# to save memory, CPU and disk churn under heavy build/test load.
# Sourced by .macos (sudo already primed). Safe to re-run. Undo commands inline.

echo "Applying lean background-service defaults..."

###############################################################################
# Spotlight indexing — off on every volume
# Builds, simulators and worktrees churn thousands of files; mds/mdworker
# re-indexing them was the largest idle cost. Finder search by name still works.
# Undo: sudo mdutil -a -i on
###############################################################################

sudo mdutil -a -i off >/dev/null 2>&1 || echo "  mdutil failed; run: sudo mdutil -a -i off"

###############################################################################
# Per-user agents (gui domain). Undo: launchctl enable gui/$UID/<label>
###############################################################################

for label in \
    com.apple.Siri.agent \
    com.apple.assistantd \
    com.apple.FolderActionsDispatcher \
    com.apple.ScriptMenuApp \
    com.apple.appleseed.seedusaged.postinstall \
    com.apple.ManagedClientAgent.enrollagent
do
    launchctl disable "gui/$UID/$label" 2>/dev/null || true
done

###############################################################################
# System daemons. Undo: sudo launchctl enable system/<label>
###############################################################################

for label in \
    com.apple.CSCSupportd \
    com.apple.mdmclient.daemon.runatboot \
    com.apple.ftpd
do
    sudo launchctl disable "system/$label" 2>/dev/null || true
done

###############################################################################
# Time Machine — no local snapshots or backup scans on a server
# Undo: sudo tmutil enable
###############################################################################

sudo tmutil disable 2>/dev/null || true
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

###############################################################################
# Window server — no transparency/motion effects on a headless box
###############################################################################

defaults write com.apple.universalaccess reduceTransparency -bool true 2>/dev/null || true
defaults write com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false

###############################################################################
# No crash/feedback dialogs that block an unattended session
###############################################################################

defaults write com.apple.CrashReporter DialogType -string "none"
defaults write com.apple.appleseed.FeedbackAssistant Autogather -bool false

echo "  Lean defaults applied (logout or restart to take full effect)."
