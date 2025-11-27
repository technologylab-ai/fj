# Feature: FJ API Extension Phase 5 - CLI Status Commands

## Overview
This is Phase 5 of the FJ API Extension implementation. It adds CLI commands for updating invoice payment status and offer acceptance/rejection status.

**Depends on**: Phase 1 (data model with `oms_project` field already in place)

## Requirements

### Functional Requirements
- `fj paid <invoice-id>` marks an invoice as paid (sets `paid_date`)
- `fj paid <invoice-id> --date YYYY-MM-DD` sets a specific paid date
- `fj offer accept <offer-id>` marks an offer as accepted (sets `accepted_date`)
- `fj offer reject <offer-id>` marks an offer as rejected (sets `declined_date`)
- All commands update the meta.json in-place and commit the change to git

### Non-Functional Requirements
- Commands work on committed documents (in FJ_HOME)
- Git commit message describes the status change
- Validation: cannot mark already-paid invoice as paid again (unless --force)
- Consistent with existing CLI patterns

## Technical Design

### New CLI Commands

#### 1. `fj paid` Command

```zig
// src/cli.zig - New PaidCommand
pub const PaidCommand = struct {
    fj_home: ?[]const u8 = null,
    date: ?[]const u8 = null,  // YYYY-MM-DD format
    force: bool = false,

    positional: struct {
        invoice_id: []const u8,
    },

    pub const aliases = .{
        .fj_home = "C",
    };

    pub const help =
        \\ Command: paid
        \\
        \\ Usage:
        \\
        \\ fj paid <invoice-id> [--date=YYYY-MM-DD] [--force]
        \\
        \\ Marks an invoice as paid. Sets paid_date in meta.json.
        \\
        \\ Examples:
        \\
        \\   fj paid 2025-047              # Mark as paid today
        \\   fj paid 2025-047 --date 2025-12-01  # Mark paid on specific date
        \\
        \\ Options:
        \\
        \\ --date=YYYY-MM-DD     Date when payment was received
        \\                       Default: today
        \\
        \\ --force               Mark as paid even if already paid
        \\
        \\ -h, --help            Displays this help message then exits.
        \\
        \\ -C, --fj_home         The FJ_HOME dir to use.
        \\                       Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};
```

#### 2. Extended `fj offer` Command

Add `accept` and `reject` subcommands to existing OfferCommand:

```zig
// Modify src/cli.zig - OfferCommand
pub const OfferCommand = struct {
    fj_home: ?[]const u8 = null,
    project: ?[]const u8 = null,
    omsproject: ?[]const u8 = null,  // NEW: OMS project link
    rates: ?[]const u8 = null,
    to: ?[]const u8 = null,
    date: ?[]const u8 = null,  // NEW: for accept/reject date

    force: bool = false,

    positional: struct {
        subcommand: enum {
            new,
            checkout,
            commit,
            list,
            show,
            open,
            compile,
            accept,   // NEW
            reject,   // NEW
        },
        arg: ?[]const u8 = null,
    },

    // ... help text updated with new subcommands
};
```

### Implementation in fj.zig

#### `cmdMarkInvoicePaid()`

```zig
pub fn cmdMarkInvoicePaid(self: *Fj, command: PaidCommand) !void {
    const invoice_id = command.positional.invoice_id;

    // Find the invoice directory
    const invoice_dir = try self.findDocumentById(Invoice, invoice_id);
    const meta_path = try std.fs.path.join(self.arena, &.{
        self.fj_home, "invoices", invoice_dir, "invoice.json"
    });

    // Read current meta.json
    const meta_contents = try std.fs.cwd().readFileAlloc(self.arena, meta_path, 1024 * 1024);
    var invoice = try std.json.parseFromSliceLeaky(Invoice, self.arena, meta_contents, .{});

    // Check if already paid
    if (invoice.paid_date != null and !command.force) {
        return Fatal.fatal("Invoice {s} is already marked as paid on {s}. Use --force to override.",
            .{ invoice_id, invoice.paid_date.? });
    }

    // Set paid_date
    const paid_date = command.date orelse try self.getTodayString();
    invoice.paid_date = paid_date;
    invoice.updated = try self.getTimestamp();

    // Write updated meta.json
    const json_output = try std.json.stringifyAlloc(self.arena, invoice, .{ .whitespace = .indent_2 });
    try std.fs.cwd().writeFile(.{ .path = meta_path, .data = json_output });

    // Git commit
    var git = Git.init(self.arena, self.fj_home);
    try git.add(meta_path);
    const commit_msg = try std.fmt.allocPrint(self.arena,
        "Mark invoice {s} as paid ({s})", .{ invoice_id, paid_date });
    try git.commit(commit_msg);

    std.debug.print("Invoice {s} marked as paid ({s})\n", .{ invoice_id, paid_date });
}
```

