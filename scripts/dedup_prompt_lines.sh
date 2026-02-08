#!/usr/bin/env bash
# Filter to remove consecutive empty prompt blocks from pane content.
#
# An "empty prompt block" is a ╭...timestamp ╯ line followed by a
# ╰ $ line (with no command), optionally followed by a shell error
# line produced during restore (e.g. bash: [: : integer expression
# expected). Consecutive such blocks accumulate across save/restore
# cycles. This filter collapses runs of them down to just the last
# one.
#
# Also collapses consecutive bare ╭ prompt lines (same-second
# re-draws from shell startup/resize).

exec awk '
function strip_ansi(s) {
    gsub(/\033\[[0-9;]*[A-Za-z]/, "", s)
    return s
}

function is_prompt_top(s) {
    return s ~ /^╭.*[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ╯$/
}

function is_prompt_bottom(s) {
    return s ~ /^╰ \$ *$/
}

function is_restore_noise(s) {
    # Shell errors produced during restore startup
    return s ~ /^bash: \[: : integer expression expected$/ \
        || s ~ /^bash: trap: .*unexpected EOF/ \
        || s ~ /^__ps1: command not found$/
}

function flush_block() {
    if (block_count > 0) {
        # Print only the last block (top + bottom, skip noise)
        print block_top[block_count]
        print block_bot[block_count]
    }
    block_count = 0
    delete block_top
    delete block_bot
}

{
    stripped = strip_ansi($0)
}

# After completing a block, absorb trailing restore noise lines
absorb_noise && is_restore_noise(stripped) {
    # Swallow this line — it belongs to the block we just buffered
    next
}

# Turn off noise absorption on any non-noise line
absorb_noise {
    absorb_noise = 0
}

# State: pending_top is set when we saw a ╭ prompt line and are
# waiting to see if the next line completes an empty block.

pending_top != "" && is_prompt_bottom(stripped) {
    # Complete empty block: buffer it
    block_count++
    block_top[block_count] = pending_top
    block_bot[block_count] = $0
    pending_top = ""
    absorb_noise = 1
    next
}

pending_top != "" && is_prompt_top(stripped) {
    # Another ╭ right after a ╭ (resize re-draw). Replace pending
    # with this newer one; the old one is discarded.
    pending_top = $0
    next
}

pending_top != "" {
    # Previous ╭ line is followed by something other than ╰ $ or
    # another ╭, so it is a real prompt. Flush buffered empty
    # blocks, emit the pending ╭, then handle this line normally.
    flush_block()
    print pending_top
    pending_top = ""
    # fall through to handle current line
}

is_prompt_top(stripped) {
    # Might be start of empty block -- hold it
    pending_top = $0
    next
}

# Regular line: flush any buffered empty blocks, then print
{
    flush_block()
    print
}

END {
    flush_block()
    if (pending_top != "") {
        print pending_top
    }
}
'
