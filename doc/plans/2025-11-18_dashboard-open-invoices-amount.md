# Feature: Display Open Invoices Amount on Dashboard

## Overview
Add a second line to the "Invoiced Total" dashboard card showing the total amount of open (unpaid) invoices. This will provide better visibility into outstanding receivables, matching the pattern used in the "Offered Total" card which shows accepted and pending amounts separately.

## Requirements

### Functional Requirements
- Display the total amount of open invoices as a second line in the "Invoiced Total" card
- Format the amount with currency symbol prefix (€)
- Style the open amount in red (`text-rose-400`) to match the "pending offers" styling
- Maintain the main "Invoiced Total" amount showing ALL invoices (open + paid combined)
- Keep existing card layout and responsive behavior

### Non-Functional Requirements
- No performance impact (calculation already iterates through invoices)
- Consistent styling with existing dashboard cards
- Proper number formatting with thousands separator

## Technical Design

### Architecture
This is a straightforward enhancement to the existing dashboard statistics system. The change follows the established pattern used for offer amounts (accepted vs pending) and applies it to invoices (all vs open).

### Data/State Changes

**Backend Statistics Structure** (`src/web/ep_utils.zig`):
- Add new field `invoices_open_amount: usize = 0` to the `Stats` struct (line ~77)
- Modify the invoice processing logic in `allDocsAndStats()` to accumulate open invoice amounts when `paid_date == null` (around line ~175-184)

**No database changes needed** - this uses existing invoice JSON data (`paid_date` and `total` fields)

### Core Changes

**File: `src/web/ep_utils.zig`**
- **Struct change** (line ~77): Add `invoices_open_amount: usize = 0` field to `Stats` struct
- **Logic change** (lines ~175-184): In the `Invoice` switch case within `allDocsAndStats()`, accumulate `stats.invoices_open_amount += obj.total orelse 0` when invoice is open

**File: `src/web/ep_dashboard.zig`**
- **Template parameter** (lines ~26-83): Format `stats.invoices_open_amount` using `Format.floatThousandsAlloc()` and add it to the params struct as `invoices_open_amount`

**File: `src/web/templates/dashboard.html`**
- **UI change** (first card): Update the "Invoiced Total" card structure to include a second line with the open amount, styled with `text-rose-400` class

### UI/Frontend Changes

**Before:**
```html
<div class="bg-white p-5 rounded-lg shadow-md border border-gray-200">
  <strong class="block text-lg font-semibold text-gray-700 mb-1">Invoiced Total ({{year}})</strong>
  <span id="total-invoiced" class="text-2xl font-bold text-blue-600">{{ currency_symbol }} {{invoiced_total}}</span>
</div>
```

**After:**
```html
<div class="bg-white p-5 rounded-lg shadow-md border border-gray-200">
  <strong class="block text-lg font-semibold text-gray-700 mb-1">Invoiced Total ({{year}})</strong>
  <span id="total-invoiced" class="text-2xl font-bold text-blue-600">
    {{ currency_symbol }} {{invoiced_total}}<br>
    <span class="text-rose-400">{{ currency_symbol }} {{invoices_open_amount}} open</span>
  </span>
</div>
```

This matches the existing pattern from the "Offered Total" card which shows accepted (green) and pending (red) amounts.

### External Dependencies
None - uses existing Tailwind CSS classes and Zig standard library functions.

## Implementation Steps

### 1. Update Stats Structure (2 minutes)
**File**: `src/web/ep_utils.zig` (line ~77)

Add the new field to the `Stats` struct:
```zig
pub const Stats = struct {
    num_invoices_open: isize = 0,
    num_invoices_total: isize = 0,
    num_offers_open: isize = 0,
    num_offers_total: isize = 0,
    invoiced_total_amount: usize = 0,
    invoices_open_amount: usize = 0,              // NEW FIELD
    offers_pending_amount: usize = 0,
    offers_accepted_amount: usize = 0,
};
```

**Testing**: Verify compilation passes with `zig build`

### 2. Update Invoice Statistics Calculation (3 minutes)
**File**: `src/web/ep_utils.zig` (lines ~175-184)

Modify the `Invoice` switch case in `allDocsAndStats()`:
```zig
Invoice => {
    stats.num_invoices_total = @intCast(names.list.len);
    stats.invoiced_total_amount += obj.total orelse 0;
    if (obj.paid_date == null) {
        stats.num_invoices_open += 1;
        stats.invoices_open_amount += obj.total orelse 0;  // NEW LINE
        break :blk "open";
    } else {
        break :blk "paid";
    }
}
```

**Testing**: Build and verify no compilation errors

### 3. Format and Pass Open Amount to Template (3 minutes)
**File**: `src/web/ep_dashboard.zig` (lines ~50-83)

Add formatting and parameter for the new field:
```zig
const params = .{
    .recent_docs = recent_documents,
    .currency_symbol = fj_config.CurrencySymbol,
    .invoices_total = stats.num_invoices_total,
    .invoices_open = stats.num_invoices_open,
    .offers_total = stats.num_offers_total,
    .offers_open = stats.num_offers_open,
    .git_status = status_writer.written(),
    .invoiced_total = try Format.floatThousandsAlloc(...),
    .invoices_open_amount = try Format.floatThousandsAlloc(      // NEW LINE
        fj_config.CurrencyFactor,                                 // NEW LINE
        stats.invoices_open_amount,                               // NEW LINE
        arena,                                                    // NEW LINE
    ),                                                            // NEW LINE
    .offers_accepted_amount = try Format.floatThousandsAlloc(...),
    .offers_pending_amount = try Format.floatThousandsAlloc(...),
    .year = year,
    .company = fj_config.CompanyName,
    .version = Version.version(),
    .fj_home = fj.fj_home.?,
};
```