#### `cmdUpdateOfferStatus()`

```zig
pub fn cmdUpdateOfferStatus(self: *Fj, command: OfferCommand, action: enum { accept, reject }) !void {
    const offer_id = command.positional.arg orelse return Fatal.fatal("Offer ID required", .{});

    // Find the offer directory
    const offer_dir = try self.findDocumentById(Offer, offer_id);
    const meta_path = try std.fs.path.join(self.arena, &.{
        self.fj_home, "offers", offer_dir, "offer.json"
    });

    // Read current meta.json
    const meta_contents = try std.fs.cwd().readFileAlloc(self.arena, meta_path, 1024 * 1024);
    var offer = try std.json.parseFromSliceLeaky(Offer, self.arena, meta_contents, .{});

    const date = command.date orelse try self.getTodayString();

    switch (action) {
        .accept => {
            if (offer.accepted_date != null and !command.force) {
                return Fatal.fatal("Offer {s} is already accepted on {s}. Use --force to override.",
                    .{ offer_id, offer.accepted_date.? });
            }
            if (offer.declined_date != null and !command.force) {
                return Fatal.fatal("Offer {s} was rejected on {s}. Use --force to override.",
                    .{ offer_id, offer.declined_date.? });
            }
            offer.accepted_date = date;
            offer.declined_date = null;  // Clear rejection if any
        },
        .reject => {
            if (offer.declined_date != null and !command.force) {
                return Fatal.fatal("Offer {s} is already rejected on {s}. Use --force to override.",
                    .{ offer_id, offer.declined_date.? });
            }
            if (offer.accepted_date != null and !command.force) {
                return Fatal.fatal("Offer {s} was accepted on {s}. Use --force to override.",
                    .{ offer_id, offer.accepted_date.? });
            }
            offer.declined_date = date;
            offer.accepted_date = null;  // Clear acceptance if any
        },
    }

    offer.updated = try self.getTimestamp();

    // Write updated meta.json
    const json_output = try std.json.stringifyAlloc(self.arena, offer, .{ .whitespace = .indent_2 });
    try std.fs.cwd().writeFile(.{ .path = meta_path, .data = json_output });

    // Git commit
    var git = Git.init(self.arena, self.fj_home);
    try git.add(meta_path);
    const action_str = switch (action) { .accept => "accepted", .reject => "rejected" };
    const commit_msg = try std.fmt.allocPrint(self.arena,
        "Mark offer {s} as {s} ({s})", .{ offer_id, action_str, date });
    try git.commit(commit_msg);

    std.debug.print("Offer {s} marked as {s} ({s})\n", .{ offer_id, action_str, date });
}
```

### Main Dispatch (src/main.zig)

```zig
// Add to the main switch
.paid => |command| {
    var fj = Fj.init(arena, fj_home);
    try fj.cmdMarkInvoicePaid(command);
},
.offer => |command| {
    var fj = Fj.init(arena, fj_home);
    switch (command.positional.subcommand) {
        .accept => try fj.cmdUpdateOfferStatus(command, .accept),
        .reject => try fj.cmdUpdateOfferStatus(command, .reject),
        // ... existing subcommands
    }
},
```

## Implementation Steps

### 1. Add PaidCommand to cli.zig (10 minutes)
**File**: `src/cli.zig`

**Actions**:
- Create `PaidCommand` struct with `invoice_id` positional, `date` and `force` options
- Add `paid: PaidCommand` to `Cli` union
- Update main help text

**Testing**:
- `zig build` succeeds
- `fj paid --help` shows help text

### 2. Extend OfferCommand in cli.zig (10 minutes)
**File**: `src/cli.zig`

**Actions**:
- Add `accept` and `reject` to subcommand enum
- Add `date: ?[]const u8 = null` option
- Update help text with new subcommands

**Testing**:
- `zig build` succeeds
- `fj offer --help` shows accept/reject subcommands

### 3. Implement cmdMarkInvoicePaid in fj.zig (25 minutes)
**File**: `src/fj.zig`

**Actions**:
- Add `cmdMarkInvoicePaid()` method
- Read invoice meta.json
- Validate not already paid (unless --force)
- Set `paid_date` field
- Write meta.json back
- Git add and commit

**Testing**:
- `fj paid 2025-001` marks invoice as paid
- Running again shows "already paid" error
- `fj paid 2025-001 --force` overrides

### 4. Implement cmdUpdateOfferStatus in fj.zig (25 minutes)
**File**: `src/fj.zig`

**Actions**:
- Add `cmdUpdateOfferStatus()` method
- Read offer meta.json
- Validate status transitions
- Set `accepted_date` or `declined_date`
- Write meta.json back
- Git add and commit

**Testing**:
- `fj offer accept 2025-008` marks offer as accepted
- `fj offer reject 2025-009` marks offer as rejected
- Conflicting status shows error

### 5. Add dispatch in main.zig (10 minutes)
**File**: `src/main.zig`

**Actions**:
- Add `.paid` case to main switch
- Add `.accept` and `.reject` cases to offer subcommand switch

**Testing**:
- All commands work end-to-end

### 6. Add helper methods to fj.zig (10 minutes)
**File**: `src/fj.zig`

**Actions**:
- Add `getTodayString()` helper (YYYY-MM-DD format)
- Add `getTimestamp()` helper (ISO8601 format for `updated` field)

**Testing**:
- Dates are formatted correctly

## CLI Usage Examples

```bash
# Mark invoice as paid (today)
fj paid 2025-047
# Output: Invoice 2025-047 marked as paid (2025-11-27)

# Mark invoice as paid on specific date
fj paid 2025-047 --date 2025-12-01
# Output: Invoice 2025-047 marked as paid (2025-12-01)

# Try to mark already-paid invoice
fj paid 2025-047
# Output: Error: Invoice 2025-047 is already marked as paid on 2025-12-01. Use --force to override.

# Force override
fj paid 2025-047 --date 2025-12-02 --force
# Output: Invoice 2025-047 marked as paid (2025-12-02)

# Accept an offer
fj offer accept 2025-008
# Output: Offer 2025-008 marked as accepted (2025-11-27)

# Reject an offer
fj offer reject 2025-009
# Output: Offer 2025-009 marked as rejected (2025-11-27)

# Try to accept already-rejected offer
fj offer accept 2025-009
# Output: Error: Offer 2025-009 was rejected on 2025-11-27. Use --force to override.
```

## Git Commit Messages

The commands generate descriptive git commit messages:

```
Mark invoice 2025-047 as paid (2025-12-01)
Mark offer 2025-008 as accepted (2025-11-27)
Mark offer 2025-009 as rejected (2025-11-27)
```

## Testing Strategy

### Manual Testing Checklist
- [ ] `fj paid --help` shows correct help
- [ ] `fj offer --help` shows accept/reject subcommands
- [ ] `fj paid <id>` sets paid_date to today
- [ ] `fj paid <id> --date YYYY-MM-DD` sets specific date
- [ ] `fj paid <id>` on already-paid invoice shows error
- [ ] `fj paid <id> --force` overrides existing paid_date
- [ ] `fj offer accept <id>` sets accepted_date
- [ ] `fj offer reject <id>` sets declined_date
- [ ] `fj offer accept <id>` on rejected offer shows error
- [ ] `fj offer accept <id> --force` overrides rejection
- [ ] Git log shows correct commit messages
- [ ] meta.json `updated` field is updated

### Edge Cases
- Invoice/Offer ID not found → helpful error message
- Invalid date format → validation error
- No write permission on FJ_HOME → appropriate error
- Git not initialized → appropriate error

## Risks and Mitigations

### Risk 1: Data loss on force override
**Risk**: Using `--force` could accidentally clear important dates
**Mitigation**: Show previous value in output when using --force

### Risk 2: Date validation
**Risk**: Invalid date format could corrupt meta.json
**Mitigation**: Validate YYYY-MM-DD format before writing

### Risk 3: Git commit failure
**Risk**: Git commit could fail, leaving inconsistent state
**Mitigation**: Validate git status before making changes; rollback on failure

## Success Metrics
- [ ] `fj paid` command works correctly
- [ ] `fj offer accept` command works correctly
- [ ] `fj offer reject` command works correctly
- [ ] All status changes are committed to git
- [ ] Error messages are clear and helpful
- [ ] `--force` flag works for overrides
- [ ] `--date` option allows custom dates

## Future Enhancements
- `fj unpaid <invoice-id>` to revert payment status
- `fj offer send <offer-id>` to mark as sent (sets `date` if not already set)
- Batch operations: `fj paid --all-overdue`
- Status history tracking (log of all status changes)