**Testing**: Build with `zig build`

### 4. Update Dashboard Template (2 minutes)
**File**: `src/web/templates/dashboard.html` (first card in grid)

Update the "Invoiced Total" card HTML:
```html
<div class="bg-white p-5 rounded-lg shadow-md border border-gray-200">
  <strong class="block text-lg font-semibold text-gray-700 mb-1">Invoiced Total ({{year}})</strong>
  <span id="total-invoiced" class="text-2xl font-bold text-blue-600">
    {{ currency_symbol }} {{invoiced_total}}<br>
    <span class="text-rose-400">{{ currency_symbol }} {{invoices_open_amount}} open</span>
  </span>
</div>
```

**Testing**: Visual inspection in browser

### 5. Manual Testing (5 minutes)
1. Build and run the server: `zig build run -- serve --port=3333`
2. Navigate to http://localhost:3333
3. Verify the "Invoiced Total" card shows:
   - First line: Total invoiced amount in blue
   - Second line: Open invoices amount in red with "open" label
4. Test with different data scenarios:
   - All invoices paid (open amount should be €0.00)
   - Mix of paid and unpaid invoices
   - All invoices unpaid (amounts should match)
5. Test responsive layout on mobile/tablet widths
6. Verify number formatting (thousands separator)

## Testing Strategy

### Unit Tests
Not applicable - this feature involves template rendering and doesn't have isolated business logic that warrants unit testing. The calculation logic is straightforward (sum of amounts where `paid_date == null`).

### Integration Tests
Not applicable - fj doesn't currently have automated integration tests for the web UI.

### Manual Testing Checklist
- [ ] Dashboard loads without errors
- [ ] "Invoiced Total" card shows both lines
- [ ] Main amount (blue) equals sum of ALL invoices
- [ ] Open amount (red) equals sum of unpaid invoices
- [ ] Currency symbol appears on both lines
- [ ] Thousands separator works correctly
- [ ] Color matches "pending offers" red (`text-rose-400`)
- [ ] "open" label appears after the amount
- [ ] Layout looks good on desktop (4 columns)
- [ ] Layout looks good on tablet (2 columns)
- [ ] Layout looks good on mobile (1 column)
- [ ] No console errors in browser dev tools

### Edge Cases to Verify
- **All paid**: Open amount shows €0.00
- **All unpaid**: Open amount equals total amount
- **Mixed status**: Numbers add up correctly
- **Zero invoices**: Dashboard doesn't crash (should show €0.00)
- **Large amounts**: Thousands separator works (e.g., €1,234,567.89)

### Performance Testing
Not applicable - no performance concerns for this feature.

## Risks and Mitigations

**Risk 1**: Template syntax error breaks dashboard rendering
- **Mitigation**: Test immediately after HTML changes. Mustache syntax is simple and unlikely to have issues. Server will fail gracefully with error page.

**Risk 2**: Number formatting inconsistency
- **Mitigation**: Use the exact same `Format.floatThousandsAlloc()` function already used for other amounts. This ensures consistency.

**Risk 3**: Color choice might not match user's expectations
- **Mitigation**: Using `text-rose-400` matches the existing pattern for "pending offers" which also represent items requiring attention. This is consistent UX.

## Rollout Plan

### Deployment Steps
1. Ensure current code is working and tested locally
2. Commit changes with message: "Add open invoices amount to dashboard card"
3. If using the fj server in production, restart the server to pick up changes
4. No data migration needed
5. No configuration changes needed

### Backwards Compatibility
- **Template**: Adding a new parameter is backwards compatible
- **Stats struct**: Adding a field with default value (0) is backwards compatible
- **No breaking changes** - all existing functionality remains unchanged

### Rollback Plan
If issues arise after deployment:
1. Revert the git commit: `git revert HEAD`
2. Rebuild: `zig build`
3. Restart server

Since this is a cosmetic dashboard change with no data persistence, rollback is simple and risk-free.

### Monitoring
- Check browser console for JavaScript errors (none expected)
- Verify server logs show no template rendering errors
- User feedback on dashboard usability

## Success Metrics

**Functional Success**:
- Dashboard displays open invoice amounts correctly
- Visual styling matches design intent (red color, proper formatting)
- No errors in server logs or browser console

**Business Success**:
- Users can quickly identify outstanding receivables at a glance
- Improved visibility into cash flow (open invoices represent pending revenue)

## Future Enhancements

Out of scope for this implementation but could be considered later:

1. **Overdue Invoices Tracking**: Highlight overdue invoices separately (requires adding due date field to Invoice JSON)
2. **Paid Invoices Amount**: Show paid amount separately as a third line in green (inverse of current open amount)
3. **Click-through Filtering**: Make the "open" amount clickable to filter the invoices list to show only unpaid invoices
4. **Aging Report**: Group open invoices by age (0-30 days, 30-60 days, 60+ days)
5. **Historical Trend**: Show sparkline or trend indicator for open invoices over time
6. **Currency Conversion**: For multi-currency setups, show total in base currency

## Estimated Total Time

**Implementation**: ~15 minutes (very straightforward changes)
- Backend (steps 1-3): 8 minutes
- Frontend (step 4): 2 minutes
- Testing (step 5): 5 minutes

**Note**: This is a simple feature following established patterns in the codebase. The majority of time will be spent on careful testing and verification rather than actual coding.
